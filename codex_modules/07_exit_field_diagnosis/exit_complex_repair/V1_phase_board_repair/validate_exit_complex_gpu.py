import argparse
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import scipy.io as sio
import torch
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

from train_exit_complex_gpu import ExitMLP, default_data_dir, load_sample_file


def parse_args():
    parser = argparse.ArgumentParser(
        description="Validate a trained exit-complex GPU surrogate on sample points or full exit fields."
    )
    parser.add_argument("--data-dir", default=None, help="Defaults to <script_dir>/modulation_law_dataset.")
    parser.add_argument("--model-path", default=None, help="Defaults to <data-dir>/gpu_model_outputs/exit_complex_mlp.pt.")
    parser.add_argument("--case", default="case_004_same_bias-0.79_layer+0_round", help="Case directory name or substring.")
    parser.add_argument("--mode", choices=["auto", "sample", "field"], default="auto")
    parser.add_argument("--target", choices=["complex_ratio_opposite", "complex_ratio_same", "amp"], default="complex_ratio_opposite")
    parser.add_argument("--max-samples", type=int, default=0, help="0 means all selected samples or pixels.")
    parser.add_argument("--batch-size", type=int, default=32768)
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--output-dir", default=None)
    return parser.parse_args()


def find_case_file(data_dir: Path, case_query: str, suffix: str):
    files = sorted(data_dir.rglob(f"*{suffix}"))
    if not files:
        return None
    matches = [path for path in files if case_query in str(path)]
    if not matches:
        return None
    return sorted(matches, key=lambda p: p.stat().st_mtime, reverse=True)[0]


def load_model(model_path: Path, device):
    checkpoint = torch.load(model_path, map_location=device)
    model = ExitMLP(
        int(checkpoint["input_dim"]),
        int(checkpoint["output_dim"]),
        checkpoint["hidden"],
        float(checkpoint["dropout"]),
    ).to(device)
    model.load_state_dict(checkpoint["model_state_dict"])
    model.eval()
    return model, checkpoint


def predict(model, checkpoint, X, device, batch_size):
    x_mean = np.asarray(checkpoint["x_mean"], dtype=np.float32)
    x_std = np.asarray(checkpoint["x_std"], dtype=np.float32)
    y_mean = torch.from_numpy(np.asarray(checkpoint["y_mean"], dtype=np.float32)).to(device)
    y_std = torch.from_numpy(np.asarray(checkpoint["y_std"], dtype=np.float32)).to(device)
    Xn = (X.astype(np.float32) - x_mean) / x_std
    Xt = torch.from_numpy(Xn)
    preds = []
    with torch.no_grad():
        for start in range(0, Xt.shape[0], batch_size):
            xb = Xt[start : start + batch_size].to(device, non_blocking=True)
            pred = model(xb) * y_std + y_mean
            preds.append(pred.cpu().numpy())
    return np.concatenate(preds, axis=0)


def metrics_for(y_true, y_pred, target_names):
    report = {
        "r2": float(r2_score(y_true, y_pred, multioutput="uniform_average")),
        "mae": float(mean_absolute_error(y_true, y_pred)),
        "rmse": float(np.sqrt(mean_squared_error(y_true, y_pred))),
        "per_dim": {},
    }
    for idx, name in enumerate(target_names):
        report["per_dim"][name] = {
            "r2": float(r2_score(y_true[:, idx], y_pred[:, idx])),
            "mae": float(mean_absolute_error(y_true[:, idx], y_pred[:, idx])),
            "rmse": float(np.sqrt(mean_squared_error(y_true[:, idx], y_pred[:, idx]))),
        }
    if y_true.shape[1] == 2:
        report["complex"] = complex_metrics(y_true[:, 0] + 1j * y_true[:, 1], y_pred[:, 0] + 1j * y_pred[:, 1])
    return report


def complex_metrics(true_complex, pred_complex):
    amp_true = np.abs(true_complex)
    amp_pred = np.abs(pred_complex)
    phase_err = np.angle(pred_complex * np.conj(true_complex))
    return {
        "amp_r2": float(r2_score(amp_true, amp_pred)),
        "amp_mae": float(mean_absolute_error(amp_true, amp_pred)),
        "phase_mae_rad": float(np.mean(np.abs(phase_err))),
        "phase_rmse_rad": float(np.sqrt(np.mean(phase_err**2))),
        "coherence": float(np.abs(np.mean(np.exp(1j * phase_err)))),
    }


