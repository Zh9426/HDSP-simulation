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
nonideal_idx = find(case_names ~= "ideal_binary");
[~, local_degraded_idx] = min([records(nonideal_idx).IoU]);
diagnostic_idx = nonideal_idx(local_degraded_idx);

%% 4. Report
fprintf('\n========================================\n');
fprintf('Standalone HDSP Cure-Model Validation\n');
fprintf('Grid: %d x %d | dx %.2f um | ROI pixels %d\n', ...
    target.Nx, target.Nx, target.dx * 1e6, target.roi_pixels);
fprintf('Exposure: %.3f s | Cure threshold: %.2f fixed\n', ...
    exposure_time, cure_model.threshold);
fprintf('Cure model: cavitation dose decides cure; thermal diffusion is diagnostic; overdrive is quality risk\n');
fprintf('----------------------------------------\n');
fprintf('case | target MPa | bg max MPa | IoU | Dice | coverage | over | under | cav dose ROI | thermal ROI/bg | quality risk ROI/peak\n');
for idx = 1:numel(records)
    r = records(idx);
    fprintf('%s | %.2f | %.2f | %.4f | %.4f | %.1f%% | %.1f%% | %.1f%% | %.4f | %.4f/%.4f | %.4f/%.4f\n', ...
        r.name, r.pressure_target_mean_MPa, r.pressure_background_max_MPa, ...
        r.IoU, r.Dice, r.coverage * 100, r.over_cure * 100, ...
        r.under_cure * 100, r.cavitation_dose_roi_mean, ...
        r.thermal_dose_roi_mean, r.thermal_dose_background_mean, ...
        r.quality_risk_roi_mean, r.quality_risk_peak);
end
fprintf('----------------------------------------\n');
fprintf('Ideal binary pressure is only the upper-bound sanity case.\n');
fprintf('Semi-ideal cases test edge blur, leakage, speckle, rolloff, and off-target lobes.\n');
fprintf('Most degraded semi-ideal case: %s (IoU %.4f)\n', ...
    records(diagnostic_idx).name, records(diagnostic_idx).IoU);
fprintf('========================================\n');

%% 5. Visualization
visual_idx = select_cure_visualization_cases(records);
num_cases = numel(visual_idx);

figure(1); clf; set(gcf, 'Color', 'w', 'Position', [80, 60, 1760, 980]);
tiledlayout(4, num_cases, 'TileSpacing', 'compact', 'Padding', 'compact');
for col = 1:num_cases
    idx = visual_idx(col);
    sim = simulations{idx};
    case_pressure = pressure_cases(idx).pressure_map;
    case_error = build_cure_error_map(sim.cured_mask, target_mask);

    nexttile(col);
    imagesc(target.x * 1e3, target.x * 1e3, case_pressure / 1e6);
    format_map_axis(); colormap(gca, turbo); colorbar;
    title(sprintf('%s\npressure MPa', records(idx).name), 'Interpreter', 'none');
    if col == 1, ylabel('pressure'); end

    nexttile(num_cases + col);
    imagesc(target.x * 1e3, target.x * 1e3, sim.cure_score);
    format_map_axis(); colormap(gca, hot); colorbar;
    title(sprintf('dose | IoU %.4f', records(idx).IoU), 'Interpreter', 'none');
    if col == 1, ylabel('cav dose'); end

    nexttile(2 * num_cases + col);
    imagesc(target.x * 1e3, target.x * 1e3, sim.cured_mask);
    format_map_axis(); colormap(gca, gray);
    title(sprintf('cured | under %.1f%%', records(idx).under_cure * 100), ...
        'Interpreter', 'none');
    if col == 1, ylabel('cured'); end

    nexttile(3 * num_cases + col);
    imagesc(target.x * 1e3, target.x * 1e3, case_error, [0, 3]);
    format_map_axis(); colormap(gca, cure_error_colormap());
    title(sprintf('error | over %.1f%%', records(idx).over_cure * 100), ...
        'Interpreter', 'none');
    if col == 1, ylabel('error'); end
end
sgtitle('Cure validation: pressure -> cavitation dose -> cure mask -> error map');

figure(2); clf; set(gcf, 'Color', 'w', 'Position', [120, 120, 1760, 520]);
tiledlayout(2, num_cases, 'TileSpacing', 'compact', 'Padding', 'compact');
for col = 1:num_cases
    idx = visual_idx(col);
    sim = simulations{idx};

    nexttile(col);
    imagesc(target.x * 1e3, target.x * 1e3, sim.score_components.thermal_dose);
    format_map_axis(); colormap(gca, parula); colorbar;
    title(sprintf('%s\nthermal diagnostic', records(idx).name), 'Interpreter', 'none');
    if col == 1, ylabel('thermal'); end

    nexttile(num_cases + col);
    imagesc(target.x * 1e3, target.x * 1e3, sim.score_components.quality_risk, [0, 1]);
    format_map_axis(); colormap(gca, hot); colorbar;
    title(sprintf('quality risk peak %.3f', records(idx).quality_risk_peak), ...
        'Interpreter', 'none');
    if col == 1, ylabel('quality risk'); end
end
sgtitle('Diagnostics only: thermal diffusion does not enter cure score');

function error_map = build_cure_error_map(cured_mask, target_mask)
error_map = zeros(size(target_mask));
error_map(cured_mask & target_mask) = 1;
error_map(~cured_mask & target_mask) = 2;
error_map(cured_mask & ~target_mask) = 3;
end

function cmap = cure_error_colormap()
cmap = [ ...
    1.00, 1.00, 1.00; ...
    0.10, 0.32, 0.75; ...
    1.00, 0.62, 0.05; ...
    0.85, 0.10, 0.10];
end

function format_map_axis()
axis image;
set(gca, 'XTick', [], 'YTick', []);
end
