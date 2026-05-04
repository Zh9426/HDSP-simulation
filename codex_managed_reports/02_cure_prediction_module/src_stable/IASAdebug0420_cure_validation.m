clear; close all; clc;
try
    reset(gpuDevice);
catch
end

addpath('F:\MATLAB\code\HDSP\HDSP\HDSP0420');
addpath('F:\GitHub\HDSP-simulation');
rng(9426);

%% 1. Parameters
Nx = 512;
Ny = Nx;
Lx = 65e-3;
z_target_dist = 16e-3;
f0 = 4.5e6;
c_water = 1480;
c_board = 2430;
density_water = 997;
lambda_water = c_water / f0;
phase_refine_mode = 'python_iasa';
iasa_epoch = 150;
iasa_anchor_eta = 1.0;
min_base_layers = 2;

pressure_scan = (1.35:0.05:2.35) * 1e6;
exposure_scan = 0.04:0.02:0.80;

cavitation_model.pressure_on = 1.8e6;
cavitation_model.pressure_full = 2.2e6;
cavitation_model.pressure_stream = 2.7e6;
cavitation_model.pressure_damage = 3.2e6;
cavitation_model.saturation_shape = 4.0;
cavitation_model.trigger_sharpness = 3.0;
cavitation_model.streaming_penalty_strength = 0.75;
cavitation_model.streaming_penalty_power = 1.5;
cavitation_model.smooth_sigma_px = 0.0;

cure_model.threshold = 1.0;
cure_model.cavitation_dose_time = 0.04;
cure_model.thermal_weight = 0.0;
cure_model.penalty_weight = 0.0;
cure_model.quality_risk_weight = 0.80;
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
cure_model.dose_fill_power = 1.0;

dx = Lx / Nx;
dy = dx;
dz = dx;
Lz_needed = 20e-3;
Nz_min = ceil(Lz_needed / dz);
optimal_sizes = [128, 192, 216, 256, 300, 384, 512];
Nz = optimal_sizes(find(optimal_sizes >= Nz_min, 1));
Lz = Nz * dz;
x = (-Nx/2 : Nx/2-1) * dx;
y = x;
[Y_grid, X_grid] = meshgrid(y, x);

fprintf('==================================================\n');
fprintf('IASAdebug0420 cure-model validation: Python + IASA only\n');
fprintf('Grid dx = dy = dz = %.4f mm | PPW = %.2f\n', dx * 1e3, lambda_water / dx);
fprintf('Grid size: %d x %d x %d (%.1f M cells)\n', Nx, Ny, Nz, (Nx * Ny * Nz) / 1e6);
fprintf('==================================================\n');

%% 2. Target pattern and Python transport file
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

thermal_alpha_guess = 0.15 / (1100 * 1800);
thermal_exposure_guess = 0.35;
thermal_diff_len = sqrt(4 * thermal_alpha_guess * thermal_exposure_guess);
thermal_sigma_px = max(0.8, 0.35 * thermal_diff_len / dx);
precomp_threshold = 0.58;
design_blur = imgaussfilt(double(imag_target_raw), thermal_sigma_px);
imag_target_design = double(design_blur > precomp_threshold);
imag_target_design = imgaussfilt(imag_target_design, 0.45);
imag_target_design = imag_target_design / max(imag_target_design(:));

transport_dir = 'C:\Users\Zh89\Desktop\transport';
if ~exist(transport_dir, 'dir')
    mkdir(transport_dir);
end
export_path = fullfile(transport_dir, 'target_for_python.mat');
save(export_path, 'imag_target', 'imag_target_design', 'Nx', 'Ny', 'Lx', ...
    'lambda_water', 'z_target_dist', 'dx', 'dz', 'f0', 'c_water', ...
    'c_board', 'thermal_sigma_px', 'min_base_layers');

import_path = fullfile(transport_dir, 'dl_phase_init.mat');
if ~exist(import_path, 'file')
    error('dl_phase_init.mat not found. Run the Python phase-generation step after reading %s.', export_path);
end

%% 3. Load Python phase and run only Python-initialized IASA
load(import_path, 'optimal_initial_phase', 'optimal_phase_bias', ...
    'target_dose_design', 'line_target_mask', 'halo_target_mask');