def plot_scatter(output_dir: Path, y_true, y_pred, target_names, prefix="validate"):
    output_dir.mkdir(parents=True, exist_ok=True)
    for idx, name in enumerate(target_names):
        fig, ax = plt.subplots(figsize=(5.4, 5.4), constrained_layout=True)
        ax.scatter(y_true[:, idx], y_pred[:, idx], s=8, alpha=0.35)
        lo = float(min(np.min(y_true[:, idx]), np.min(y_pred[:, idx])))
        hi = float(max(np.max(y_true[:, idx]), np.max(y_pred[:, idx])))
        pad = 0.05 * max(hi - lo, 1e-6)
        ax.plot([lo - pad, hi + pad], [lo - pad, hi + pad], "k--", linewidth=1.0)
        ax.set_xlim(lo - pad, hi + pad)
        ax.set_ylim(lo - pad, hi + pad)
        ax.grid(True, alpha=0.25)
        ax.set_xlabel("Measured k-Wave target")
        ax.set_ylabel("Predicted surrogate target")
        ax.set_title(f"Exit complex surrogate validation: {name}")
        fig.savefig(output_dir / f"{prefix}_true_vs_pred_{name}.png", dpi=180)
        plt.close(fig)


def plot_map(output_dir: Path, name: str, image, mask=None, cmap="viridis"):
    output_dir.mkdir(parents=True, exist_ok=True)
    img = np.asarray(image, dtype=np.float32).copy()
    if mask is not None:
        img[~mask] = np.nan
    fig, ax = plt.subplots(figsize=(6.2, 5.4), constrained_layout=True)
    im = ax.imshow(img, origin="upper", cmap=cmap)
    ax.set_title(name.replace("_", " "))
    ax.set_xticks([])
    ax.set_yticks([])
    fig.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    fig.savefig(output_dir / f"{name}.png", dpi=180)
    plt.close(fig)


def matlab_attr(struct_value, name, default=None):
    return getattr(struct_value, name, default)


def infer_patch_and_feature_dims(input_dim):
    for feature_dim in (16, 10):
        patch_area = input_dim - feature_dim
        patch_size = int(round(np.sqrt(patch_area)))
        if patch_size > 0 and patch_size * patch_size == patch_area:
            return patch_size, feature_dim
    raise ValueError(f"Cannot infer patch and feature dimensions from input_dim={input_dim}")


def local_circular_std(phase_patch):
    coherence = np.abs(np.mean(np.exp(1j * phase_patch)))
    return float(np.sqrt(max(0.0, -2.0 * np.log(max(coherence, np.finfo(np.float32).eps)))))


def build_field_features(data, checkpoint, max_samples):
    valid_mask = np.asarray(data["valid_mask"]).astype(bool)
    rows, cols = np.where(valid_mask)
    if max_samples and rows.size > max_samples:
        pick = np.round(np.linspace(0, rows.size - 1, int(max_samples))).astype(np.int64)
        rows = rows[pick]
        cols = cols[pick]

    input_dim = int(checkpoint["input_dim"])
    patch_size, feature_dim = infer_patch_and_feature_dims(input_dim)
    patch_radius = patch_size // 2

    thickness_map = np.asarray(data["thickness_map"], dtype=np.float32)
    grad_map = np.asarray(data["thickness_grad_norm"], dtype=np.float32)
    local_mean = np.asarray(data["local_thickness_mean"], dtype=np.float32)
    local_std = np.asarray(data["local_thickness_std"], dtype=np.float32)
    edge_mm = np.asarray(data["aperture_edge_distance_mm"], dtype=np.float32)
    layers = np.asarray(data["net_num_board"], dtype=np.float32)
    board_phase = np.asarray(data.get("board_phase", np.zeros_like(thickness_map)), dtype=np.float32)
    x_mm = np.asarray(data["x_mm"], dtype=np.float32).reshape(-1)
    y_mm = np.asarray(data["y_mm"], dtype=np.float32).reshape(-1)
    X_mm, Y_mm = np.meshgrid(x_mm, y_mm)
    radius_mm = np.hypot(X_mm, Y_mm).astype(np.float32)
    phase_complex = np.exp(1j * board_phase)
    phase_gy, phase_gx = np.gradient(phase_complex)
    phase_grad_norm = np.sqrt(np.abs(phase_gx) ** 2 + np.abs(phase_gy) ** 2).astype(np.float32)

    thickness_pad = np.pad(thickness_map, patch_radius, mode="edge")
    grad_pad = np.pad(grad_map, patch_radius, mode="edge")
    phase_pad = np.pad(board_phase, patch_radius, mode="edge")
    phase_grad_pad = np.pad(phase_grad_norm, patch_radius, mode="edge")
    num_pixels = rows.size
    patch_features = np.empty((num_pixels, patch_size * patch_size), dtype=np.float32)
    feature_vector = np.empty((num_pixels, feature_dim), dtype=np.float32)
    for idx, (r, c) in enumerate(zip(rows, cols)):
        rp = r + patch_radius
        cp = c + patch_radius
        patch_thickness = thickness_pad[rp - patch_radius : rp + patch_radius + 1, cp - patch_radius : cp + patch_radius + 1]
        patch_grad = grad_pad[rp - patch_radius : rp + patch_radius + 1, cp - patch_radius : cp + patch_radius + 1]
        patch_phase = phase_pad[rp - patch_radius : rp + patch_radius + 1, cp - patch_radius : cp + patch_radius + 1]
        patch_phase_grad = phase_grad_pad[rp - patch_radius : rp + patch_radius + 1, cp - patch_radius : cp + patch_radius + 1]
        patch_features[idx] = patch_thickness.reshape(-1)
        features = [
            thickness_map[r, c] * 1e3,
            grad_map[r, c],
            local_mean[r, c] * 1e3,
            local_std[r, c],
            radius_mm[r, c],
            edge_mm[r, c],
            layers[r, c],
            np.mean(patch_thickness) * 1e3,
            np.std(patch_thickness) * 1e3,
            np.mean(patch_grad),
        ]
        if feature_dim == 16:
            features.extend(
                [
                    X_mm[r, c],
                    Y_mm[r, c],
                    np.sin(board_phase[r, c]),
                    np.cos(board_phase[r, c]),
                    np.mean(patch_phase_grad),
                    local_circular_std(patch_phase),
                ]
            )
        feature_vector[idx] = np.array(
            features,
            dtype=np.float32,
        )
    X = np.concatenate([patch_features, feature_vector], axis=1)
    return X, rows, cols, valid_mask


