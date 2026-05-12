function metrics = calculate_pressure_metrics(pressure_amp, target_amp, target_mask, x, y)
%CALCULATE_PRESSURE_METRICS Metrics centered on pressure-amplitude quality.
amp = double(pressure_amp);
target = double(target_amp);
amp_norm = amp / (max(amp(:)) + eps);
target_norm = target / (max(target(:)) + eps);
dark_mask = ~target_mask;

[peak_global, peak_linear_idx] = max(amp(:));
[peak_row, peak_col] = ind2sub(size(amp), peak_linear_idx);
target_values = amp(target_mask);
dark_values = amp(dark_mask);
target_energy = amp(target_mask).^2;
dark_energy = amp(dark_mask).^2;

target_amp_for_peak = amp;
target_amp_for_peak(~target_mask) = -inf;
[peak_target, peak_target_idx] = max(target_amp_for_peak(:));
[target_peak_row, target_peak_col] = ind2sub(size(amp), peak_target_idx);

pred_centered = amp_norm(:) - mean(amp_norm(:));
target_centered = target_norm(:) - mean(target_norm(:));
pcc = sum(pred_centered .* target_centered) / ...
    (sqrt(sum(pred_centered.^2) * sum(target_centered.^2)) + eps);

metrics.peak_global_pressure_pa = peak_global;
metrics.peak_target_pressure_pa = peak_target;
metrics.mean_target_pressure_pa = mean(target_values);
metrics.std_target_pressure_pa = std(target_values);
metrics.target_uniformity_cv = metrics.std_target_pressure_pa / (metrics.mean_target_pressure_pa + eps);
metrics.target_uniformity_score = 1 / (1 + metrics.target_uniformity_cv);
metrics.mean_dark_pressure_pa = mean(dark_values);
metrics.max_dark_pressure_pa = max(dark_values);
metrics.focus_contrast = metrics.mean_target_pressure_pa / (metrics.mean_dark_pressure_pa + eps);
metrics.peak_sidelobe_ratio = metrics.peak_target_pressure_pa / (metrics.max_dark_pressure_pa + eps);
metrics.energy_efficiency = sum(target_energy) / (sum(amp(:).^2) + eps);
metrics.dark_energy_leakage = sum(dark_energy) / (sum(amp(:).^2) + eps);
metrics.target_energy_uniformity_cv = std(target_energy) / (mean(target_energy) + eps);
metrics.target_energy_uniformity_score = 1 / (1 + metrics.target_energy_uniformity_cv);
metrics.target_pressure_coverage_50 = mean(target_values >= 0.5 * metrics.peak_target_pressure_pa);
metrics.target_pressure_coverage_70 = mean(target_values >= 0.7 * metrics.peak_target_pressure_pa);
metrics.pcc = pcc;
metrics.nmse = sum((amp_norm(:) - target_norm(:)).^2) / (sum(target_norm(:).^2) + eps);
metrics.peak_global_x_mm = x(peak_row) * 1e3;
metrics.peak_global_y_mm = y(peak_col) * 1e3;
metrics.peak_target_x_mm = x(target_peak_row) * 1e3;
metrics.peak_target_y_mm = y(target_peak_col) * 1e3;
target_centroid_x = sum(target .* reshape(x, [], 1), 'all') / (sum(target(:)) + eps);
target_centroid_y = sum(target .* reshape(y, 1, []), 'all') / (sum(target(:)) + eps);
metrics.peak_target_error_mm = sqrt((x(target_peak_row) - target_centroid_x)^2 + ...
    (y(target_peak_col) - target_centroid_y)^2) * 1e3;
metrics.target_pressure_p05_pa = prctile(target_values, 5);
metrics.target_pressure_p10_pa = prctile(target_values, 10);
metrics.target_pressure_p50_pa = prctile(target_values, 50);
metrics.target_pressure_p90_pa = prctile(target_values, 90);
metrics.target_pressure_p95_pa = prctile(target_values, 95);
metrics.dark_pressure_p95_pa = prctile(dark_values, 95);
metrics.dark_pressure_p99_pa = prctile(dark_values, 99);
metrics.target_p05_over_p50 = metrics.target_pressure_p05_pa / (metrics.target_pressure_p50_pa + eps);
metrics.target_p10_over_p50 = metrics.target_pressure_p10_pa / (metrics.target_pressure_p50_pa + eps);
metrics.target_p90_over_mean = metrics.target_pressure_p90_pa / (metrics.mean_target_pressure_pa + eps);
metrics.target_p95_over_mean = metrics.target_pressure_p95_pa / (metrics.mean_target_pressure_pa + eps);
metrics.target_peak_over_mean = metrics.peak_target_pressure_pa / (metrics.mean_target_pressure_pa + eps);
metrics.dark_p95_over_target_p50 = metrics.dark_pressure_p95_pa / (metrics.target_pressure_p50_pa + eps);
metrics.dark_p99_over_target_p50 = metrics.dark_pressure_p99_pa / (metrics.target_pressure_p50_pa + eps);
metrics.dark_peak_over_target_p50 = metrics.max_dark_pressure_pa / (metrics.target_pressure_p50_pa + eps);
metrics.dark_high_area_fraction = mean(dark_values >= 0.72 * metrics.target_pressure_p50_pa);
dark_relative_penalty = ...
    max(metrics.dark_p99_over_target_p50 - 0.72, 0)^2 + ...
    0.35 * max(metrics.dark_peak_over_target_p50 - 0.95, 0)^2 + ...
    0.5 * metrics.dark_high_area_fraction;
metrics.target_pressure_quality_score = ...
    2.8 * metrics.target_uniformity_score + ...
    2.2 * metrics.target_p10_over_p50 + ...
    1.2 * metrics.target_p05_over_p50 + ...
    0.5 * metrics.pcc - ...
    1.2 * max(metrics.target_p95_over_mean - 1.25, 0)^2 - ...
    0.8 * max(metrics.target_peak_over_mean - 1.60, 0)^2 - ...
    1.6 * dark_relative_penalty;

if exist('ssim', 'file') == 2
    metrics.ssim = ssim(amp_norm, target_norm);
else
    metrics.ssim = NaN;
end
end
