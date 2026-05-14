import torch


def normalize_energy_from_amplitude(amp_norm):
    energy = amp_norm**2
    return energy / (torch.max(energy) + 1e-8)


def masked_values(field, mask):
    return field[mask > 0.5]


def stack_term(terms_by_z, key):
    return torch.stack([terms[key] for terms in terms_by_z])


def aggregate_z_quality_terms(terms_by_z):
    """Aggregate per-z cure metrics with explicit worst-plane penalties."""
    coverage = stack_term(terms_by_z, "target_coverage")
    target_p10 = stack_term(terms_by_z, "target_p10")
    target_p20 = stack_term(terms_by_z, "target_p20")
    p05_over_p50 = stack_term(terms_by_z, "target_p05_over_p50")
    p10_over_p50 = stack_term(terms_by_z, "target_p10_over_p50")
    p75_over_p25 = stack_term(terms_by_z, "target_p75_over_p25")
    p90_over_p10 = stack_term(terms_by_z, "target_p90_over_p10")
    p95_over_p05 = stack_term(terms_by_z, "target_p95_over_p05")
    band_spread_loss = stack_term(terms_by_z, "target_band_spread_loss")
    p90_over_mean = stack_term(terms_by_z, "target_p90_over_mean")
    p95_over_mean = stack_term(terms_by_z, "target_p95_over_mean")
    peak_over_mean = stack_term(terms_by_z, "target_peak_over_mean")
    target_floor_loss = stack_term(terms_by_z, "target_floor_loss")
    dark_ceiling_loss = stack_term(terms_by_z, "dark_ceiling_loss")
    separation_loss = stack_term(terms_by_z, "separation_loss")
    dark_band_spread_loss = stack_term(terms_by_z, "dark_band_spread_loss")
    dark_cv = stack_term(terms_by_z, "dark_cv")
    dark_p50 = stack_term(terms_by_z, "dark_p50")
    dark_p95 = stack_term(terms_by_z, "dark_p95")
    dark_p99 = stack_term(terms_by_z, "dark_p99")
    dark_p99_over_target_p50 = stack_term(terms_by_z, "dark_p99_over_target_p50")
    dark_peak_over_target_p50 = stack_term(terms_by_z, "dark_peak_over_target_p50")
    dark_high_area_fraction = stack_term(terms_by_z, "dark_high_area_fraction")
    target_cv = stack_term(terms_by_z, "target_cv")
    quality_score = stack_term(terms_by_z, "quality_score")

    mean_target_coverage = torch.mean(coverage)
    worst_target_coverage = torch.min(coverage)
    mean_p05_over_p50 = torch.mean(p05_over_p50)
    worst_p05_over_p50 = torch.min(p05_over_p50)
    mean_p10_over_p50 = torch.mean(p10_over_p50)
    worst_p10_over_p50 = torch.min(p10_over_p50)
    mean_target_cv = torch.mean(target_cv)
    worst_target_cv = torch.max(target_cv)

    return {
        "mean_threshold_loss": torch.mean(stack_term(terms_by_z, "threshold_loss")),
        "mean_low_quantile_loss": torch.mean(stack_term(terms_by_z, "low_quantile_loss")),
        "mean_target_band_spread_loss": torch.mean(band_spread_loss),
        "worst_target_band_spread_loss": torch.max(band_spread_loss),
        "mean_target_floor_loss": torch.mean(target_floor_loss),
        "worst_target_floor_loss": torch.max(target_floor_loss),
        "mean_dark_ceiling_loss": torch.mean(dark_ceiling_loss),
        "worst_dark_ceiling_loss": torch.max(dark_ceiling_loss),
        "mean_separation_loss": torch.mean(separation_loss),
        "worst_separation_loss": torch.max(separation_loss),
        "mean_dark_band_spread_loss": torch.mean(dark_band_spread_loss),
        "worst_dark_band_spread_loss": torch.max(dark_band_spread_loss),
        "mean_target_mean_amp_loss": torch.mean(stack_term(terms_by_z, "target_mean_amp_loss")),
        "mean_amp_uniformity_loss": torch.mean(stack_term(terms_by_z, "amp_uniformity_loss")),
        "mean_energy_uniformity_loss": torch.mean(stack_term(terms_by_z, "energy_uniformity_loss")),
        "mean_energy_efficiency": torch.mean(stack_term(terms_by_z, "energy_efficiency")),
        "mean_target_contrast_loss": torch.mean(stack_term(terms_by_z, "target_contrast_loss")),
        "mean_amp_corr_proxy": torch.mean(quality_score),
        "mean_dark_area_loss": torch.mean(stack_term(terms_by_z, "dark_area_loss")),
        "mean_dark_relative_loss": torch.mean(stack_term(terms_by_z, "dark_relative_loss")),
        "worst_dark_relative_loss": torch.max(stack_term(terms_by_z, "dark_relative_loss")),
        "mean_dark_mean_loss": torch.mean(stack_term(terms_by_z, "dark_mean_loss")),
        "mean_halo_loss": torch.mean(stack_term(terms_by_z, "halo_loss")),
        "mean_quality_score": torch.mean(quality_score),
        "worst_quality_score": torch.min(quality_score),
        "mean_target_coverage": mean_target_coverage,
        "worst_target_coverage": worst_target_coverage,
        "worst_target_coverage_loss": torch.relu(1.0 - worst_target_coverage) ** 2,
        "mean_target_p10": torch.mean(target_p10),
        "mean_target_p20": torch.mean(target_p20),
        "worst_target_p10": torch.min(target_p10),
        "worst_target_p20": torch.min(target_p20),
        "mean_target_p10_over_p50": mean_p10_over_p50,
        "worst_target_p10_over_p50": worst_p10_over_p50,
        "mean_target_p05_over_p50": mean_p05_over_p50,
        "worst_target_p05_over_p50": worst_p05_over_p50,
        "mean_target_p75_over_p25": torch.mean(p75_over_p25),
        "mean_target_p90_over_p10": torch.mean(p90_over_p10),
        "mean_target_p95_over_p05": torch.mean(p95_over_p05),
        "worst_low_quantile_loss": torch.max(stack_term(terms_by_z, "low_quantile_loss")),
        "mean_target_cv": mean_target_cv,
        "worst_target_cv": worst_target_cv,
        "worst_cv_loss": worst_target_cv**2,
        "mean_peak_balance_loss": torch.mean(stack_term(terms_by_z, "peak_balance_loss")),
        "worst_peak_balance_loss": torch.max(stack_term(terms_by_z, "peak_balance_loss")),
        "mean_target_p90_over_mean": torch.mean(p90_over_mean),
        "mean_target_p95_over_mean": torch.mean(p95_over_mean),
        "mean_target_peak_over_mean": torch.mean(peak_over_mean),
        "worst_target_p95_over_mean": torch.max(p95_over_mean),
        "worst_target_peak_over_mean": torch.max(peak_over_mean),
        "mean_dark_p99_over_target_p50": torch.mean(dark_p99_over_target_p50),
        "worst_dark_p99_over_target_p50": torch.max(dark_p99_over_target_p50),
        "mean_dark_peak_over_target_p50": torch.mean(dark_peak_over_target_p50),
        "worst_dark_peak_over_target_p50": torch.max(dark_peak_over_target_p50),
        "mean_dark_cv": torch.mean(dark_cv),
        "worst_dark_cv": torch.max(dark_cv),
        "mean_dark_p50": torch.mean(dark_p50),
        "mean_dark_p95": torch.mean(dark_p95),
        "mean_dark_p99": torch.mean(dark_p99),
        "worst_dark_p99": torch.max(dark_p99),
        "mean_dark_high_area_fraction": torch.mean(dark_high_area_fraction),
        "mean_dark_area_fraction": torch.mean(stack_term(terms_by_z, "dark_area_fraction")),
        "mean_target_mean_raw": torch.mean(stack_term(terms_by_z, "target_mean_raw")),
        "mean_target_to_global_mean": torch.mean(stack_term(terms_by_z, "target_to_global_mean")),
    }


