import argparse
import json
import math
from pathlib import Path

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt
import numpy as np
import scipy.io as sio
from sklearn.decomposition import PCA
from sklearn.ensemble import RandomForestRegressor
from sklearn.metrics import mean_absolute_error, mean_squared_error, r2_score
from sklearn.pipeline import Pipeline
from sklearn.preprocessing import StandardScaler


def parse_args():
    parser = argparse.ArgumentParser(description="Train RF exit-amplitude surrogate from exported MATLAB runs.")
    parser.add_argument(
        "--data-dir",
        default=r"C:\Users\Zh89\Desktop\transport\exit_amp_surrogate",
        help="Directory containing *_samples.mat and *_summary.mat files.",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Output directory for reports and figures. Defaults to <data-dir>/model_outputs.",
    )
    parser.add_argument(
        "--num-holdout-runs",
        type=int,
        default=1,
        help="Number of runs to randomly hold out for evaluation. Use 1 or 2 for faster iteration.",
    )
    parser.add_argument(
        "--random-seed",
        type=int,
        default=42,
        help="Random seed for selecting holdout runs.",
    )
    return parser.parse_args()


def sanitize_run_name(run_name: str) -> str:
    return run_name.replace("\\", "_").replace("/", "_").replace(" ", "_")


def evaluate_predictions(y_true, y_pred):
    return {
        "r2": float(r2_score(y_true, y_pred)),
        "mae": float(mean_absolute_error(y_true, y_pred)),
        "rmse": float(math.sqrt(mean_squared_error(y_true, y_pred))),
    }


def load_sample_file(sample_path: Path):
    data = sio.loadmat(sample_path, squeeze_me=True, struct_as_record=False)
    run_meta = data["run_meta"]
    run_name = str(getattr(run_meta, "run_label", sample_path.stem))

    feature_vector = np.asarray(data["feature_vector"], dtype=np.float32)
    target_exit_amp = np.asarray(data["target_exit_amp"], dtype=np.float32).reshape(-1)
    thickness_patches = np.asarray(data["thickness_patches"], dtype=np.float32)
    x_mm = np.asarray(data["x_mm"], dtype=np.float32).reshape(-1)
    y_mm = np.asarray(data["y_mm"], dtype=np.float32).reshape(-1)
    radius_mm = np.asarray(data["radius_mm"], dtype=np.float32).reshape(-1)
    edge_distance_mm = np.asarray(data["edge_distance_mm"], dtype=np.float32).reshape(-1)

    if thickness_patches.ndim != 3:
        raise ValueError(f"{sample_path} thickness_patches must be 3D, got shape {thickness_patches.shape}")

    num_samples = target_exit_amp.shape[0]
    if thickness_patches.shape[2] != num_samples:
        raise ValueError(
            f"{sample_path} thickness_patches sample count mismatch: {thickness_patches.shape[2]} vs {num_samples}"
        )

    for name, value in {
        "feature_vector": feature_vector,
        "x_mm": x_mm,
        "y_mm": y_mm,
        "radius_mm": radius_mm,
        "edge_distance_mm": edge_distance_mm,
    }.items():
        if value.shape[0] != num_samples:
            raise ValueError(f"{sample_path} {name} length mismatch: {value.shape[0]} vs {num_samples}")

    patch_features = np.transpose(thickness_patches, (2, 0, 1)).reshape(num_samples, -1)
    feature_names = [
        "thickness_center_mm",
        "thickness_grad_center",
        "local_mean_mm",
        "local_std_mm",
        "radius_mm",
        "edge_distance_mm",
        "layer_index",
        "patch_mean_mm",
        "patch_std_mm",
        "patch_grad_mean",
    ]

    return {
        "run_name": run_name,
        "sample_path": str(sample_path),
        "num_samples": int(num_samples),
        "X_linear": feature_vector,
        "X_patch": np.concatenate([patch_features, feature_vector], axis=1),
        "y": target_exit_amp,
        "x_mm": x_mm,
        "y_mm": y_mm,
        "radius_mm": radius_mm,
        "edge_distance_mm": edge_distance_mm,
        "feature_names": feature_names,
    }


def build_dataset(data_dir: Path):
    sample_files = sorted(data_dir.glob("*_samples.mat"))
    if not sample_files:
        raise FileNotFoundError(f"No *_samples.mat files found in {data_dir}")

    runs = [load_sample_file(path) for path in sample_files]
    X_patch = np.concatenate([run["X_patch"] for run in runs], axis=0)
    y = np.concatenate([run["y"] for run in runs], axis=0)
    groups = np.concatenate([[idx] * run["y"].shape[0] for idx, run in enumerate(runs)]).astype(np.int32)
    run_names = [run["run_name"] for run in runs]
    return runs, X_patch, y, groups, run_names