pad_factor = 2;
Nx_pad = Nx * pad_factor;
Ny_pad = Ny * pad_factor;
Lx_pad = Lx * pad_factor;
dk_pad = 2 * pi / Lx_pad;
kx_pad = (-Nx_pad/2 : Nx_pad/2-1) * dk_pad;
[Kx_pad, Ky_pad] = meshgrid(kx_pad, kx_pad);
k_water = 2 * pi / lambda_water;
Kz_sq = k_water^2 - Kx_pad.^2 - Ky_pad.^2;
propagating = (Kz_sq > 0);
Kz = zeros(size(Kz_sq));
Kz(propagating) = sqrt(Kz_sq(propagating));
H_forward = zeros(size(Kz_sq));
H_forward(propagating) = exp(1i * Kz(propagating) * z_target_dist);
H_backward = conj(H_forward);

target_pad = zeros(Nx_pad, Ny_pad);
target_amp_design = sqrt(max(target_dose_design, 0));
center_idx = Nx/2+1:Nx/2+Nx;
target_pad(center_idx, center_idx) = target_amp_design;
mask_line = false(Nx_pad, Ny_pad);
mask_halo = false(Nx_pad, Ny_pad);
mask_line(center_idx, center_idx) = line_target_mask > 0.5;
mask_halo(center_idx, center_idx) = halo_target_mask > 0.5;
mask_dark = ~(mask_line | mask_halo);

circle_mask_board = (X_grid.^2 + Y_grid.^2) <= (32e-3)^2;
k_board_val = 2 * pi * f0 / c_board;
k_water_val = 2 * pi * f0 / c_water;
k_diff = abs(k_water_val - k_board_val);
phase_step = k_diff * dz;
phase_bias_seed = 0;
if exist('optimal_phase_bias', 'var')
    phase_bias_seed = optimal_phase_bias;
end

[phase_projected_init, ~, phase_bias_seed] = project_phase_to_board( ...
    optimal_initial_phase, phase_step, min_base_layers, circle_mask_board, phase_bias_seed, true);
[holo_phase, net_num_board, phase_bias_python_iasa] = run_iasa_phase_refinement( ...
    phase_projected_init, phase_bias_seed, phase_step, min_base_layers, circle_mask_board, ...
    target_pad, mask_line, mask_halo, mask_dark, H_forward, H_backward, ...
    Nx, Nx_pad, Ny_pad, iasa_epoch, iasa_anchor_eta, phase_refine_mode);

asm_iasa_amp = compute_asm_focus_field(holo_phase, circle_mask_board, Nx, Ny, H_forward);
asm_iasa_norm = asm_iasa_amp / (max(asm_iasa_amp(:)) + eps);
target_norm = imag_target / (max(imag_target(:)) + eps);
asm_iasa_metrics = calc_image_metrics(asm_iasa_norm, target_norm);

%% 4. Direct-phase k-Wave validation in homogeneous water
fprintf('\n==================================================\n');
fprintf('Running Python + IASA direct-phase k-Wave validation.\n');
fprintf('This stage does not build the thickness board.\n');
fprintf('==================================================\n');

iasa_result = run_direct_phase_validation( ...
    holo_phase, circle_mask_board, imag_target, ...
    Nx, Ny, Nz, dx, dy, dz, Lz, z_target_dist, f0, c_water, density_water, 'Python + IASA');
kwave_iasa_metrics = calc_image_metrics(iasa_result.amp_norm, target_norm);

%% 5. Cure-model validation on Python + IASA focal pressure
target_mask = imag_target > 0.5;
roi_amp_median = median(iasa_result.amp(target_mask));
if roi_amp_median <= 0
    error('Invalid ROI pressure amplitude median. Cannot calibrate pressure.');
end

scan_records = zeros(numel(pressure_scan) * numel(exposure_scan), 9);
best = struct('IoU', -inf);
record_idx = 0;
for p_idx = 1:numel(pressure_scan)
    target_median_pressure = pressure_scan(p_idx);
    p_scaled = iasa_result.amp ./ roi_amp_median .* target_median_pressure;
    cavitation_model.mask = p_scaled > 0;
    cav = compute_cavitation_activity_map(p_scaled, cavitation_model);
    [dose_rate, dose_components] = compute_cavitation_dose_rate(cav.trigger, cav.growth, cure_model);
    thermal_dose = zeros(size(dose_rate));
    for e_idx = 1:numel(exposure_scan)
        exposure_time = exposure_scan(e_idx);
        cavitation_dose = dose_rate .* (exposure_time / cure_model.cavitation_dose_time);
        [cure_score, cured_mask, cure_components] = compute_cavitation_cure_score( ...
            cavitation_dose, thermal_dose, cav.penalty, cure_model);
        metrics = evaluate_cure_prediction(cure_score, target_mask, cure_model.threshold);

        record_idx = record_idx + 1;
        scan_records(record_idx, :) = [ ...
            target_median_pressure / 1e6, exposure_time, metrics.IoU, metrics.Dice, ...
            metrics.over_cure_ratio, metrics.under_cure_ratio, metrics.cured_coverage, ...
            max(p_scaled(:)) / 1e6, mean(cure_components.quality_risk(target_mask))];

        if metrics.IoU > best.IoU
            best.target_median_pressure = target_median_pressure;
            best.exposure_time = exposure_time;
            best.p_scaled = p_scaled;
            best.cavitation = cav;
            best.dose_rate = dose_rate;
            best.dose_components = dose_components;
            best.cavitation_dose = cavitation_dose;
            best.cure_score = cure_score;
            best.cured_mask = cured_mask;
            best.cure_components = cure_components;
            best.metrics = metrics;
            best.IoU = metrics.IoU;
        end
    end