def compute_cure_quality_terms(
    pred_amp_norm,
    target_binary,
    halo_mask,
    far_dark_mask,
    pred_amp_raw=None,
    threshold_norm=0.60,
    low_quantile_goal=0.88,
    target_mean_amp_goal=None,
):
    """Return differentiable quality terms for threshold-driven curing.

    The target mask should be uniformly above a normalized pressure threshold.
    Background penalties are area-based so an isolated bright pixel is less
    important than a sustained above-threshold leak.
    """
    if pred_amp_raw is None:
        pred_amp_raw = pred_amp_norm

    pred_energy = normalize_energy_from_amplitude(pred_amp_norm)
    inside_amp_vals = masked_values(pred_amp_norm, target_binary)
    inside_energy_vals = masked_values(pred_energy, target_binary)
    inside_raw_vals = masked_values(pred_amp_raw, target_binary)
    all_raw_vals = pred_amp_raw.reshape(-1)
    dark_amp_vals = masked_values(pred_amp_norm, far_dark_mask)
    dark_energy_vals = masked_values(pred_energy, far_dark_mask)
    halo_energy_vals = masked_values(pred_energy, halo_mask)

    zero = torch.tensor(0.0, dtype=pred_amp_norm.dtype, device=pred_amp_norm.device)
    if inside_amp_vals.numel() <= 4:
        return {
            "pred_energy": pred_energy,
            "target_amp_vals": inside_amp_vals,
            "target_energy_vals": inside_energy_vals,
            "dark_amp_vals": dark_amp_vals,
            "target_mean": zero,
            "target_mean_raw": zero,
            "target_mean_amp_loss": zero,
            "target_to_global_mean": zero,
            "target_contrast_loss": zero,
            "target_cv": zero,
            "energy_uniformity_loss": zero,
            "amp_uniformity_loss": zero,
            "threshold_loss": zero,
            "target_coverage": zero,
            "low_quantile_loss": zero,
            "peak_balance_loss": zero,
            "target_band_spread_loss": zero,
            "target_p05_over_p50": zero,
            "target_p10_over_p50": zero,
            "target_p10": zero,
            "target_p20": zero,
            "target_p75_over_p25": zero,
            "target_p90_over_p10": zero,
            "target_p95_over_p05": zero,
            "target_p90_over_mean": zero,
            "target_p95_over_mean": zero,
            "target_peak_over_mean": zero,
            "target_floor_loss": zero,
            "dark_mean_loss": zero,
            "dark_area_loss": zero,
            "dark_relative_loss": zero,
            "dark_ceiling_loss": zero,
            "separation_loss": zero,
            "dark_band_spread_loss": zero,
            "dark_cv": zero,
            "dark_area_fraction": zero,
            "dark_p50": zero,
            "dark_p95": zero,
            "dark_p99": zero,
            "dark_p95_over_target_p50": zero,
            "dark_p99_over_target_p50": zero,
            "dark_peak_over_target_p50": zero,
            "dark_high_area_fraction": zero,
            "halo_loss": zero,
            "energy_efficiency": zero,
            "quality_score": zero,
        }

    target_mean = torch.mean(inside_amp_vals)
    target_mean_raw = torch.mean(inside_raw_vals)
    global_mean_raw = torch.mean(all_raw_vals)
    target_to_global_mean = target_mean_raw / (global_mean_raw + 1e-8)
    target_std = torch.std(inside_amp_vals)
    target_cv = target_std / (target_mean + 1e-8)
    energy_uniformity_loss = torch.var(inside_energy_vals) / (torch.mean(inside_energy_vals) ** 2 + 1e-8)
    amp_uniformity_loss = torch.var(inside_amp_vals) / (target_mean**2 + 1e-8)

    threshold = torch.tensor(threshold_norm, dtype=pred_amp_norm.dtype, device=pred_amp_norm.device)
    threshold_loss = torch.mean(torch.relu(threshold - inside_amp_vals) ** 2) / (threshold**2 + 1e-8)
    target_coverage = torch.mean((inside_amp_vals >= threshold).float())

    target_p05 = torch.quantile(inside_amp_vals, 0.05)
    target_p10 = torch.quantile(inside_amp_vals, 0.10)
    target_p20 = torch.quantile(inside_amp_vals, 0.20)
    target_p25 = torch.quantile(inside_amp_vals, 0.25)
    target_p50 = torch.quantile(inside_amp_vals, 0.50)
    target_p75 = torch.quantile(inside_amp_vals, 0.75)
    target_p90 = torch.quantile(inside_amp_vals, 0.90)
    target_p95 = torch.quantile(inside_amp_vals, 0.95)
    target_peak = torch.max(inside_amp_vals)
    target_p05_over_p50 = target_p05 / (target_p50 + 1e-8)
    target_p10_over_p50 = target_p10 / (target_p50 + 1e-8)
    target_p75_over_p25 = target_p75 / (target_p25 + 1e-8)
    target_p90_over_p10 = target_p90 / (target_p10 + 1e-8)
    target_p95_over_p05 = target_p95 / (target_p05 + 1e-8)
    target_p90_over_mean = target_p90 / (target_mean + 1e-8)
    target_p95_over_mean = target_p95 / (target_mean + 1e-8)
    target_peak_over_mean = target_peak / (target_mean + 1e-8)
    low_quantile_target = torch.tensor(low_quantile_goal, dtype=pred_amp_norm.dtype, device=pred_amp_norm.device)
    low_quantile_loss = torch.relu(low_quantile_target - target_p10_over_p50) ** 2
    peak_balance_loss = (
        torch.relu(target_p90_over_mean - 1.20) ** 2
        + 1.5 * torch.relu(target_p95_over_mean - 1.32) ** 2
        + 1.1 * torch.relu(target_peak_over_mean - 1.85) ** 2
    )
    target_band_spread_loss = (
        torch.relu(target_p75_over_p25 - 1.42) ** 2
        + 0.8 * torch.relu(target_p90_over_p10 - 1.95) ** 2
        + 0.45 * torch.relu(target_p95_over_p05 - 2.60) ** 2
    )
    target_floor_loss = (
        torch.relu(threshold - target_p10) ** 2 / (threshold**2 + 1e-8)
        + 0.7 * torch.relu((threshold * 1.02) - target_p20) ** 2 / (threshold**2 + 1e-8)
    )
    target_mean_amp_loss = zero
    if target_mean_amp_goal is not None:
        target_mean_goal = torch.tensor(target_mean_amp_goal, dtype=pred_amp_norm.dtype, device=pred_amp_norm.device)
        target_mean_amp_loss = torch.relu(target_mean_goal - target_mean_raw) ** 2 / (target_mean_goal**2 + 1e-8)
    target_contrast_loss = 1.0 / (target_to_global_mean + 1e-8)

    dark_mean_loss = torch.mean(dark_energy_vals) if dark_energy_vals.numel() > 4 else zero
    if dark_amp_vals.numel() > 4:
        dark_p50 = torch.quantile(dark_amp_vals, 0.50)
        dark_p95 = torch.quantile(dark_amp_vals, 0.95)
        dark_p99 = torch.quantile(dark_amp_vals, 0.99)
        dark_peak = torch.max(dark_amp_vals)
        dark_mean = torch.mean(dark_amp_vals)
        dark_std = torch.std(dark_amp_vals)
        dark_cv = dark_std / (dark_mean + 1e-8)
        dark_p95_over_target_p50 = dark_p95 / (target_p50 + 1e-8)
        dark_p99_over_target_p50 = dark_p99 / (target_p50 + 1e-8)
        dark_peak_over_target_p50 = dark_peak / (target_p50 + 1e-8)
        dark_limit = 0.72 * target_p50
        dark_area_loss = torch.mean(torch.relu(dark_amp_vals - dark_limit) ** 2) / (target_p50**2 + 1e-8)
        dark_high_area_fraction = torch.mean((dark_amp_vals >= dark_limit).float())
        dark_ceiling = 0.62 * threshold
        dark_ceiling_loss = (
            torch.relu(dark_p95 - dark_ceiling) ** 2 / (threshold**2 + 1e-8)
            + 1.4 * torch.relu(dark_p99 - dark_ceiling) ** 2 / (threshold**2 + 1e-8)
        )
        separation_margin = target_p10 - dark_p99
        separation_goal = 0.12 * threshold
        separation_loss = torch.relu(separation_goal - separation_margin) ** 2 / (threshold**2 + 1e-8)
        dark_band_spread_loss = (
            torch.relu((dark_p95 / (dark_p50 + 1e-8)) - 1.18) ** 2
            + 0.9 * torch.relu((dark_p99 / (dark_p50 + 1e-8)) - 1.32) ** 2
            + 0.25 * dark_cv**2
        )
        dark_relative_loss = (
            torch.relu(dark_p99_over_target_p50 - 0.72) ** 2
            + 0.35 * torch.relu(dark_peak_over_target_p50 - 0.95) ** 2
            + 0.5 * dark_area_loss
        )
        dark_area_fraction = torch.mean((dark_amp_vals >= threshold).float())
    else:
        dark_p50 = zero
        dark_p95 = zero
        dark_p99 = zero
        dark_cv = zero
        dark_p95_over_target_p50 = zero
        dark_p99_over_target_p50 = zero
        dark_peak_over_target_p50 = zero
        dark_high_area_fraction = zero
        dark_area_loss = zero
        dark_relative_loss = zero
        dark_ceiling_loss = zero
        separation_loss = zero
        dark_band_spread_loss = zero
        dark_area_fraction = zero
    halo_loss = torch.mean(halo_energy_vals) if halo_energy_vals.numel() > 4 else zero
    energy_efficiency = torch.sum(pred_energy * target_binary) / (torch.sum(pred_energy) + 1e-8)

    quality_score = (
        2.0 / (1.0 + target_cv)
        + 1.8 * target_p10_over_p50
        + 0.9 * target_p05_over_p50
        + 0.8 * target_coverage
        - 1.2 * target_floor_loss
        - 1.2 * target_band_spread_loss
        - 1.4 * peak_balance_loss
        - 1.3 * dark_relative_loss
        - 1.2 * dark_ceiling_loss
        - 1.4 * separation_loss
        - 0.7 * dark_band_spread_loss
        - 0.3 * dark_high_area_fraction
    )

    return {
        "pred_energy": pred_energy,
        "target_amp_vals": inside_amp_vals,
        "target_energy_vals": inside_energy_vals,
        "dark_amp_vals": dark_amp_vals,
        "target_mean": target_mean,
        "target_mean_raw": target_mean_raw,
        "target_mean_amp_loss": target_mean_amp_loss,
        "target_to_global_mean": target_to_global_mean,
        "target_contrast_loss": target_contrast_loss,
        "target_cv": target_cv,
        "energy_uniformity_loss": energy_uniformity_loss,
        "amp_uniformity_loss": amp_uniformity_loss,
        "threshold_loss": threshold_loss,
        "target_coverage": target_coverage,
        "low_quantile_loss": low_quantile_loss,
        "peak_balance_loss": peak_balance_loss,
        "target_band_spread_loss": target_band_spread_loss,
        "target_floor_loss": target_floor_loss,
        "target_p05_over_p50": target_p05_over_p50,
        "target_p10_over_p50": target_p10_over_p50,
        "target_p10": target_p10,
        "target_p20": target_p20,
        "target_p75_over_p25": target_p75_over_p25,
        "target_p90_over_p10": target_p90_over_p10,
        "target_p95_over_p05": target_p95_over_p05,
        "target_p90_over_mean": target_p90_over_mean,
        "target_p95_over_mean": target_p95_over_mean,
        "target_peak_over_mean": target_peak_over_mean,
        "dark_mean_loss": dark_mean_loss,
        "dark_area_loss": dark_area_loss,
        "dark_relative_loss": dark_relative_loss,
        "dark_ceiling_loss": dark_ceiling_loss,
        "separation_loss": separation_loss,
        "dark_band_spread_loss": dark_band_spread_loss,
        "dark_cv": dark_cv,
        "dark_area_fraction": dark_area_fraction,
        "dark_p50": dark_p50,
        "dark_p95": dark_p95,
        "dark_p99": dark_p99,
        "dark_p95_over_target_p50": dark_p95_over_target_p50,
        "dark_p99_over_target_p50": dark_p99_over_target_p50,
        "dark_peak_over_target_p50": dark_peak_over_target_p50,
        "dark_high_area_fraction": dark_high_area_fraction,
        "halo_loss": halo_loss,
        "energy_efficiency": energy_efficiency,
        "quality_score": quality_score,
    }
