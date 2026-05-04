clear; close all; clc;

script_dir = fileparts(mfilename('fullpath'));
work_dir = fileparts(script_dir);
out_dir = fullfile(work_dir, 'outputs');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end
addpath(script_dir);

Nx = 256;
Lx = 40e-3;
x = linspace(-Lx/2, Lx/2, Nx);
[X, Y] = meshgrid(x, x);
target_mask = abs(X) < 9e-3 & abs(Y) < 2.4e-3;
target_mask = target_mask | ((X + 7e-3).^2 + (Y - 4e-3).^2 < (3.2e-3)^2);
target_mask = target_mask | ((X - 7e-3).^2 + (Y + 4e-3).^2 < (3.2e-3)^2);

core_pressure = 1.98e6 .* double(target_mask);
halo_pressure = 1.62e6 .* exp(-((abs(Y) - 2.8e-3).^2) ./ (2 * (1.4e-3)^2)) ...
    .* exp(-(X.^2) ./ (2 * (13e-3)^2));
p_amp = max(core_pressure, halo_pressure);
p_amp = p_amp + 0.18e6 .* exp(-((X + 10e-3).^2 + (Y + 7e-3).^2) ./ (2 * (2.0e-3)^2));

cavitation_model = struct();
cavitation_model.mask = true(size(p_amp));
cavitation_model.pressure_on = 1.72e6;
cavitation_model.pressure_full = 1.98e6;
cavitation_model.pressure_stream = 2.35e6;
cavitation_model.pressure_damage = 2.80e6;
cavitation_model.saturation_shape = 4.0;
cavitation_model.trigger_sharpness = 3.0;
cavitation_model.streaming_penalty_strength = 0.75;
cavitation_model.streaming_penalty_power = 1.5;
cavitation_model.smooth_sigma_px = 0.8;

cure_model = struct();
cure_model.threshold = 1.0;
cure_model.cavitation_dose_time = 0.04;
cure_model.dose_growth_floor = 0.65;
cure_model.dose_trigger_weight = 0.35;
cure_model.dose_cloud_radius_px = 2;
cure_model.dose_cloud_floor = 0.45;
cure_model.dose_cloud_power = 1.0;
cure_model.dose_cloud_weight = 0.0;
cure_model.dose_seed_floor = 0.85;
cure_model.dose_seed_power = 1.0;
cure_model.dose_fill_radius_px = 2;
cure_model.dose_fill_weight = 0.0;
cure_model.dose_fill_growth_ref = 0.20;
cure_model.thermal_delta_ref = 20.0;
cure_model.thermal_dose_time = 0.12;
cure_model.thermal_weight = 0.0;
cure_model.quality_risk_weight = 0.80;

exposure_time = 0.62;
cav = compute_cavitation_activity_map(p_amp, cavitation_model);
[dose_rate, dose_components] = compute_cavitation_dose_rate(cav.trigger, cav.growth, cure_model);
cavitation_dose = dose_rate .* (exposure_time / max(cure_model.cavitation_dose_time, eps));
bulk_temp_rise = 12 + 18 .* (p_amp ./ max(p_amp(:))).^2;
thermal_dose = compute_thermal_aux_increment(bulk_temp_rise, exposure_time, true, cure_model, cav.growth);
[cure_score, cured_mask, score_components] = compute_cavitation_cure_score( ...
    cavitation_dose, thermal_dose, cav.penalty, cure_model);
metrics = evaluate_cure_prediction(cure_score, target_mask, cure_model.threshold);

summary = struct();
summary.Nx = Nx;
summary.Lx_m = Lx;
summary.exposure_time_s = exposure_time;
summary.pressure_peak_mpa = max(p_amp(:)) / 1e6;
summary.pressure_roi_mean_mpa = mean(p_amp(target_mask)) / 1e6;
summary.cavitation_dose_peak = max(cavitation_dose(:));
summary.cavitation_dose_roi_mean = mean(cavitation_dose(target_mask));
summary.thermal_dose_roi_mean = mean(thermal_dose(target_mask));
summary.IoU = metrics.IoU;
summary.Dice = metrics.Dice;
summary.over_cure_ratio = metrics.over_cure_ratio;
summary.under_cure_ratio = metrics.under_cure_ratio;
summary.cured_coverage = metrics.cured_coverage;

save(fullfile(out_dir, 'cure_prediction_demo_results.mat'), ...
    'summary', 'x', 'target_mask', 'p_amp', 'cav', 'dose_rate', ...
    'dose_components', 'cavitation_dose', 'thermal_dose', 'cure_score', ...
    'cured_mask', 'score_components', 'metrics', '-v7.3');

fig = figure('Color', 'w', 'Position', [80, 80, 1500, 720]);
tiledlayout(2, 4, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile; imagesc(x * 1e3, x * 1e3, target_mask); axis image; colormap(gca, gray); colorbar; title('Target mask');
nexttile; imagesc(x * 1e3, x * 1e3, p_amp / 1e6); axis image; colormap(gca, turbo); colorbar; title('Pressure MPa');
nexttile; imagesc(x * 1e3, x * 1e3, cav.trigger); axis image; colormap(gca, turbo); colorbar; title('Cavitation trigger');
nexttile; imagesc(x * 1e3, x * 1e3, cav.growth); axis image; colormap(gca, turbo); colorbar; title('Cavitation growth');
nexttile; imagesc(x * 1e3, x * 1e3, cavitation_dose); axis image; colormap(gca, turbo); colorbar; title('Cavitation dose');
nexttile; imagesc(x * 1e3, x * 1e3, thermal_dose); axis image; colormap(gca, turbo); colorbar; title('Thermal diagnostic');
nexttile; imagesc(x * 1e3, x * 1e3, cure_score); axis image; colormap(gca, turbo); colorbar; title('Cure score');
nexttile; imagesc(x * 1e3, x * 1e3, cured_mask); axis image; colormap(gca, gray); colorbar; title(sprintf('Cured IoU %.3f', metrics.IoU));
exportgraphics(fig, fullfile(out_dir, 'cure_prediction_demo_overview.png'), 'Resolution', 250);

fid = fopen(fullfile(out_dir, 'summary.txt'), 'w');
if fid > 0
    fprintf(fid, 'Cure prediction module demo summary\n');
    fprintf(fid, 'Outputs: %s\n\n', out_dir);
    fprintf(fid, 'Pressure peak/ROI mean: %.3f / %.3f MPa\n', summary.pressure_peak_mpa, summary.pressure_roi_mean_mpa);
    fprintf(fid, 'Cavitation dose peak/ROI mean: %.4f / %.4f\n', summary.cavitation_dose_peak, summary.cavitation_dose_roi_mean);
    fprintf(fid, 'Thermal diagnostic ROI mean: %.4f\n', summary.thermal_dose_roi_mean);
    fprintf(fid, 'IoU/Dice/over/under/coverage: %.4f / %.4f / %.2f%% / %.2f%% / %.2f%%\n', ...
        summary.IoU, summary.Dice, summary.over_cure_ratio * 100, ...
        summary.under_cure_ratio * 100, summary.cured_coverage * 100);
    fclose(fid);
end
fid_json = fopen(fullfile(out_dir, 'summary.json'), 'w');
if fid_json > 0
    fwrite(fid_json, jsonencode(summary));
    fclose(fid_json);
end

fprintf('Cure demo outputs saved to: %s\n', out_dir);
