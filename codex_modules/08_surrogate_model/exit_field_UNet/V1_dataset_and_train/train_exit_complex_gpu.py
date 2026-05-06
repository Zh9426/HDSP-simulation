import argparse
import json
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import scipy.io as sio
import torch
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score


def parse_args():
    parser = argparse.ArgumentParser(description="Train a GPU MLP surrogate for HDSP exit complex modulation ratio.")
    parser.add_argument("--data-dir", default=None, help="Defaults to <script_dir>/modulation_law_dataset.")
    parser.add_argument("--output-dir", default=None, help="Defaults to <data-dir>/gpu_model_outputs.")
    parser.add_argument(
        "--target",
        choices=["complex_ratio_opposite", "complex_ratio_same", "amp"],
        default="complex_ratio_opposite",
    )
    parser.add_argument("--num-holdout-runs", type=int, default=1)
    parser.add_argument("--random-seed", type=int, default=42)
    parser.add_argument("--max-runs", type=int, default=0, help="0 means all runs.")
    parser.add_argument("--max-samples-per-run", type=int, default=0, help="0 means all samples.")
    parser.add_argument("--sample-selection", choices=["latest_per_case", "all"], default="latest_per_case")
    parser.add_argument("--epochs", type=int, default=300)
    parser.add_argument("--batch-size", type=int, default=16384)
    parser.add_argument("--lr", type=float, default=8e-4)
    parser.add_argument("--weight-decay", type=float, default=1e-4)
    parser.add_argument("--hidden", type=int, nargs="+", default=[768, 512, 256, 128])
    parser.add_argument("--dropout", type=float, default=0.03)
    parser.add_argument("--device", default="cuda", help="cuda, cpu, or cuda:0.")
    return parser.parse_args()


def default_data_dir() -> Path:
    return Path(__file__).resolve().parent / "modulation_law_dataset"


def sanitize_run_name(run_name: str) -> str:
    return run_name.replace("\\", "_").replace("/", "_").replace(" ", "_")


def pick_target(data, target: str):
    if target == "amp":
        return np.asarray(data["target_exit_amp"], dtype=np.float32).reshape(-1, 1), ["amp"]
    prefix = "target_ratio_same" if target == "complex_ratio_same" else "target_ratio_opposite"
    real_name = f"{prefix}_real"
    imag_name = f"{prefix}_imag"
    if real_name not in data or imag_name not in data:
        raise KeyError(
            f"Missing {real_name}/{imag_name}. Regenerate sweep data with complex-field export or use --target amp."
        )
    y_real = np.asarray(data[real_name], dtype=np.float32).reshape(-1)
    y_imag = np.asarray(data[imag_name], dtype=np.float32).reshape(-1)
    return np.stack([y_real, y_imag], axis=1), ["real", "imag"]


def load_sample_file(sample_path: Path, target: str, max_samples_per_run: int):
    data = sio.loadmat(sample_path, squeeze_me=True, struct_as_record=False)
    run_meta = data["run_meta"]
    run_name = str(getattr(run_meta, "run_label", sample_path.stem))
    thickness_patches = np.asarray(data["thickness_patches"], dtype=np.float32)
    feature_vector = np.asarray(data["feature_vector"], dtype=np.float32)
    y, target_names = pick_target(data, target)

    if thickness_patches.ndim != 3:
        raise ValueError(f"{sample_path} thickness_patches must be 3D, got {thickness_patches.shape}")
    num_samples = y.shape[0]
    if thickness_patches.shape[2] != num_samples or feature_vector.shape[0] != num_samples:
        raise ValueError(f"{sample_path} sample count mismatch.")

    if max_samples_per_run and num_samples > max_samples_per_run:
        sample_idx = np.round(np.linspace(0, num_samples - 1, int(max_samples_per_run))).astype(np.int64)
        thickness_patches = thickness_patches[:, :, sample_idx]
        feature_vector = feature_vector[sample_idx]
        y = y[sample_idx]
        num_samples = y.shape[0]

    patch_features = np.transpose(thickness_patches, (2, 0, 1)).reshape(num_samples, -1)
    x = np.concatenate([patch_features, feature_vector], axis=1).astype(np.float32)
    return {
        "run_name": run_name,
        "sample_path": str(sample_path),
        "X": x,
        "y": y.astype(np.float32),
        "target_names": target_names,
        "num_samples": int(num_samples),
    }


