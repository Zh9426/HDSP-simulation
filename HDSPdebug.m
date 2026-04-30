clear; close all; clc;

%% 1. Target and grid
Nx = 512;
Lx = 65e-3;
dx = Lx / Nx;
x = (-Nx/2 : Nx/2-1) * dx;
[Y_grid, X_grid] = meshgrid(x, x);

strut_width = 1.0e-3;
pore_size = 3.0e-3;
pitch = strut_width + pore_size;
mask_X = mod(X_grid + pitch / 2, pitch) < strut_width;
mask_Y = mod(Y_grid + pitch / 2, pitch) < strut_width;
scaffold_raw = mask_X | mask_Y;

target_radius = 15e-3;
circle_mask = (X_grid.^2 + Y_grid.^2) <= target_radius^2;
imag_target_raw = scaffold_raw & circle_mask;
imag_target = imgaussfilt(double(imag_target_raw), 0.5);
imag_target = imag_target / max(imag_target(:));
target_mask = imag_target > 0.5;
ROI_pixels = nnz(target_mask);

%% 2. Fixed physical cure model
cure_model = struct();
cure_model.pressure_on = 1.72e6;
cure_model.pressure_full = 1.98e6;
cure_model.pressure_stream = 2.35e6;
cure_model.pressure_damage = 2.80e6;
cure_model.saturation_shape = 4.0;
cure_model.trigger_sharpness = 3.0;
cure_model.streaming_penalty_strength = 0.75;
cure_model.streaming_penalty_power = 1.5;
cure_model.smooth_sigma_px = 0.0;

cure_model.threshold = 1.0;
cure_model.cavitation_dose_time = 0.04;
cure_model.thermal_weight = 0.0;
cure_model.penalty_weight = 0.80;
cure_model.dose_growth_floor = 0.65;
cure_model.dose_trigger_weight = 0.35;
cure_model.dose_cloud_radius_px = 0;
cure_model.dose_cloud_floor = 1.0;
cure_model.dose_cloud_weight = 0.0;
cure_model.dose_seed_floor = 1.0;
cure_model.dose_fill_radius_px = 0;
cure_model.dose_fill_weight = 0.0;

%% 3. Perfect pressure field for cure-module validation
target_pressure = 2.25e6;
background_pressure = 1.20e6;
exposure_time = 0.06;

p_amp = ones(Nx, Nx) .* background_pressure;
p_amp(target_mask) = target_pressure;

result = simulate_cure_from_pressure_map( ...
    p_amp, exposure_time, cure_model, target_mask);

cured_mask = result.cured_mask;
metrics = result.metrics;
cavitation_dose = result.score_components.cavitation_dose;
thermal_contribution = result.score_components.thermal_contribution;
penalty_contribution = result.score_components.penalty_contribution;

%% 4. Report
fprintf('\n========================================\n');
fprintf('Standalone Cure-Model Validation\n');
fprintf('Grid: %d x %d | dx %.2f um | ROI pixels %d\n', ...
    Nx, Nx, dx * 1e6, ROI_pixels);
fprintf('Pressure field: target %.2f MPa | background %.2f MPa | exposure %.3f s\n', ...
    target_pressure / 1e6, background_pressure / 1e6, exposure_time);
fprintf('Cure threshold: %.2f (fixed physical criterion)\n', cure_model.threshold);
fprintf('----------------------------------------\n');
fprintf('Cavitation activity peak/ROI mean: %.4f / %.4f\n', ...
    max(result.cavitation.activity(:)), mean(result.cavitation.activity(target_mask)));
fprintf('Cavitation dose peak/ROI mean: %.4f / %.4f\n', ...
    max(cavitation_dose(:)), mean(cavitation_dose(target_mask)));
fprintf('Thermal contribution ROI mean: %.4f\n', mean(thermal_contribution(target_mask)));
fprintf('Overdrive penalty ROI mean: %.4f\n', mean(penalty_contribution(target_mask)));
fprintf('----------------------------------------\n');
fprintf('Perfect-pressure cure prediction\n');
fprintf('IoU: %.4f\n', metrics.IoU);
fprintf('Dice: %.4f\n', metrics.Dice);
fprintf('Effective cure: %.1f%%\n', metrics.cured_coverage * 100);
fprintf('Over-cure: %.1f%%\n', metrics.over_cure_ratio * 100);
fprintf('Under-cure: %.1f%%\n', metrics.under_cure_ratio * 100);
fprintf('========================================\n');

%% 5. Visualization
figure(1); clf; set(gcf, 'Color', 'w', 'Position', [120, 120, 1200, 360]);
subplot(1, 3, 1);
imagesc(x * 1e3, x * 1e3, target_mask); axis image; colormap(gca, gray);
title('Target mask'); xlabel('mm'); ylabel('mm');

subplot(1, 3, 2);
imagesc(x * 1e3, x * 1e3, p_amp / 1e6); axis image; colormap(gca, turbo); colorbar;
title('Perfect pressure (MPa)'); xlabel('mm'); ylabel('mm');

subplot(1, 3, 3);
imagesc(x * 1e3, x * 1e3, cured_mask); axis image; colormap(gca, gray);
title(sprintf('Predicted cure | IoU %.4f', metrics.IoU)); xlabel('mm'); ylabel('mm');