end

%% 6. Visualization and export
out_dir = fullfile(fileparts(mfilename('fullpath')), 'IASAdebug0420_cure_outputs');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

fig1 = figure('Color', 'w', 'Position', [60, 60, 1700, 980]);
tiledlayout(3, 4, 'Padding', 'compact', 'TileSpacing', 'compact');

nexttile; imagesc(x * 1e3, y * 1e3, target_norm); axis image;
colormap(gca, gray); colorbar; title('Target pattern'); xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, holo_phase); axis image;
colormap(gca, hsv); colorbar; clim([0, 2*pi]); title('Python + IASA phase'); xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, iasa_result.amp_norm); axis image;
colormap(gca, turbo); colorbar; title(sprintf('k-Wave pressure norm\\nPCC %.4f | SSIM %.4f', kwave_iasa_metrics.pcc, kwave_iasa_metrics.ssim));
xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, best.p_scaled / 1e6); axis image;
colormap(gca, turbo); colorbar; title(sprintf('Scaled pressure MPa\\nROI median %.2f MPa', best.target_median_pressure / 1e6));
xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, best.cavitation.activity); axis image;
colormap(gca, hot); colorbar; title('Cavitation activity'); xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, best.dose_rate); axis image;
colormap(gca, hot); colorbar; title('Cavitation dose rate'); xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, best.cure_score); axis image;
colormap(gca, turbo); colorbar; title('Cure score = cavitation dose'); xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, best.cured_mask); axis image;
colormap(gca, [1 1 1; 0.1 0.1 0.3]); colorbar; title(sprintf('Predicted cure\\nIoU %.4f', best.metrics.IoU));
xlabel('x (mm)'); ylabel('y (mm)');

error_map = zeros(size(target_mask));
error_map(target_mask & best.cured_mask) = 1;
error_map(target_mask & ~best.cured_mask) = 2;
error_map(~target_mask & best.cured_mask) = 3;
nexttile; imagesc(x * 1e3, y * 1e3, error_map); axis image;
colormap(gca, [0.02 0.02 0.08; 0.1 0.7 0.2; 0.1 0.3 1.0; 1.0 0.25 0.1]); colorbar;
title('Cure map: hit / under / over'); xlabel('x (mm)'); ylabel('y (mm)');

nexttile; imagesc(x * 1e3, y * 1e3, best.cure_components.quality_risk); axis image;
colormap(gca, hot); colorbar; title('Quality risk'); xlabel('x (mm)'); ylabel('y (mm)');

nexttile;
plot(x * 1e3, target_norm(round(end/2), :), 'k-', 'LineWidth', 2); hold on;
plot(x * 1e3, iasa_result.amp_norm(round(end/2), :), 'b-', 'LineWidth', 1.8);
plot(x * 1e3, best.cured_mask(round(end/2), :), 'r--', 'LineWidth', 1.4);
grid on; xlabel('x (mm)'); ylabel('Normalized value');
title('Centerline target / pressure / cure'); legend('Target', 'Pressure', 'Cure', 'Location', 'best');

nexttile;
scatter(scan_records(:, 1), scan_records(:, 2), 20, scan_records(:, 3), 'filled');
grid on; colorbar; xlabel('ROI median pressure (MPa)'); ylabel('Exposure (s)');
title('Cure scan IoU');

exportgraphics(fig1, fullfile(out_dir, 'python_iasa_cure_validation_overview.png'), 'Resolution', 300);

save(fullfile(out_dir, 'python_iasa_cure_validation.mat'), ...
    'imag_target', 'imag_target_design', 'holo_phase', 'net_num_board', ...
    'phase_step', 'phase_bias_python_iasa', 'iasa_result', 'asm_iasa_metrics', ...
    'kwave_iasa_metrics', 'scan_records', 'best', 'cavitation_model', ...
    'cure_model', 'dx', 'dy', 'dz', 'f0', 'z_target_dist', '-v7.3');

