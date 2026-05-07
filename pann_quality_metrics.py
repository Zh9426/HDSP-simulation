import torch


def normalize_energy_from_amplitude(amp_norm):
    energy = amp_norm**2
    return energy / (torch.max(energy) + 1e-8)


def masked_values(field, mask):
    return field[mask > 0.5]


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
            "target_p10_over_p50": zero,
            "dark_mean_loss": zero,
            "dark_area_loss": zero,
            "dark_area_fraction": zero,
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

    target_p10 = torch.quantile(inside_amp_vals, 0.10)
    target_p50 = torch.quantile(inside_amp_vals, 0.50)
    target_p10_over_p50 = target_p10 / (target_p50 + 1e-8)
    low_quantile_target = torch.tensor(low_quantile_goal, dtype=pred_amp_norm.dtype, device=pred_amp_norm.device)
    low_quantile_loss = torch.relu(low_quantile_target - target_p10_over_p50) ** 2
    target_mean_amp_loss = zero
    if target_mean_amp_goal is not None:
        target_mean_goal = torch.tensor(target_mean_amp_goal, dtype=pred_amp_norm.dtype, device=pred_amp_norm.device)
        target_mean_amp_loss = torch.relu(target_mean_goal - target_mean_raw) ** 2 / (target_mean_goal**2 + 1e-8)
    target_contrast_loss = 1.0 / (target_to_global_mean + 1e-8)

    dark_mean_loss = torch.mean(dark_energy_vals) if dark_energy_vals.numel() > 4 else zero
    dark_area_loss = (
        torch.mean(torch.relu(dark_amp_vals - threshold) ** 2) / (threshold**2 + 1e-8)
        if dark_amp_vals.numel() > 4
        else zero
    )
    dark_area_fraction = (
        torch.mean((dark_amp_vals >= threshold).float())
        if dark_amp_vals.numel() > 4
        else zero
    )
    halo_loss = torch.mean(halo_energy_vals) if halo_energy_vals.numel() > 4 else zero
    energy_efficiency = torch.sum(pred_energy * target_binary) / (torch.sum(pred_energy) + 1e-8)

    quality_score = (
        4.0 * target_coverage
        + 2.5 * target_p10_over_p50
        + 1.5 / (1.0 + target_cv)
        + 0.8 * energy_efficiency
        + 0.4 * torch.log1p(target_to_global_mean)
        - 0.7 * target_mean_amp_loss
        - 0.8 * dark_area_fraction
        - 0.2 * halo_loss
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
        "target_p10_over_p50": target_p10_over_p50,
        "dark_mean_loss": dark_mean_loss,
        "dark_area_loss": dark_area_loss,
        "dark_area_fraction": dark_area_fraction,
        "halo_loss": halo_loss,
        "energy_efficiency": energy_efficiency,
        "quality_score": quality_score,
    }
