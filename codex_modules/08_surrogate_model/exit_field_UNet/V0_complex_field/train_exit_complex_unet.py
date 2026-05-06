import argparse
import json
import math
import random
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import scipy.io as sio
import torch
import torch.nn.functional as F
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

from train_exit_complex_gpu import default_data_dir


def parse_args():
    parser = argparse.ArgumentParser(description="Train a tile-based CNN/U-Net surrogate for full exit complex fields.")
    parser.add_argument("--data-dir", default=None, help="Defaults to <script_dir>/modulation_law_dataset.")
    parser.add_argument("--output-dir", default=None, help="Defaults to <data-dir>/unet_model_outputs.")
    parser.add_argument("--case", default="case_004_same_bias-0.79_layer+0_round", help="Holdout case substring.")
    parser.add_argument("--target", choices=["complex_ratio_opposite", "complex_ratio_same"], default="complex_ratio_opposite")
    parser.add_argument("--epochs", type=int, default=120)
    parser.add_argument("--steps-per-epoch", type=int, default=600)
    parser.add_argument("--batch-size", type=int, default=8)
    parser.add_argument("--tile-size", type=int, default=128)
    parser.add_argument("--base-channels", type=int, default=32)
    parser.add_argument("--lr", type=float, default=8e-4)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--random-seed", type=int, default=42)
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--amp", action="store_true", help="Use CUDA mixed precision.")
    parser.add_argument("--eval-every", type=int, default=10)
    parser.add_argument("--patience", type=int, default=20)
    parser.add_argument("--max-runs", type=int, default=0, help="0 means all field-validation runs.")
    return parser.parse_args()


def find_field_files(data_dir: Path, max_runs: int):
    files = sorted(data_dir.rglob("*_field_validation.mat"))
    if not files:
        raise FileNotFoundError(f"No *_field_validation.mat files found below {data_dir}")
    if max_runs:
        files = files[: max(1, int(max_runs))]
    return files


def matlab_attr(struct_value, name, default=None):
    return getattr(struct_value, name, default)


def safe_norm(arr, scale=1.0):
    out = np.asarray(arr, dtype=np.float32) / float(scale)
    out[~np.isfinite(out)] = 0
    return out


def load_field_case(path: Path, target: str):
    data = sio.loadmat(path, squeeze_me=True, struct_as_record=False)
    meta = data.get("run_meta")
    run_name = str(matlab_attr(meta, "run_label", path.parent.name))
    mask = np.asarray(data["valid_mask"]).astype(np.float32)
    thickness = np.asarray(data["thickness_map"], dtype=np.float32)
    layers = np.asarray(data["net_num_board"], dtype=np.float32)
    phase = np.asarray(data["board_phase"], dtype=np.float32)
    grad = np.asarray(data["thickness_grad_norm"], dtype=np.float32)
    local_mean = np.asarray(data["local_thickness_mean"], dtype=np.float32)
    local_std = np.asarray(data["local_thickness_std"], dtype=np.float32)
    edge = np.asarray(data["aperture_edge_distance_mm"], dtype=np.float32)
    x_mm = np.asarray(data["x_mm"], dtype=np.float32).reshape(-1)
    y_mm = np.asarray(data["y_mm"], dtype=np.float32).reshape(-1)
    x_norm = x_mm / (np.max(np.abs(x_mm)) + 1e-6)
    y_norm = y_mm / (np.max(np.abs(y_mm)) + 1e-6)
    X_norm, Y_norm = np.meshgrid(x_norm, y_norm)

    meta_dx = float(matlab_attr(meta, "dx", 1.0))
    meta_dz = float(matlab_attr(meta, "dz", meta_dx))
    f0 = float(matlab_attr(meta, "f0", 4.5e6))
    c_water = float(matlab_attr(meta, "c_water", 1480.0))
    c_board = float(matlab_attr(meta, "c_board", 2430.0))
    rho_water = float(matlab_attr(meta, "density_water", 997.0))
    rho_board = float(matlab_attr(meta, "density_board", 1100.0))
    z_exit_mm = float(matlab_attr(meta, "z_exit_probe_offset_mm", 4.0))
    lambda_water = c_water / f0
    k_water_dx = 2 * math.pi * f0 / c_water * meta_dx
    k_board_dx = 2 * math.pi * f0 / c_board * meta_dx
    phase_step = (2 * math.pi * f0 / c_water - 2 * math.pi * f0 / c_board) * meta_dz
    impedance_ratio = (rho_board * c_board) / (rho_water * c_water)
    exit_z_over_lambda = (z_exit_mm * 1e-3) / lambda_water

    phys = [
        phase_step / math.pi,
        k_water_dx,
        k_board_dx,
        impedance_ratio,
        exit_z_over_lambda / 20.0,
    ]
    h, w = mask.shape
    phys_maps = [np.full((h, w), value, dtype=np.float32) for value in phys]
    edge_norm = edge / (np.nanmax(edge[mask > 0]) + 1e-6)
    layer_norm = layers / (np.nanmax(layers[mask > 0]) + 1e-6)
    inputs = np.stack(
        [
            safe_norm(thickness, 1e-3),
            layer_norm,
            np.sin(phase).astype(np.float32),
            np.cos(phase).astype(np.float32),
            grad,
            safe_norm(local_mean, 1e-3),
            local_std,
            edge_norm,
            mask,
            X_norm.astype(np.float32),
            Y_norm.astype(np.float32),
            *phys_maps,
        ],
        axis=0,
    )
    if target == "complex_ratio_same":
        target_real = np.asarray(data["ratio_same_real"], dtype=np.float32)
        target_imag = np.asarray(data["ratio_same_imag"], dtype=np.float32)
    else:
        target_real = np.asarray(data["ratio_opposite_real"], dtype=np.float32)
        target_imag = np.asarray(data["ratio_opposite_imag"], dtype=np.float32)
    target_map = np.stack([target_real, target_imag], axis=0)
    inputs[:, mask == 0] = 0
    target_map[:, mask == 0] = 0
    return {
        "run_name": run_name,
        "path": str(path),
        "input": inputs.astype(np.float32),
        "target": target_map.astype(np.float32),
        "mask": mask.astype(np.float32)[None, :, :],
    }


