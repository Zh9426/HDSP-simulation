import argparse
import json
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import torch
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score

from train_exit_complex_gpu import ExitMLP, default_data_dir, load_sample_file


def parse_args():
    parser = argparse.ArgumentParser(description="Validate a trained exit-complex GPU surrogate on exported k-Wave samples.")
    parser.add_argument("--data-dir", default=None, help="Defaults to <script_dir>/modulation_law_dataset.")
    parser.add_argument("--model-path", default=None, help="Defaults to <data-dir>/gpu_model_outputs/exit_complex_mlp.pt.")
    parser.add_argument("--case", default="case_004_same_bias-0.79_layer+0_round", help="Case directory name or substring.")
    parser.add_argument("--target", choices=["complex_ratio_opposite", "complex_ratio_same", "amp"], default="complex_ratio_opposite")
    parser.add_argument("--max-samples", type=int, default=0, help="0 means all samples in the selected sample file.")
    parser.add_argument("--batch-size", type=int, default=32768)
    parser.add_argument("--device", default="cuda")
    parser.add_argument("--output-dir", default=None)
    return parser.parse_args()


def find_case_sample(data_dir: Path, case_query: str):
    sample_files = sorted(data_dir.rglob("*_samples.mat"))
    if not sample_files:
        raise FileNotFoundError(f"No *_samples.mat files found below {data_dir}")
    matches = [path for path in sample_files if case_query in str(path)]
    if not matches:
        raise FileNotFoundError(f"No sample file matching '{case_query}' below {data_dir}")
    if len(matches) > 1:
        matches = sorted(matches, key=lambda p: p.stat().st_mtime, reverse=True)
    return matches[0]


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
        true_complex = y_true[:, 0] + 1j * y_true[:, 1]
        pred_complex = y_pred[:, 0] + 1j * y_pred[:, 1]
        amp_true = np.abs(true_complex)
        amp_pred = np.abs(pred_complex)
        phase_err = np.angle(pred_complex * np.conj(true_complex))
        report["complex"] = {
            "amp_r2": float(r2_score(amp_true, amp_pred)),
            "amp_mae": float(mean_absolute_error(amp_true, amp_pred)),
            "phase_mae_rad": float(np.mean(np.abs(phase_err))),
            "phase_rmse_rad": float(np.sqrt(np.mean(phase_err**2))),
            "coherence": float(np.abs(np.mean(np.exp(1j * phase_err)))),
        }
    return report


def plot_scatter(output_dir: Path, y_true, y_pred, target_names):
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
        fig.savefig(output_dir / f"validate_true_vs_pred_{name}.png", dpi=180)
        plt.close(fig)


def main():
    args = parse_args()
    data_dir = Path(args.data_dir) if args.data_dir else default_data_dir()
    model_path = Path(args.model_path) if args.model_path else data_dir / "gpu_model_outputs" / "exit_complex_mlp.pt"
    output_dir = Path(args.output_dir) if args.output_dir else data_dir / "gpu_model_outputs" / f"validate_{args.case}"
    requested_device = args.device
    if requested_device.startswith("cuda") and not torch.cuda.is_available():
        requested_device = "cpu"
    device = torch.device(requested_device)

    sample_path = find_case_sample(data_dir, args.case)
    run = load_sample_file(sample_path, args.target, args.max_samples)
    model, checkpoint = load_model(model_path, device)
    pred = predict(model, checkpoint, run["X"], device, args.batch_size)
    report = metrics_for(run["y"], pred, run["target_names"])
    report.update(
        {
            "case": args.case,
            "sample_path": str(sample_path),
            "model_path": str(model_path),
            "target": args.target,
            "num_samples": int(run["y"].shape[0]),
            "device": str(device),
        }
    )
    plot_scatter(output_dir, run["y"], pred, run["target_names"])
    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "validation_report.json").write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")
    print(
        f"[OK] Validation complete | R2={report['r2']:.4f} MAE={report['mae']:.4f} RMSE={report['rmse']:.4f}",
        flush=True,
    )
    if "complex" in report:
        c = report["complex"]
        print(
            f"[OK] Complex amp_R2={c['amp_r2']:.4f} phase_MAE={c['phase_mae_rad']:.4f} rad "
            f"coherence={c['coherence']:.4f}",
            flush=True,
        )
    print(f"Outputs written to: {output_dir}", flush=True)


if __name__ == "__main__":
    main()