def select_sample_files(data_dir: Path, sample_selection: str):
    sample_files = sorted(data_dir.rglob("*_samples.mat"))
    if not sample_files:
        raise FileNotFoundError(f"No *_samples.mat files found recursively in {data_dir}")
    if sample_selection == "latest_per_case":
        latest_by_dir = {}
        for path in sample_files:
            current = latest_by_dir.get(path.parent)
            if current is None or path.stat().st_mtime > current.stat().st_mtime:
                latest_by_dir[path.parent] = path
        sample_files = sorted(latest_by_dir.values())
    return sample_files


def build_dataset(data_dir: Path, target: str, max_runs: int, max_samples_per_run: int, sample_selection: str):
    sample_files = select_sample_files(data_dir, sample_selection)
    if max_runs:
        sample_files = sample_files[: max(1, int(max_runs))]
    runs = [load_sample_file(path, target, max_samples_per_run) for path in sample_files]
    X = np.concatenate([run["X"] for run in runs], axis=0)
    y = np.concatenate([run["y"] for run in runs], axis=0)
    groups = np.concatenate([[idx] * run["num_samples"] for idx, run in enumerate(runs)]).astype(np.int32)
    run_names = [run["run_name"] for run in runs]
    target_names = runs[0]["target_names"]
    sample_paths = [run["sample_path"] for run in runs]
    return runs, X, y, groups, run_names, target_names, sample_paths


def select_holdout_run_ids(groups, num_holdout_runs: int, random_seed: int):
    unique_runs = np.unique(groups).astype(np.int32)
    if unique_runs.size <= 1:
        return unique_runs
    rng = np.random.default_rng(random_seed)
    num_holdout = max(1, min(int(num_holdout_runs), unique_runs.size))
    return np.sort(rng.choice(unique_runs, size=num_holdout, replace=False))


class ExitMLP(torch.nn.Module):
    def __init__(self, input_dim: int, output_dim: int, hidden, dropout: float):
        super().__init__()
        layers = []
        prev = input_dim
        for width in hidden:
            layers.append(torch.nn.Linear(prev, int(width)))
            layers.append(torch.nn.SiLU())
            layers.append(torch.nn.LayerNorm(int(width)))
            if dropout > 0:
                layers.append(torch.nn.Dropout(dropout))
            prev = int(width)
        layers.append(torch.nn.Linear(prev, output_dim))
        self.net = torch.nn.Sequential(*layers)

    def forward(self, x):
        return self.net(x)


def evaluate_predictions(y_true, y_pred, target_names):
    metrics = {
        "r2": float(r2_score(y_true, y_pred, multioutput="uniform_average")),
        "mae": float(mean_absolute_error(y_true, y_pred)),
        "rmse": float(math.sqrt(mean_squared_error(y_true, y_pred))),
        "per_dim": {},
    }
    for dim, name in enumerate(target_names):
        metrics["per_dim"][name] = {
            "r2": float(r2_score(y_true[:, dim], y_pred[:, dim])),
            "mae": float(mean_absolute_error(y_true[:, dim], y_pred[:, dim])),
            "rmse": float(math.sqrt(mean_squared_error(y_true[:, dim], y_pred[:, dim]))),
        }
    return metrics