def select_holdout_run_ids(groups, num_holdout_runs: int, random_seed: int):
    unique_runs = np.unique(groups).astype(np.int32)
    if unique_runs.size == 0:
        raise ValueError("No runs available for evaluation.")
    if unique_runs.size == 1:
        return unique_runs

    num_holdout = max(1, min(int(num_holdout_runs), unique_runs.size))
    rng = np.random.default_rng(random_seed)
    selected = np.sort(rng.choice(unique_runs, size=num_holdout, replace=False))
    return selected


def fit_rf_model(X_train, X_test, y_train, y_test):
    pca_components = min(32, X_train.shape[1], X_train.shape[0])
    model = Pipeline(
        [
            ("scaler", StandardScaler()),
            ("pca", PCA(n_components=max(4, pca_components))),
            (
                "regressor",
                RandomForestRegressor(
                    n_estimators=160,
                    max_depth=18,
                    min_samples_leaf=4,
                    random_state=42,
                    n_jobs=1,
                ),
            ),
        ]
    )
    model.fit(X_train, y_train)
    pred = np.clip(model.predict(X_test), 0.0, 1.0)
    return {
        "model": model,
        "metrics": evaluate_predictions(y_test, pred),
        "pred": pred,
    }


def plot_prediction_maps(output_dir: Path, run, y_true, y_pred, title_prefix):
    unique_x = np.unique(run["x_mm"])
    unique_y = np.unique(run["y_mm"])
    x_to_col = {val: idx for idx, val in enumerate(unique_x)}
    y_to_row = {val: idx for idx, val in enumerate(unique_y)}
    true_map = np.full((unique_y.size, unique_x.size), np.nan, dtype=np.float32)
    pred_map = np.full_like(true_map, np.nan)

    for xv, yv, tv, pv in zip(run["x_mm"], run["y_mm"], y_true, y_pred):
        true_map[y_to_row[yv], x_to_col[xv]] = tv
        pred_map[y_to_row[yv], x_to_col[xv]] = pv

    err_map = pred_map - true_map
    extent = [unique_x.min(), unique_x.max(), unique_y.max(), unique_y.min()]

    fig, axes = plt.subplots(1, 3, figsize=(15, 4.5), constrained_layout=True)
    for ax, data, title in [
        (axes[0], true_map, "Measured Exit Amplitude"),
        (axes[1], pred_map, "Predicted Exit Amplitude"),
        (axes[2], err_map, "Prediction Error"),
    ]:
        im = ax.imshow(data, extent=extent, cmap="turbo")
        ax.set_title(title)
        ax.set_xlabel("mm")
        ax.set_ylabel("mm")
        plt.colorbar(im, ax=ax, shrink=0.85)
    fig.suptitle(title_prefix)
    fig.savefig(output_dir / "prediction_maps.png", dpi=180)
    plt.close(fig)


def plot_grouped_errors(output_dir: Path, run, y_true, y_pred, title_prefix):
    abs_err = np.abs(y_pred - y_true)
    fig, axes = plt.subplots(1, 3, figsize=(15, 4.5), constrained_layout=True)
    groups = [
        (run["X_linear"][:, 0], "Thickness (mm)"),
        (run["radius_mm"], "Radius (mm)"),
        (run["edge_distance_mm"], "Edge distance (mm)"),
    ]
    for ax, (values, xlabel) in zip(axes, groups):
        bins = np.linspace(values.min(), values.max(), 9)
        centers = 0.5 * (bins[:-1] + bins[1:])
        means = np.full(centers.shape, np.nan)
        for idx in range(centers.size):
            right_closed = idx == centers.size - 1
            mask = (values >= bins[idx]) & (values <= bins[idx + 1] if right_closed else values < bins[idx + 1])
            if np.any(mask):
                means[idx] = abs_err[mask].mean()
        ax.plot(centers, means, "o-", linewidth=1.5)
        ax.grid(True, alpha=0.3)
        ax.set_xlabel(xlabel)
        ax.set_ylabel("Mean absolute error")
    fig.suptitle(title_prefix)
    fig.savefig(output_dir / "grouped_error_curves.png", dpi=180)
    plt.close(fig)