class ConvBlock(torch.nn.Module):
    def __init__(self, in_ch, out_ch):
        super().__init__()
        self.block = torch.nn.Sequential(
            torch.nn.Conv2d(in_ch, out_ch, kernel_size=3, padding=1),
            torch.nn.GroupNorm(8 if out_ch >= 8 else 1, out_ch),
            torch.nn.SiLU(),
            torch.nn.Conv2d(out_ch, out_ch, kernel_size=3, padding=1),
            torch.nn.GroupNorm(8 if out_ch >= 8 else 1, out_ch),
            torch.nn.SiLU(),
        )

    def forward(self, x):
        return self.block(x)


class SmallUNet(torch.nn.Module):
    def __init__(self, in_channels, out_channels=2, base_channels=32):
        super().__init__()
        b = int(base_channels)
        self.enc1 = ConvBlock(in_channels, b)
        self.enc2 = ConvBlock(b, b * 2)
        self.enc3 = ConvBlock(b * 2, b * 4)
        self.pool = torch.nn.MaxPool2d(2)
        self.mid = ConvBlock(b * 4, b * 4)
        self.up2 = torch.nn.ConvTranspose2d(b * 4, b * 2, kernel_size=2, stride=2)
        self.dec2 = ConvBlock(b * 4, b * 2)
        self.up1 = torch.nn.ConvTranspose2d(b * 2, b, kernel_size=2, stride=2)
        self.dec1 = ConvBlock(b * 2, b)
        self.out = torch.nn.Conv2d(b, out_channels, kernel_size=1)

    def forward(self, x):
        e1 = self.enc1(x)
        e2 = self.enc2(self.pool(e1))
        e3 = self.enc3(self.pool(e2))
        m = self.mid(e3)
        d2 = self.up2(m)
        if d2.shape[-2:] != e2.shape[-2:]:
            d2 = F.interpolate(d2, size=e2.shape[-2:], mode="bilinear", align_corners=False)
        d2 = self.dec2(torch.cat([d2, e2], dim=1))
        d1 = self.up1(d2)
        if d1.shape[-2:] != e1.shape[-2:]:
            d1 = F.interpolate(d1, size=e1.shape[-2:], mode="bilinear", align_corners=False)
        d1 = self.dec1(torch.cat([d1, e1], dim=1))
        return self.out(d1)


def split_cases(cases, holdout_query):
    holdout = [case for case in cases if holdout_query in case["run_name"] or holdout_query in case["path"]]
    if not holdout:
        holdout = [cases[0]]
    holdout_paths = {case["path"] for case in holdout}
    train = [case for case in cases if case["path"] not in holdout_paths]
    if not train:
        train = holdout
    return train, holdout


def compute_channel_stats(cases):
    channels = cases[0]["input"].shape[0]
    total = 0
    mean = np.zeros((channels,), dtype=np.float64)
    var = np.zeros((channels,), dtype=np.float64)
    for case in cases:
        mask = case["mask"][0] > 0
        x = case["input"][:, mask]
        total += x.shape[1]
        mean += x.sum(axis=1)
        var += (x**2).sum(axis=1)
    mean /= max(total, 1)
    var = var / max(total, 1) - mean**2
    std = np.sqrt(np.maximum(var, 1e-8))
    return mean.astype(np.float32)[:, None, None], std.astype(np.float32)[:, None, None]