%% 7. Summary
fprintf('\n==================================================\n');
fprintf('Python + IASA acoustic field\n');
fprintf('ASM PCC/SSIM/NMSE/EE: %.4f / %.4f / %.4f / %.2f%%\n', ...
    asm_iasa_metrics.pcc, asm_iasa_metrics.ssim, asm_iasa_metrics.nmse, asm_iasa_metrics.ee * 100);
fprintf('k-Wave PCC/SSIM/NMSE/EE: %.4f / %.4f / %.4f / %.2f%%\n', ...
    kwave_iasa_metrics.pcc, kwave_iasa_metrics.ssim, kwave_iasa_metrics.nmse, kwave_iasa_metrics.ee * 100);
fprintf('--------------------------------------------------\n');
fprintf('Cure-model validation on k-Wave Python + IASA field\n');
fprintf('Best ROI median pressure: %.2f MPa\n', best.target_median_pressure / 1e6);
fprintf('Best exposure: %.2f s\n', best.exposure_time);
fprintf('Cure threshold: %.2f fixed cavitation-dose criterion\n', cure_model.threshold);
fprintf('Cavitation dose peak/ROI mean: %.4f / %.4f\n', ...
    max(best.cavitation_dose(:)), mean(best.cavitation_dose(target_mask)));
fprintf('Quality risk ROI/peak: %.4f / %.4f\n', ...
    mean(best.cure_components.quality_risk(target_mask)), max(best.cure_components.quality_risk(:)));
fprintf('Coverage/Over/Under: %.1f%% / %.1f%% / %.1f%%\n', ...
    best.metrics.cured_coverage * 100, best.metrics.over_cure_ratio * 100, best.metrics.under_cure_ratio * 100);
fprintf('IoU/Dice: %.4f / %.4f\n', best.metrics.IoU, best.metrics.Dice);
fprintf('Figures and data saved to: %s\n', out_dir);
fprintf('==================================================\n');

%% Local helpers
function [holo_phase, net_num_board, phase_bias_seed] = run_iasa_phase_refinement( ...
    init_phase, phase_bias_seed, phase_step, min_base_layers, circle_mask_board, ...
    target_pad, mask_line, mask_halo, mask_dark, H_forward, H_backward, ...
    Nx, Nx_pad, Ny_pad, iasa_epoch, iasa_anchor_eta, phase_refine_mode)

center_idx = Nx/2+1:Nx/2+Nx;
board_phase_pad = zeros(Nx_pad, Ny_pad);
board_phase_pad(center_idx, center_idx) = exp(1i * init_phase);
phase_anchor = init_phase;
weight_pad = 0.05 + target_pad * 1.95;

if strcmpi(phase_refine_mode, 'python_only')
    epoch = 0;
else
    epoch = iasa_epoch;
end

[~, net_num_board, phase_bias_seed] = project_phase_to_board( ...
    init_phase, phase_step, min_base_layers, circle_mask_board, phase_bias_seed, true);

for i = 1:epoch
    U_source = zeros(Nx_pad, Ny_pad);
    center_phase = angle(board_phase_pad(center_idx, center_idx));
    center_source = exp(1i * center_phase);
    center_source(~circle_mask_board) = 0;
    U_source(center_idx, center_idx) = center_source;

    A_source = fftshift(fft2(ifftshift(U_source)));
    A_target = A_source .* H_forward;
    U_target = fftshift(ifft2(ifftshift(A_target)));

    rec_amp = abs(U_target);
    peak_val = max(rec_amp(mask_line));
    if peak_val == 0
        peak_val = max(rec_amp(:));
    end
    rec_amp_norm = rec_amp / peak_val;

    if i > 5
        beta = 0.6;
        correction = (target_pad(mask_line) ./ (rec_amp_norm(mask_line) + 1e-6)) .^ beta;
        weight_pad(mask_line) = weight_pad(mask_line) .* correction;
        weight_pad(weight_pad > 10) = 10;
        weight_pad(mask_halo) = 0.05;
        weight_pad(mask_dark) = 0;
    end

    U_target_constrained = weight_pad .* exp(1i * angle(U_target));
    A_target_cons = fftshift(fft2(ifftshift(U_target_constrained)));
    A_source_cons = A_target_cons .* H_backward;
    U_source_new = fftshift(ifft2(ifftshift(A_source_cons)));
    source_phase_candidate = angle(U_source_new(center_idx, center_idx));
    [phase_projected_iter_raw, ~, phase_bias_seed] = project_phase_to_board( ...
        source_phase_candidate, phase_step, min_base_layers, circle_mask_board, phase_bias_seed, true);

    if iasa_anchor_eta < 1
        blended_complex = (1 - iasa_anchor_eta) .* exp(1i * phase_anchor) + ...
            iasa_anchor_eta .* exp(1i * phase_projected_iter_raw);
        blended_phase = angle(blended_complex);
    else
        blended_phase = phase_projected_iter_raw;
    end

    [phase_projected_iter, net_num_board, phase_bias_seed] = project_phase_to_board( ...
        blended_phase, phase_step, min_base_layers, circle_mask_board, phase_bias_seed, true);

    board_phase_pad = zeros(Nx_pad, Ny_pad);
    board_phase_pad(center_idx, center_idx) = exp(1i * phase_projected_iter);
