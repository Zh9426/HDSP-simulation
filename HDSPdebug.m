clear; close all; clc;

%% 1. Lightweight HDSP target scaffold
target = build_hdsp_validation_target(512, 65e-3);
target_mask = target.mask;

%% 2. Full fixed cure model
cure_model = default_cure_model_params(target.dx);
exposure_time = 0.06;

%% 3. Pressure providers for cure-model validation
pressure_cases = build_pressure_validation_cases(target_mask, cure_model, target.dx);
[records, simulations] = evaluate_cure_validation_cases( ...
    pressure_cases, exposure_time, cure_model, target_mask);

case_names = string({records.name});
ideal_idx = find(case_names == "ideal_binary", 1);
[~, best_idx] = max([records.IoU]);

%% 4. Report
fprintf('\n========================================\n');
fprintf('Standalone HDSP Cure-Model Validation\n');
fprintf('Grid: %d x %d | dx %.2f um | ROI pixels %d\n', ...
    target.Nx, target.Nx, target.dx * 1e6, target.roi_pixels);
fprintf('Exposure: %.3f s | Cure threshold: %.2f fixed\n', ...
    exposure_time, cure_model.threshold);
fprintf('Full cure model: cavitation dose + thermal diffusion auxiliary + overdrive penalty\n');
fprintf('----------------------------------------\n');
fprintf('case | target MPa | bg max MPa | IoU | Dice | coverage | over | under | cav dose ROI | thermal ROI/bg\n');
for idx = 1:numel(records)
    r = records(idx);
    fprintf('%s | %.2f | %.2f | %.4f | %.4f | %.1f%% | %.1f%% | %.1f%% | %.4f | %.4f/%.4f\n', ...
        r.name, r.pressure_target_mean_MPa, r.pressure_background_max_MPa, ...
        r.IoU, r.Dice, r.coverage * 100, r.over_cure * 100, ...
        r.under_cure * 100, r.cavitation_dose_roi_mean, ...
        r.thermal_dose_roi_mean, r.thermal_dose_background_mean);
end
fprintf('----------------------------------------\n');
fprintf('Ideal binary pressure is only the upper-bound sanity case.\n');
fprintf('Semi-ideal cases test edge blur, leakage, speckle, rolloff, and off-target lobes.\n');
fprintf('Best validation case by IoU: %s (IoU %.4f)\n', ...
    records(best_idx).name, records(best_idx).IoU);
fprintf('========================================\n');

%% 5. Visualization
if isempty(ideal_idx)
    ideal_idx = 1;
end
ideal_sim = simulations{ideal_idx};
best_sim = simulations{best_idx};

figure(1); clf; set(gcf, 'Color', 'w', 'Position', [120, 120, 1280, 720]);
subplot(2, 3, 1);
imagesc(target.x * 1e3, target.x * 1e3, target_mask); axis image;
colormap(gca, gray); title('Target mask'); xlabel('mm'); ylabel('mm');

subplot(2, 3, 2);
imagesc(target.x * 1e3, target.x * 1e3, pressure_cases(ideal_idx).pressure_map / 1e6);
axis image; colormap(gca, turbo); colorbar;
title('Ideal pressure (MPa)'); xlabel('mm'); ylabel('mm');

subplot(2, 3, 3);
imagesc(target.x * 1e3, target.x * 1e3, ideal_sim.cured_mask); axis image;
colormap(gca, gray);
title(sprintf('Ideal cure | IoU %.4f', records(ideal_idx).IoU));
xlabel('mm'); ylabel('mm');

subplot(2, 3, 4);
imagesc(target.x * 1e3, target.x * 1e3, pressure_cases(best_idx).pressure_map / 1e6);
axis image; colormap(gca, turbo); colorbar;
title(sprintf('%s pressure', records(best_idx).name), 'Interpreter', 'none');
xlabel('mm'); ylabel('mm');

subplot(2, 3, 5);
imagesc(target.x * 1e3, target.x * 1e3, best_sim.cure_score); axis image;
colormap(gca, hot); colorbar;
title(sprintf('%s cure score', records(best_idx).name), 'Interpreter', 'none');
xlabel('mm'); ylabel('mm');

subplot(2, 3, 6);
imagesc(target.x * 1e3, target.x * 1e3, best_sim.cured_mask); axis image;
colormap(gca, gray);
title(sprintf('%s cure | IoU %.4f', records(best_idx).name, records(best_idx).IoU), ...
    'Interpreter', 'none');
xlabel('mm'); ylabel('mm');