def plot_true_vs_pred(output_dir: Path, y_true, y_pred, title_prefix):
    fig, ax = plt.subplots(figsize=(5.2, 5.2), constrained_layout=True)
    ax.scatter(y_true, y_pred, s=8, alpha=0.4)
    ax.plot([0, 1], [0, 1], "k--", linewidth=1.0)
    ax.set_xlabel("Measured exit amplitude")
    ax.set_ylabel("Predicted exit amplitude")
    ax.set_title(title_prefix)
    ax.grid(True, alpha=0.25)
    fig.savefig(output_dir / "true_vs_pred.png", dpi=180)
    plt.close(fig)


def weighted_average(metrics_list, key, weights):
    values = np.asarray([metrics[key] for metrics in metrics_list], dtype=np.float64)
    weights = np.asarray(weights, dtype=np.float64)
    return float(np.sum(values * weights) / np.sum(weights))


def evaluate_holdout_runs(output_dir: Path, runs, X_patch, y, groups, run_names, holdout_run_ids):
    aggregate_true = []
    aggregate_pred = []
    per_run_report = {}
    per_run_metrics = []
    per_run_weights = []

    print(f"[INFO] Evaluating {len(holdout_run_ids)} holdout run(s): " + ", ".join(run_names[int(idx)] for idx in holdout_run_ids), flush=True)

    for eval_idx, holdout_id in enumerate(holdout_run_ids, start=1):
        holdout_id = int(holdout_id)
        train_idx = np.where(groups != holdout_id)[0]
        test_idx = np.where(groups == holdout_id)[0]
        run_name = run_names[holdout_id]
        run = runs[holdout_id]

        run_output_dir = output_dir / f"holdout_{sanitize_run_name(run_name)}"
        run_output_dir.mkdir(parents=True, exist_ok=True)
        print(
            f"[{eval_idx}/{len(holdout_run_ids)}] Holdout run '{run_name}': "
            f"train_samples={train_idx.size}, test_samples={test_idx.size}",
            flush=True,
        )

        if train_idx.size == 0:
            print(f"[{eval_idx}/{len(holdout_run_ids)}] Self-eval mode: training and testing on '{run_name}'", flush=True)
            result = fit_rf_model(X_patch[test_idx], X_patch[test_idx], y[test_idx], y[test_idx])
            title_prefix = f"rf_patch_pca on self-eval run: {run_name}"
            split_mode = "self_eval"
        else:
            print(f"[{eval_idx}/{len(holdout_run_ids)}] Training RF+PCA for holdout '{run_name}'...", flush=True)
            result = fit_rf_model(X_patch[train_idx], X_patch[test_idx], y[train_idx], y[test_idx])
            title_prefix = f"rf_patch_pca on holdout run: {run_name}"
            split_mode = "random_holdout_run"

        y_true = y[test_idx]
        y_pred = result["pred"]
        print(
            f"[{eval_idx}/{len(holdout_run_ids)}] Metrics for '{run_name}': "
            f"R2={result['metrics']['r2']:.4f}, MAE={result['metrics']['mae']:.4f}, RMSE={result['metrics']['rmse']:.4f}",
            flush=True,
        )
        print(f"[{eval_idx}/{len(holdout_run_ids)}] Writing figures for '{run_name}'...", flush=True)
        plot_true_vs_pred(run_output_dir, y_true, y_pred, title_prefix)
        plot_prediction_maps(run_output_dir, run, y_true, y_pred, title_prefix)
        plot_grouped_errors(run_output_dir, run, y_true, y_pred, title_prefix)

        metrics = result["metrics"]
        per_run_report[run_name] = {
            "metrics": metrics,
            "num_samples": int(y_true.shape[0]),
            "split_mode": split_mode,
            "train_runs": [run_names[int(idx)] for idx in np.unique(groups[train_idx])] if train_idx.size else [run_name],
            "test_run": run_name,
            "output_dir": str(run_output_dir),
        }
        per_run_metrics.append(metrics)
        per_run_weights.append(y_true.shape[0])
        aggregate_true.append(y_true)
        aggregate_pred.append(y_pred)

    aggregate_true = np.concatenate(aggregate_true, axis=0)
    aggregate_pred = np.concatenate(aggregate_pred, axis=0)
    print("[INFO] Writing aggregate held-out scatter plot...", flush=True)
    plot_true_vs_pred(output_dir, aggregate_true, aggregate_pred, "rf_patch_pca across held-out runs")

    aggregate_metrics = {
        "r2_global": float(r2_score(aggregate_true, aggregate_pred)),
        "mae_weighted": weighted_average(per_run_metrics, "mae", per_run_weights),
        "rmse_weighted": weighted_average(per_run_metrics, "rmse", per_run_weights),
        "r2_mean": float(np.mean([m["r2"] for m in per_run_metrics])),
        "r2_min": float(np.min([m["r2"] for m in per_run_metrics])),
    }
    return per_run_report, aggregate_metrics