end

holo_phase = mod(net_num_board * phase_step, 2 * pi);
holo_phase(~circle_mask_board) = 0;
end

function result = run_direct_phase_validation(phase_map, source_mask, target_img, ...
    Nx, Ny, Nz, dx, dy, dz, Lz, z_target_dist, f0, c_water, density_water, run_label)

fprintf('\n[%s] building direct-phase source...\n', run_label);
kgrid = kWaveGrid(Nx, dx, Ny, dy, Nz, dz);
medium.sound_speed = c_water * ones(Nx, Ny, Nz, 'single');
medium.density = density_water * ones(Nx, Ny, Nz, 'single');

pml_size = 10;
source_z_idx = pml_size + 5;
target_plane_idx = source_z_idx + round(z_target_dist / dz);
if target_plane_idx >= Nz - pml_size
    error('Target plane index exceeds available domain. Increase Nz before running validation.');
end

cfl = 0.3;
t_end = (Lz * 1.5) / c_water;
kgrid.makeTime(c_water, cfl, t_end);

source.p_mask = zeros(Nx, Ny, Nz, 'single');
source.p_mask(:, :, source_z_idx) = single(source_mask);
phase_vec = phase_map(source_mask);
t_vec = reshape(kgrid.t_array, 1, []);
omega = 2 * pi * f0;
source_sig = sin(omega .* t_vec - phase_vec);
ramp_pts = min(kgrid.Nt, max(1, round(2 / f0 / kgrid.dt)));
window = [linspace(0, 1, ramp_pts), ones(1, kgrid.Nt - ramp_pts)];
source.p = single(source_sig .* window);
source.p_mode = 'dirichlet';

sensor.mask = zeros(Nx, Ny, Nz, 'single');
sensor.mask(:, :, target_plane_idx) = 1;
sensor.record = {'p'};
sensor.record_start_index = max(1, kgrid.Nt - round(3 / f0 / kgrid.dt));

input_args = { ...
    'PMLInside', true, ...
    'PMLSize', pml_size, ...
    'PlotPML', false, ...
    'PlotSim', false, ...
    'DataCast', 'gpuArray-single' ...
    };
try
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
catch
    fprintf('[%s] GPU path failed, falling back to CPU.\n', run_label);
    input_args = input_args(1:end-2);
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
end
p_raw = gather(sensor_data.p);
time_idx = sensor.record_start_index:kgrid.Nt;
t_record = kgrid.t_array(time_idx);
demod_ref = exp(-1i * 2 * pi * f0 * t_record(:));
p_complex = p_raw * demod_ref;
p_amp = reshape(abs(p_complex), Nx, Ny);
p_phase = reshape(angle(p_complex), Nx, Ny);

amp_norm = p_amp / (max(p_amp(:)) + eps);
target_norm = target_img / (max(target_img(:)) + eps);

result.amp = p_amp;
result.amp_norm = amp_norm;
result.phase = p_phase;
result.target_norm = target_norm;
result.source_z_idx = source_z_idx;
result.target_plane_idx = target_plane_idx;
end

function metrics = calc_image_metrics(pred_img, target_img)
pred_norm = pred_img / (max(pred_img(:)) + eps);
target_norm = target_img / (max(target_img(:)) + eps);
metrics.pcc = corr2(pred_norm, target_norm);
metrics.ssim = ssim(double(pred_norm), double(target_norm));
metrics.nmse = sum((pred_norm(:) - target_norm(:)).^2) / sum(target_norm(:).^2);
target_mask = target_norm > 0.5;
metrics.ee = sum(pred_norm(target_mask)) / (sum(pred_norm(:)) + eps);
try
    reset(gpuDevice);
catch
end
end
