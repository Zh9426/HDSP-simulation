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
metrics.mean_dark_pressure_pa = mean(dark_values);
metrics.focus_contrast = metrics.mean_target_pressure_pa / (metrics.mean_dark_pressure_pa + eps);
metrics.energy_efficiency = sum(amp(target_mask).^2) / (sum(amp(:).^2) + eps);
metrics.pcc = pcc;
metrics.nmse = sum((amp_norm(:) - target_norm(:)).^2) / (sum(target_norm(:).^2) + eps);
metrics.peak_global_x_mm = x(peak_row) * 1e3;
metrics.peak_global_y_mm = y(peak_col) * 1e3;
metrics.peak_target_x_mm = x(target_peak_row) * 1e3;
metrics.peak_target_y_mm = y(target_peak_col) * 1e3;
metrics.target_pressure_p10_pa = prctile(target_values, 10);
metrics.target_pressure_p50_pa = prctile(target_values, 50);
metrics.target_pressure_p90_pa = prctile(target_values, 90);

if exist('ssim', 'file') == 2
    metrics.ssim = ssim(amp_norm, target_norm);
else
    metrics.ssim = NaN;
end
end