def field_target_arrays(data, target, rows, cols):
    if target == "complex_ratio_same":
        real = np.asarray(data["ratio_same_real"], dtype=np.float32)
        imag = np.asarray(data["ratio_same_imag"], dtype=np.float32)
        return np.stack([real[rows, cols], imag[rows, cols]], axis=1), ["real", "imag"]
    if target == "complex_ratio_opposite":
        real = np.asarray(data["ratio_opposite_real"], dtype=np.float32)
        imag = np.asarray(data["ratio_opposite_imag"], dtype=np.float32)
        return np.stack([real[rows, cols], imag[rows, cols]], axis=1), ["real", "imag"]
    amp = np.asarray(data["exit_amp_norm"], dtype=np.float32)
    return amp[rows, cols].reshape(-1, 1), ["amp"]


def reconstruct_exit_complex(data, ratio_values, target, rows, cols):
    ideal = np.asarray(data["ideal_complex_real"], dtype=np.float32) + 1j * np.asarray(data["ideal_complex_imag"], dtype=np.float32)
    ideal_vals = ideal[rows, cols]
    ratio = ratio_values[:, 0] + 1j * ratio_values[:, 1]
    if target == "complex_ratio_opposite":
        return np.conj(ratio * ideal_vals)
    return ratio * ideal_vals


def run_sample_validation(args, data_dir, model_path, output_dir, device):
    sample_path = find_case_file(data_dir, args.case, "_samples.mat")
    if sample_path is None:
        raise FileNotFoundError(f"No *_samples.mat file matching '{args.case}' below {data_dir}")
    run = load_sample_file(sample_path, args.target, args.max_samples)
    model, checkpoint = load_model(model_path, device)
    pred = predict(model, checkpoint, run["X"], device, args.batch_size)
    report = metrics_for(run["y"], pred, run["target_names"])
    report.update(
        {
            "mode": "sample",
            "case": args.case,
            "sample_path": str(sample_path),
            "model_path": str(model_path),
            "target": args.target,
            "num_samples": int(run["y"].shape[0]),
            "device": str(device),
        }
    )
    plot_scatter(output_dir, run["y"], pred, run["target_names"])
    return report