def normalize_cases(cases, x_mean, x_std):
    for case in cases:
        case["input_norm"] = ((case["input"] - x_mean) / x_std).astype(np.float32)


def sample_tile(case, tile_size):
    mask = case["mask"][0]
    h, w = mask.shape
    if h <= tile_size or w <= tile_size:
        r0 = max(0, (h - tile_size) // 2)
        c0 = max(0, (w - tile_size) // 2)
    else:
        ys, xs = np.where(mask > 0)
        center_idx = random.randrange(len(ys))
        cy, cx = int(ys[center_idx]), int(xs[center_idx])
        r0 = min(max(cy - tile_size // 2, 0), h - tile_size)
        c0 = min(max(cx - tile_size // 2, 0), w - tile_size)
    sl = (slice(r0, r0 + tile_size), slice(c0, c0 + tile_size))
    x = case["input_norm"][:, sl[0], sl[1]]
    y = case["target"][:, sl[0], sl[1]]
    m = case["mask"][:, sl[0], sl[1]]
    return x, y, m


def make_batch(cases, batch_size, tile_size, device):
    xs, ys, masks = [], [], []
    for _ in range(batch_size):
        case = random.choice(cases)
        x, y, m = sample_tile(case, tile_size)
        xs.append(x)
        ys.append(y)
        masks.append(m)
    return (
        torch.from_numpy(np.stack(xs)).to(device),
        torch.from_numpy(np.stack(ys)).to(device),
        torch.from_numpy(np.stack(masks)).to(device),
    )


def masked_smooth_l1(pred, target, mask):
    loss = F.smooth_l1_loss(pred, target, reduction="none", beta=0.5)
    loss = loss * mask
    return loss.sum() / (mask.sum() * pred.shape[1] + 1e-6)


def complex_metrics(y_true, y_pred):
    true_complex = y_true[:, 0] + 1j * y_true[:, 1]
    pred_complex = y_pred[:, 0] + 1j * y_pred[:, 1]
    phase_err = np.angle(pred_complex * np.conj(true_complex))
    return {
        "r2": float(r2_score(y_true, y_pred, multioutput="uniform_average")),
        "mae": float(mean_absolute_error(y_true, y_pred)),
        "rmse": float(math.sqrt(mean_squared_error(y_true, y_pred))),
        "amp_r2": float(r2_score(np.abs(true_complex), np.abs(pred_complex))),
        "phase_mae_rad": float(np.mean(np.abs(phase_err))),
        "coherence": float(np.abs(np.mean(np.exp(1j * phase_err)))),
    }


def predict_case(model, case, device):
    model.eval()
    x = torch.from_numpy(case["input_norm"][None]).to(device)
    with torch.no_grad():
        pred = model(x).cpu().numpy()[0]
    mask = case["mask"][0] > 0
    y_true = np.stack([case["target"][0, mask], case["target"][1, mask]], axis=1)
    y_pred = np.stack([pred[0, mask], pred[1, mask]], axis=1)
    return y_true, y_pred, pred


def evaluate(model, cases, device):
    all_true, all_pred = [], []
    per_case = {}
    for case in cases:
        y_true, y_pred, _ = predict_case(model, case, device)
        per_case[case["run_name"]] = complex_metrics(y_true, y_pred)
        all_true.append(y_true)
        all_pred.append(y_pred)
    return complex_metrics(np.concatenate(all_true, axis=0), np.concatenate(all_pred, axis=0)), per_case


def plot_prediction_maps(output_dir, case, pred):
    output_dir.mkdir(parents=True, exist_ok=True)
    mask = case["mask"][0] > 0
    for name, image in [
        ("unet_pred_ratio_amp", np.abs(pred[0] + 1j * pred[1])),
        ("unet_actual_ratio_amp", np.abs(case["target"][0] + 1j * case["target"][1])),
        ("unet_phase_error_rad", np.angle((pred[0] + 1j * pred[1]) * np.conj(case["target"][0] + 1j * case["target"][1]))),
    ]:
        img = np.asarray(image, dtype=np.float32).copy()
        img[~mask] = np.nan
        fig, ax = plt.subplots(figsize=(6, 5.2), constrained_layout=True)
        im = ax.imshow(img, origin="upper", cmap="viridis" if "phase" not in name else "twilight")
        ax.set_title(name)
        ax.set_xticks([])
        ax.set_yticks([])
        fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
        fig.savefig(output_dir / f"{name}.png", dpi=180)
        plt.close(fig)


def main():
    args = parse_args()
    random.seed(args.random_seed)
    np.random.seed(args.random_seed)
    torch.manual_seed(args.random_seed)
    data_dir = Path(args.data_dir) if args.data_dir else default_data_dir()
    output_dir = Path(args.output_dir) if args.output_dir else data_dir / "unet_model_outputs"
    output_dir.mkdir(parents=True, exist_ok=True)
    requested_device = args.device
    if requested_device.startswith("cuda") and not torch.cuda.is_available():
        requested_device = "cpu"
    device = torch.device(requested_device)
    files = find_field_files(data_dir, args.max_runs)
    print(f"[INFO] Loading {len(files)} field case(s) from {data_dir}", flush=True)
    cases = [load_field_case(path, args.target) for path in files]
    train_cases, holdout_cases = split_cases(cases, args.case)
    x_mean, x_std = compute_channel_stats(train_cases)
    normalize_cases(train_cases + holdout_cases, x_mean, x_std)
    print(
        f"[INFO] Device={device} | train_cases={len(train_cases)} | holdout_cases={len(holdout_cases)} "
        f"| input_channels={cases[0]['input'].shape[0]} | tile={args.tile_size}",
        flush=True,
    )
    print(f"[INFO] Holdout run(s): {', '.join(case['run_name'] for case in holdout_cases)}", flush=True)

    model = SmallUNet(cases[0]["input"].shape[0], 2, args.base_channels).to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    scaler = torch.cuda.amp.GradScaler(enabled=args.amp and device.type == "cuda")
    best_metrics = None
    best_state = None
    best_r2 = -np.inf
    stale_evals = 0
    history = []
    for epoch in range(1, args.epochs + 1):
        model.train()
        total_loss = 0.0
        for _ in range(args.steps_per_epoch):
            xb, yb, mb = make_batch(train_cases, args.batch_size, args.tile_size, device)
            optimizer.zero_grad(set_to_none=True)
            with torch.cuda.amp.autocast(enabled=args.amp and device.type == "cuda"):
                pred = model(xb)
                loss = masked_smooth_l1(pred, yb, mb)
            scaler.scale(loss).backward()
            scaler.step(optimizer)
            scaler.update()
            total_loss += float(loss.item())
        do_eval = epoch == 1 or epoch % args.eval_every == 0 or epoch == args.epochs
        if do_eval:
            metrics, per_case = evaluate(model, holdout_cases, device)
            history.append({"epoch": epoch, "train_loss": total_loss / args.steps_per_epoch, "metrics": metrics})
            print(
                f"[{epoch:03d}/{args.epochs}] loss={history[-1]['train_loss']:.5f} "
                f"R2={metrics['r2']:.4f} MAE={metrics['mae']:.4f} RMSE={metrics['rmse']:.4f} "
                f"amp_R2={metrics['amp_r2']:.4f} phase_MAE={metrics['phase_mae_rad']:.4f}",
                flush=True,
            )
            if metrics["r2"] > best_r2:
                best_r2 = metrics["r2"]
                best_metrics = metrics
                best_state = {key: value.detach().cpu().clone() for key, value in model.state_dict().items()}
                stale_evals = 0
            else:
                stale_evals += 1
                if stale_evals >= args.patience:
                    print(f"[INFO] Early stopping after {stale_evals} stale evals.", flush=True)
                    break

    if best_state is not None:
        model.load_state_dict(best_state)
    final_metrics, per_case = evaluate(model, holdout_cases, device)
    y_true, y_pred, pred_map = predict_case(model, holdout_cases[0], device)
    plot_prediction_maps(output_dir, holdout_cases[0], pred_map)
    report = {
        "target": args.target,
        "device": str(device),
        "epochs": args.epochs,
        "steps_per_epoch": args.steps_per_epoch,
        "batch_size": args.batch_size,
        "tile_size": args.tile_size,
        "base_channels": args.base_channels,
        "amp": bool(args.amp),
        "train_runs": [case["run_name"] for case in train_cases],
        "holdout_runs": [case["run_name"] for case in holdout_cases],
        "input_channels": int(cases[0]["input"].shape[0]),
        "best_metrics": best_metrics,
        "final_metrics": final_metrics,
        "per_case": per_case,
        "history": history,
        "field_paths": [case["path"] for case in cases],
    }
    torch.save(
        {
            "model_state_dict": best_state if best_state is not None else model.state_dict(),
            "input_channels": int(cases[0]["input"].shape[0]),
            "base_channels": args.base_channels,
            "x_mean": x_mean.astype(np.float32),
            "x_std": x_std.astype(np.float32),
            "target": args.target,
        },
        output_dir / "exit_complex_unet.pt",
    )
    (output_dir / "unet_surrogate_report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(
        "[OK] U-Net training complete | "
        f"R2={final_metrics['r2']:.4f} MAE={final_metrics['mae']:.4f} RMSE={final_metrics['rmse']:.4f}",
        flush=True,
    )
    print(f"Outputs written to: {output_dir}", flush=True)


if __name__ == "__main__":
    main()