def plot_true_vs_pred(output_dir: Path, y_true, y_pred, name: str, title: str):
    output_dir.mkdir(parents=True, exist_ok=True)
    fig, ax = plt.subplots(figsize=(5.4, 5.4), constrained_layout=True)
    ax.scatter(y_true, y_pred, s=8, alpha=0.35)
    lo = float(min(np.min(y_true), np.min(y_pred)))
    hi = float(max(np.max(y_true), np.max(y_pred)))
    pad = 0.05 * max(hi - lo, 1e-6)
    lo -= pad
    hi += pad
    ax.plot([lo, hi], [lo, hi], "k--", linewidth=1.0)
    ax.set_xlim(lo, hi)
    ax.set_ylim(lo, hi)
    ax.set_xlabel("Measured target")
    ax.set_ylabel("Predicted target")
    ax.set_title(title)
    ax.grid(True, alpha=0.25)
    fig.savefig(output_dir / f"true_vs_pred_{name}.png", dpi=180)
    plt.close(fig)


def train_one_split(args, X, y, groups, run_names, target_names, output_dir: Path):
    holdout_ids = select_holdout_run_ids(groups, args.num_holdout_runs, args.random_seed)
    test_mask = np.isin(groups, holdout_ids)
    train_mask = ~test_mask
    if not np.any(train_mask):
        train_mask = test_mask

    X_train = X[train_mask]
    y_train = y[train_mask]
    X_test = X[test_mask]
    y_test = y[test_mask]
    train_run_names = [run_names[int(idx)] for idx in np.unique(groups[train_mask])]
    holdout_run_names = [run_names[int(idx)] for idx in holdout_ids]

    x_mean = X_train.mean(axis=0, keepdims=True)
    x_std = X_train.std(axis=0, keepdims=True) + 1e-6
    y_mean = y_train.mean(axis=0, keepdims=True)
    y_std = y_train.std(axis=0, keepdims=True) + 1e-6
    X_train_n = (X_train - x_mean) / x_std
    X_test_n = (X_test - x_mean) / x_std
    y_train_n = (y_train - y_mean) / y_std

    requested_device = args.device
    if requested_device.startswith("cuda") and not torch.cuda.is_available():
        requested_device = "cpu"
    device = torch.device(requested_device)
    model = ExitMLP(X.shape[1], y.shape[1], args.hidden, args.dropout).to(device)
    optimizer = torch.optim.AdamW(model.parameters(), lr=args.lr, weight_decay=args.weight_decay)
    loss_fn = torch.nn.SmoothL1Loss(beta=0.5)

    X_train_t = torch.from_numpy(X_train_n.astype(np.float32))
    y_train_t = torch.from_numpy(y_train_n.astype(np.float32))
    X_test_t = torch.from_numpy(X_test_n.astype(np.float32))
    y_mean_t = torch.from_numpy(y_mean.astype(np.float32)).to(device)
    y_std_t = torch.from_numpy(y_std.astype(np.float32)).to(device)
    train_ds = torch.utils.data.TensorDataset(X_train_t, y_train_t)
    generator = torch.Generator()
    generator.manual_seed(args.random_seed)
    loader = torch.utils.data.DataLoader(
        train_ds,
        batch_size=args.batch_size,
        shuffle=True,
        num_workers=0,
        pin_memory=device.type == "cuda",
        generator=generator,
    )

    print(
        f"[INFO] Device={device} | train_samples={X_train.shape[0]} | test_samples={X_test.shape[0]} | "
        f"input_dim={X.shape[1]} | output_dim={y.shape[1]}",
        flush=True,
    )
    print(f"[INFO] Holdout run(s): {', '.join(holdout_run_names)}", flush=True)

    history = []
    best_metrics = None
    best_pred = None
    best_state_dict = None
    best_r2 = -np.inf
    for epoch in range(1, args.epochs + 1):
        model.train()
        total_loss = 0.0
        total_count = 0
        for xb, yb in loader:
            xb = xb.to(device, non_blocking=True)
            yb = yb.to(device, non_blocking=True)
            optimizer.zero_grad(set_to_none=True)
            pred = model(xb)
            loss = loss_fn(pred, yb)
            loss.backward()
            optimizer.step()
            total_loss += float(loss.item()) * xb.shape[0]
            total_count += xb.shape[0]

        if epoch == 1 or epoch % max(1, args.epochs // 10) == 0 or epoch == args.epochs:
            pred = predict_numpy(model, X_test_t, y_mean_t, y_std_t, device, args.batch_size)
            metrics = evaluate_predictions(y_test, pred, target_names)
            history.append({"epoch": epoch, "train_loss": total_loss / max(total_count, 1), "metrics": metrics})
            print(
                f"[{epoch:03d}/{args.epochs}] loss={history[-1]['train_loss']:.5f} "
                f"R2={metrics['r2']:.4f} MAE={metrics['mae']:.4f} RMSE={metrics['rmse']:.4f}",
                flush=True,
            )
            if metrics["r2"] > best_r2:
                best_r2 = metrics["r2"]
                best_metrics = metrics
                best_pred = pred
                best_state_dict = {key: value.detach().cpu().clone() for key, value in model.state_dict().items()}

    for dim, name in enumerate(target_names):
        plot_true_vs_pred(output_dir, y_test[:, dim], best_pred[:, dim], name, f"GPU MLP {name} holdout")

    torch.save(
        {
            "model_state_dict": best_state_dict if best_state_dict is not None else model.state_dict(),
            "input_dim": X.shape[1],
            "output_dim": y.shape[1],
            "hidden": args.hidden,
            "dropout": args.dropout,
            "x_mean": x_mean.astype(np.float32),
            "x_std": x_std.astype(np.float32),
            "y_mean": y_mean.astype(np.float32),
            "y_std": y_std.astype(np.float32),
            "target_names": target_names,
        },
        output_dir / "exit_complex_mlp.pt",
    )

    return {
        "target": args.target,
        "device": str(device),
        "epochs": args.epochs,
        "batch_size": args.batch_size,
        "lr": args.lr,
        "weight_decay": args.weight_decay,
        "hidden": args.hidden,
        "dropout": args.dropout,
        "train_runs": train_run_names,
        "holdout_runs": holdout_run_names,
        "num_train_samples": int(X_train.shape[0]),
        "num_test_samples": int(X_test.shape[0]),
        "best_metrics": best_metrics,
        "history": history,
    }


def predict_numpy(model, X_t, y_mean_t, y_std_t, device, batch_size: int):
    model.eval()
    preds = []
    with torch.no_grad():
        for start in range(0, X_t.shape[0], batch_size):
            xb = X_t[start : start + batch_size].to(device, non_blocking=True)
            pred_n = model(xb)
            pred = pred_n * y_std_t + y_mean_t
            preds.append(pred.cpu().numpy())
    return np.concatenate(preds, axis=0)


def main():
    args = parse_args()
    np.random.seed(args.random_seed)
    torch.manual_seed(args.random_seed)
    data_dir = Path(args.data_dir) if args.data_dir else default_data_dir()
    output_dir = Path(args.output_dir) if args.output_dir else data_dir / "gpu_model_outputs"
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"[INFO] Loading runs from: {data_dir}", flush=True)
    runs, X, y, groups, run_names, target_names, sample_paths = build_dataset(
        data_dir, args.target, args.max_runs, args.max_samples_per_run, args.sample_selection
    )
    print(
        f"[INFO] Loaded {len(runs)} run(s), samples={X.shape[0]}, target={args.target}, "
        f"target_dims={target_names}",
        flush=True,
    )
    report = train_one_split(args, X, y, groups, run_names, target_names, output_dir)
    report.update(
        {
            "data_dir": str(data_dir),
            "output_dir": str(output_dir),
            "num_runs": len(runs),
            "run_names": run_names,
            "sample_paths": sample_paths,
            "max_runs": args.max_runs,
            "max_samples_per_run": args.max_samples_per_run,
            "sample_selection": args.sample_selection,
        }
    )
    (output_dir / "gpu_surrogate_report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(
        "[OK] GPU MLP training complete | "
        f"R2={report['best_metrics']['r2']:.4f} MAE={report['best_metrics']['mae']:.4f} "
        f"RMSE={report['best_metrics']['rmse']:.4f}",
        flush=True,
    )
    print(f"Outputs written to: {output_dir}", flush=True)


if __name__ == "__main__":
    main()