def run_field_validation(args, data_dir, model_path, output_dir, device):
    field_path = find_case_file(data_dir, args.case, "_field_validation.mat")
    if field_path is None:
        raise FileNotFoundError(f"No *_field_validation.mat file matching '{args.case}' below {data_dir}")
    data = sio.loadmat(field_path, squeeze_me=True, struct_as_record=False)
    model, checkpoint = load_model(model_path, device)
    X, rows, cols, valid_mask = build_field_features(data, checkpoint, args.max_samples)
    y_true, target_names = field_target_arrays(data, args.target, rows, cols)
    y_pred = predict(model, checkpoint, X, device, args.batch_size)
    report = metrics_for(y_true, y_pred, target_names)
    report.update(
        {
            "mode": "field",
            "case": args.case,
            "field_path": str(field_path),
            "model_path": str(model_path),
            "target": args.target,
            "num_pixels": int(y_true.shape[0]),
            "device": str(device),
            "run_label": str(matlab_attr(data.get("run_meta"), "run_label", args.case)),
        }
    )
    plot_scatter(output_dir, y_true, y_pred, target_names, prefix="field")

    if y_true.shape[1] == 2:
        actual_exit = np.asarray(data["exit_complex_real"], dtype=np.float32) + 1j * np.asarray(data["exit_complex_imag"], dtype=np.float32)
        actual_vals = actual_exit[rows, cols]
        pred_exit_vals = reconstruct_exit_complex(data, y_pred, args.target, rows, cols)
        report["exit_complex_reconstruction"] = complex_metrics(actual_vals, pred_exit_vals)

        shape = valid_mask.shape
        pred_ratio_map = np.full(shape, np.nan + 1j * np.nan, dtype=np.complex64)
        pred_exit_map = np.full(shape, np.nan + 1j * np.nan, dtype=np.complex64)
        pred_ratio_map[rows, cols] = y_pred[:, 0] + 1j * y_pred[:, 1]
        pred_exit_map[rows, cols] = pred_exit_vals
        actual_ratio = y_true[:, 0] + 1j * y_true[:, 1]
        actual_ratio_map = np.full(shape, np.nan + 1j * np.nan, dtype=np.complex64)
        actual_ratio_map[rows, cols] = actual_ratio

        plot_map(output_dir, "field_pred_ratio_amp", np.abs(pred_ratio_map), valid_mask)
        plot_map(output_dir, "field_actual_ratio_amp", np.abs(actual_ratio_map), valid_mask)
        plot_map(
            output_dir,
            "field_ratio_amp_abs_error",
            np.abs(np.abs(pred_ratio_map) - np.abs(actual_ratio_map)),
            valid_mask,
            cmap="magma",
        )
        plot_map(output_dir, "field_pred_exit_amp", np.abs(pred_exit_map), valid_mask)
        plot_map(output_dir, "field_actual_exit_amp", np.abs(actual_exit), valid_mask)
        phase_err_map = np.full(shape, np.nan, dtype=np.float32)
        phase_err_map[rows, cols] = np.angle(pred_exit_vals * np.conj(actual_vals))
        plot_map(output_dir, "field_exit_phase_error_rad", phase_err_map, valid_mask, cmap="twilight")
    return report


def main():
    args = parse_args()
    data_dir = Path(args.data_dir) if args.data_dir else default_data_dir()
    model_path = Path(args.model_path) if args.model_path else data_dir / "gpu_model_outputs" / "exit_complex_mlp.pt"
    base_output = Path(args.output_dir) if args.output_dir else data_dir / "gpu_model_outputs" / f"validate_{args.case}"
    requested_device = args.device
    if requested_device.startswith("cuda") and not torch.cuda.is_available():
        requested_device = "cpu"
    device = torch.device(requested_device)

    mode = args.mode
    if mode == "auto":
        mode = "field" if find_case_file(data_dir, args.case, "_field_validation.mat") is not None else "sample"
    output_dir = base_output / mode if args.mode == "auto" else base_output
    if mode == "field":
        report = run_field_validation(args, data_dir, model_path, output_dir, device)
    else:
        report = run_sample_validation(args, data_dir, model_path, output_dir, device)

    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "validation_report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(
        f"[OK] {mode} validation complete | R2={report['r2']:.4f} MAE={report['mae']:.4f} RMSE={report['rmse']:.4f}",
        flush=True,
    )
    if "complex" in report:
        c = report["complex"]
        print(
            f"[OK] ratio amp_R2={c['amp_r2']:.4f} phase_MAE={c['phase_mae_rad']:.4f} rad "
            f"coherence={c['coherence']:.4f}",
            flush=True,
        )
    if "exit_complex_reconstruction" in report:
        c = report["exit_complex_reconstruction"]
        print(
            f"[OK] exit-field amp_R2={c['amp_r2']:.4f} phase_MAE={c['phase_mae_rad']:.4f} rad "
            f"coherence={c['coherence']:.4f}",
            flush=True,
        )
    print(f"Outputs written to: {output_dir}", flush=True)


if __name__ == "__main__":
    main()