def write_report(output_dir: Path, report):
    report_path = output_dir / "surrogate_report.json"
    report_path.write_text(json.dumps(report, indent=2, ensure_ascii=False), encoding="utf-8")

    text_lines = [
        "HDSP Exit Amplitude Surrogate Report",
        f"evaluation_mode: {report['evaluation_mode']}",
        f"num_runs: {report['num_runs']}",
        f"num_samples_total: {report['num_samples_total']}",
        "",
        "aggregate_metrics:",
        f"  r2_global: {report['aggregate_metrics']['r2_global']:.4f}",
        f"  r2_mean: {report['aggregate_metrics']['r2_mean']:.4f}",
        f"  r2_min: {report['aggregate_metrics']['r2_min']:.4f}",
        f"  mae_weighted: {report['aggregate_metrics']['mae_weighted']:.4f}",
        f"  rmse_weighted: {report['aggregate_metrics']['rmse_weighted']:.4f}",
        "",
        "per_run_metrics:",
    ]
    for run_name, payload in report["per_run_metrics"].items():
        metrics = payload["metrics"]
        text_lines.extend(
            [
                f"  {run_name}:",
                f"    r2: {metrics['r2']:.4f}",
                f"    mae: {metrics['mae']:.4f}",
                f"    rmse: {metrics['rmse']:.4f}",
                f"    num_samples: {payload['num_samples']}",
                f"    split_mode: {payload['split_mode']}",
                f"    train_runs: {', '.join(payload['train_runs'])}",
                f"    output_dir: {payload['output_dir']}",
            ]
        )
    text_lines.append("")
    text_lines.append(f"best_model: {report['best_model']}")
    text_lines.append(f"stage1_gate_pass: {report['stage1_gate_pass']}")
    (output_dir / "surrogate_report.txt").write_text("\n".join(text_lines), encoding="utf-8")


def main():
    args = parse_args()
    data_dir = Path(args.data_dir)
    output_dir = Path(args.output_dir) if args.output_dir else data_dir / "model_outputs"
    output_dir.mkdir(parents=True, exist_ok=True)

    print(f"[INFO] Loading runs from: {data_dir}", flush=True)
    runs, X_patch, y, groups, run_names = build_dataset(data_dir)
    print(
        f"[INFO] Loaded {len(runs)} run(s), total samples={y.shape[0]}: " + ", ".join(run_names),
        flush=True,
    )
    holdout_run_ids = select_holdout_run_ids(groups, args.num_holdout_runs, args.random_seed)
    print(
        f"[INFO] Randomly selected holdout run(s): " + ", ".join(run_names[int(idx)] for idx in holdout_run_ids),
        flush=True,
    )
    per_run_report, aggregate_metrics = evaluate_holdout_runs(
        output_dir, runs, X_patch, y, groups, run_names, holdout_run_ids
    )

    report = {
        "data_dir": str(data_dir),
        "num_runs": len(runs),
        "num_samples_total": int(y.shape[0]),
        "evaluation_mode": "random_holdout_runs" if len(runs) > 1 else "self_eval_single_run",
        "selected_holdout_runs": [run_names[int(idx)] for idx in holdout_run_ids],
        "num_holdout_runs": int(len(holdout_run_ids)),
        "random_seed": int(args.random_seed),
        "best_model": "rf_patch_pca",
        "aggregate_metrics": aggregate_metrics,
        "per_run_metrics": per_run_report,
        "stage1_gate_pass": bool(aggregate_metrics["r2_mean"] >= 0.30),
    }
    print("[INFO] Writing report...", flush=True)
    write_report(output_dir, report)

    print("[OK] Exit-amplitude surrogate training complete")
    print(
        "rf_patch_pca: "
        f"R2_global={aggregate_metrics['r2_global']:.4f} | "
        f"R2_mean={aggregate_metrics['r2_mean']:.4f} | "
        f"R2_min={aggregate_metrics['r2_min']:.4f} | "
        f"MAE={aggregate_metrics['mae_weighted']:.4f} | "
        f"RMSE={aggregate_metrics['rmse_weighted']:.4f}"
    )
    print("Best model: rf_patch_pca")
    print(f"Stage-1 gate (mean R2 >= 0.30): {report['stage1_gate_pass']}")
    print(f"Outputs written to: {output_dir}")


if __name__ == "__main__":
    main()
