clear; close all; clc;
try
    reset(gpuDevice);
catch
end

addpath(pwd);
addpath('F:\MATLAB\code\HDSP\HDSP\HDSP0420');
rng(9426);

%% 1. Parameters
Nx = 512;
Ny = Nx;
Lx = 65e-3;
Ly = Lx;
z_target_dist = 16e-3;
f0 = 4.5e6;
c_water = 1480;
c_board = 2430;
density_water = 997;
density_board = 1100;
alpha_coeff_water = 0.002;
alpha_power_water = 1.5;
alpha_coeff_board = 1.5;
c_pdms = 1070;
density_pdms = 965;
alpha_coeff_pdms = 5.0;
pdms_thickness = 7e-3;
focus_scan_radius = 6e-3;
lambda_water = c_water / f0;
phase_refine_mode = 'python_iasa';
iasa_epoch = 150;
iasa_anchor_eta = 1.0;
min_base_layers = 2;
target_pressure_mpa = 2.05;
exposure_time = 0.06;
exit_probe_offsets_voxels = [0, 2, 4, 8, 12, 16, 24, 32];
exit_phase_amp_threshold_ratio = 0.10;
asm_focus_scan_step_voxels = 2;
run_repaired_full_simulation = strcmpi(getenv('RUN_REPAIRED_FULL_KWAVE'), '1');

dx = Lx / Nx;
dy = dx;
dz = dx;
asm_focus_scan_offsets_voxels = -round(focus_scan_radius / dz):asm_focus_scan_step_voxels:round(focus_scan_radius / dz);
asm_focus_scan_offsets_voxels = unique(sort([asm_focus_scan_offsets_voxels, 0]));
asm_focus_scan_distances = z_target_dist + asm_focus_scan_offsets_voxels * dz;
asm_focus_scan_distances = asm_focus_scan_distances(asm_focus_scan_distances > 0);
x = (-Nx/2 : Nx/2-1) * dx;
y = x;
[Y_grid, X_grid] = meshgrid(y, x);

fprintf('==================================================\n');
fprintf('Phase-board exit repair validation\n');
fprintf('Grid dx = dy = dz = %.4f mm | PPW = %.2f\n', dx * 1e3, lambda_water / dx);
fprintf('ASM focus scan: %.2f to %.2f mm, %d planes\n', ...
    min(asm_focus_scan_distances) * 1e3, max(asm_focus_scan_distances) * 1e3, numel(asm_focus_scan_distances));
fprintf('==================================================\n');

%% 2. Target pattern and Python transport
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
target_norm = imag_target / (max(imag_target(:)) + eps);
target_mask = target_norm > 0.5;

transport_dir = 'C:\Users\Zh89\Desktop\transport';
if ~exist(transport_dir, 'dir')
    mkdir(transport_dir);
end
export_path = fullfile(transport_dir, 'target_for_python.mat');
save(export_path, 'imag_target', 'imag_target_design', 'Nx', 'Ny', 'Lx', ...
    'lambda_water', 'z_target_dist', 'dx', 'dz', 'f0', 'c_water', ...
    'c_board', 'thermal_sigma_px', 'min_base_layers');

fprintf('\nTarget exported to: %s\n', export_path);
fprintf('Run the Python initial-phase script, then press any key.\n\n');
pause;

import_path = fullfile(transport_dir, 'dl_phase_init.mat');
if ~exist(import_path, 'file')
    error('dl_phase_init.mat not found. Run the Python phase-generation step first.');
end
load(import_path, 'optimal_initial_phase', 'optimal_phase_bias', 'target_dose_design', ...
    'line_target_mask', 'halo_target_mask');

%% 3. IASA phase refinement and discrete board construction
pad_factor = 2;
Nx_pad = Nx * pad_factor;
Ny_pad = Ny * pad_factor;
Lx_pad = Lx * pad_factor;
dk_pad = 2 * pi / Lx_pad;
kx_pad = (-Nx_pad/2 : Nx_pad/2-1) * dk_pad;
[Kx_pad, Ky_pad] = meshgrid(kx_pad, kx_pad);
k_water_wave = 2 * pi / lambda_water;
Kz_sq = k_water_wave^2 - Kx_pad.^2 - Ky_pad.^2;
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

thickness_map = net_num_board * dz;
asm_iasa_amp = compute_asm_focus_field(holo_phase, circle_mask_board, Nx, Ny, H_forward);
asm_iasa_norm = asm_iasa_amp / (max(asm_iasa_amp(:)) + eps);
asm_iasa_metrics = calc_image_metrics(asm_iasa_norm, target_norm);

%% 4. First short simulation: real board exit complex field
fprintf('\nRunning short board-exit simulation.\n');
exit_result = run_board_exit_simulation( ...
    net_num_board, circle_mask_board, Nx, Ny, dx, dy, dz, f0, ...
    c_water, c_board, density_water, density_board, ...
    alpha_coeff_water, alpha_power_water, alpha_coeff_board, exit_probe_offsets_voxels);

exit_phase_scan = analyze_exit_phase_planes( ...
    exit_result.p_exit_complex_stack, exit_result.z_probe_indices, exit_result.z_board_exit_idx, ...
    holo_phase, circle_mask_board, H_forward, Kz, propagating, asm_focus_scan_distances, center_idx, Nx_pad, Ny_pad, ...
    target_norm, dx, exit_phase_amp_threshold_ratio);
local_exit_diagnostic = analyze_local_exit_field( ...
    exit_result.local_exit_complex, exit_result.local_exit_compensated, holo_phase, circle_mask_board, ...
    H_forward, Kz, propagating, asm_focus_scan_distances, center_idx, Nx_pad, Ny_pad, ...
    target_norm, exit_phase_amp_threshold_ratio);

p_exit_complex = exit_phase_scan.best_repaired.p_exit_complex;
p_exit_amp = abs(p_exit_complex);
p_exit_amp_norm = p_exit_amp / (max(p_exit_amp(:)) + eps);
p_exit_phase = angle(p_exit_complex);
exit_vals = p_exit_amp(circle_mask_board);
exit_amp_cv = std(exit_vals(:)) / (mean(exit_vals(:)) + eps);
exit_amp_min_ratio = min(exit_vals(:)) / (max(exit_vals(:)) + eps);

actual_exit_asm_amp = propagate_exit_field_asm(p_exit_complex, H_forward, center_idx, Nx_pad, Ny_pad);
actual_exit_asm_norm = actual_exit_asm_amp / (max(actual_exit_asm_amp(:)) + eps);
actual_exit_asm_metrics = calc_image_metrics(actual_exit_asm_norm, target_norm);

theory_exit = make_idealized_exit_field(p_exit_complex, circle_mask_board, 1.0);
theory_exit_asm_amp = propagate_exit_field_asm(theory_exit, H_forward, center_idx, Nx_pad, Ny_pad);
theory_exit_asm_norm = theory_exit_asm_amp / (max(theory_exit_asm_amp(:)) + eps);
theory_exit_asm_metrics = calc_image_metrics(theory_exit_asm_norm, target_norm);

%% 5. Second full simulation: ideal amplitude + measured exit phase
if run_repaired_full_simulation
    try
        reset(gpuDevice);
    catch
    end
    fprintf('\nRunning repaired-exit full propagation simulation.\n');
    full_result = run_repaired_exit_full_simulation( ...
        theory_exit, circle_mask_board, target_norm, target_mask, ...
        Nx, Ny, dx, dy, dz, z_target_dist, focus_scan_radius, ...
        f0, c_water, density_water, alpha_coeff_water, alpha_power_water, ...
        c_pdms, density_pdms, alpha_coeff_pdms, pdms_thickness);

    p_focal = full_result.p_focal;
    p_focal_norm = p_focal / (max(p_focal(:)) + eps);
    kwave_metrics = calc_image_metrics(p_focal_norm, target_norm);
    cure_result = run_cavitation_cure_prediction(p_focal, target_mask, target_pressure_mpa, exposure_time);
else
    fprintf('\nSkipping repaired full k-Wave run. Use exit-phase scan before enabling it.\n');
    full_result = struct('best_z_mm', NaN);
    p_focal = NaN(size(target_norm));
    p_focal_norm = p_focal;
    kwave_metrics = empty_image_metrics();
    cure_result = empty_cure_result(size(target_norm));
end

%% 6. Export artifacts and report
out_dir = fullfile(fileparts(mfilename('fullpath')), 'phase_board_exit_repair_outputs');
if ~exist(out_dir, 'dir')
    mkdir(out_dir);
end

metrics = struct();
metrics.phase_bias_python_iasa = phase_bias_python_iasa;
metrics.phase_step = phase_step;
metrics.asm_iasa = asm_iasa_metrics;
metrics.actual_exit_asm = actual_exit_asm_metrics;
metrics.repaired_exit_asm = theory_exit_asm_metrics;
metrics.repaired_kwave = kwave_metrics;
metrics.exit_amp_cv = exit_amp_cv;
metrics.exit_amp_min_ratio = exit_amp_min_ratio;
metrics.exit_phase_scan = exit_phase_scan.records;
metrics.exit_phase_best_repaired = exit_phase_scan.best_repaired.summary;
metrics.exit_phase_best_phase = exit_phase_scan.best_phase.summary;
metrics.exit_phase_focus_scan_distances_mm = asm_focus_scan_distances * 1e3;
metrics.local_exit = local_exit_diagnostic.metrics;
metrics.best_z_mm = full_result.best_z_mm;
metrics.cure = cure_result.metrics;
save(fullfile(out_dir, 'phase_board_exit_repair_results.mat'), ...
    'metrics', 'thickness_map', 'net_num_board', 'holo_phase', ...
    'p_exit_complex', 'theory_exit', 'exit_phase_scan', 'local_exit_diagnostic', 'p_focal', 'p_focal_norm', ...
    'target_norm', 'target_mask', 'cure_result', 'x', 'y', '-v7.3');

fig = figure('Color', 'w', 'Position', [60, 60, 1600, 920]);
tiledlayout(3, 4, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile; imagesc(x * 1e3, y * 1e3, target_norm); axis image; colormap(gca, gray); colorbar; title('Target');
nexttile; imagesc(x * 1e3, y * 1e3, holo_phase); axis image; colormap(gca, hsv); colorbar; clim([0, 2*pi]); title('Discrete phase');
nexttile; imagesc(x * 1e3, y * 1e3, thickness_map * 1e3); axis image; colormap(gca, parula); colorbar; title('Board thickness (mm)');
nexttile; imagesc(x * 1e3, y * 1e3, asm_iasa_norm); axis image; colormap(gca, turbo); colorbar; title(sprintf('Design ASM PCC %.4f', asm_iasa_metrics.pcc));
nexttile; imagesc(x * 1e3, y * 1e3, p_exit_amp_norm); axis image; colormap(gca, turbo); colorbar; title(sprintf('Actual exit amp CV %.4f', exit_amp_cv));
nexttile; imagesc(x * 1e3, y * 1e3, p_exit_phase); axis image; colormap(gca, hsv); colorbar; title('Actual exit phase');
nexttile; imagesc(x * 1e3, y * 1e3, actual_exit_asm_norm); axis image; colormap(gca, turbo); colorbar; title(sprintf('Actual exit ASM PCC %.4f', actual_exit_asm_metrics.pcc));
nexttile; imagesc(x * 1e3, y * 1e3, theory_exit_asm_norm); axis image; colormap(gca, turbo); colorbar; title(sprintf('Repaired exit ASM PCC %.4f', theory_exit_asm_metrics.pcc));
nexttile; imagesc(x * 1e3, y * 1e3, p_focal_norm); axis image; colormap(gca, turbo); colorbar; title(sprintf('Repaired k-Wave PCC %.4f', kwave_metrics.pcc));
nexttile; imagesc(x * 1e3, y * 1e3, cure_result.cured_mask); axis image; colormap(gca, [1 1 1; 0.1 0.1 0.3]); title(sprintf('Cure IoU %.4f', cure_result.metrics.IoU));
nexttile; imagesc(x * 1e3, y * 1e3, cure_result.cure_score); axis image; colormap(gca, turbo); colorbar; title('Cavitation cure score');
nexttile; plot(x * 1e3, target_norm(round(end/2), :), 'k--', 'LineWidth', 2); hold on;
plot(x * 1e3, p_focal_norm(round(end/2), :), 'r-', 'LineWidth', 1.5); grid on;
title('Centerline'); xlabel('x (mm)'); ylabel('norm amp'); legend('Target', 'Repaired k-Wave');
exportgraphics(fig, fullfile(out_dir, 'phase_board_exit_repair_overview.png'), 'Resolution', 300);

local_raw_repaired = make_idealized_exit_field(local_exit_diagnostic.raw_complex, circle_mask_board, 1.0);
local_comp_repaired = make_idealized_exit_field(local_exit_diagnostic.compensated_complex, circle_mask_board, 1.0);
local_raw_asm = propagate_exit_field_asm(local_raw_repaired, H_forward, center_idx, Nx_pad, Ny_pad);
local_raw_asm_norm = local_raw_asm / (max(local_raw_asm(:)) + eps);
local_comp_asm = propagate_exit_field_asm(local_comp_repaired, H_forward, center_idx, Nx_pad, Ny_pad);
local_comp_asm_norm = local_comp_asm / (max(local_comp_asm(:)) + eps);
fig_local = figure('Color', 'w', 'Position', [80, 80, 1450, 760]);
tiledlayout(2, 3, 'Padding', 'compact', 'TileSpacing', 'compact');
nexttile; imagesc(x * 1e3, y * 1e3, abs(local_exit_diagnostic.raw_complex)); axis image; colormap(gca, turbo); colorbar; title('Local exit amp');
nexttile; imagesc(x * 1e3, y * 1e3, angle(local_exit_diagnostic.raw_complex)); axis image; colormap(gca, hsv); colorbar; clim([-pi, pi]); title('Local exit phase raw');
nexttile; imagesc(x * 1e3, y * 1e3, angle(local_exit_diagnostic.compensated_complex)); axis image; colormap(gca, hsv); colorbar; clim([-pi, pi]); title('Local exit phase compensated');
nexttile; imagesc(x * 1e3, y * 1e3, holo_phase); axis image; colormap(gca, hsv); colorbar; clim([0, 2*pi]); title('Theoretical board phase');
nexttile; imagesc(x * 1e3, y * 1e3, local_raw_asm_norm); axis image; colormap(gca, turbo); colorbar; title(sprintf('Raw local repaired PCC %.4f', local_exit_diagnostic.metrics.raw.repaired_fixed_pcc));
nexttile; imagesc(x * 1e3, y * 1e3, local_comp_asm_norm); axis image; colormap(gca, turbo); colorbar; title(sprintf('Comp local repaired PCC %.4f', local_exit_diagnostic.metrics.compensated.repaired_fixed_pcc));
exportgraphics(fig_local, fullfile(out_dir, 'local_exit_diagnostic.png'), 'Resolution', 300);

fig_scan = figure('Color', 'w', 'Position', [90, 90, 1250, 720]);
tiledlayout(2, 2, 'Padding', 'compact', 'TileSpacing', 'compact');
offset_mm = [exit_phase_scan.records.offset_mm];
nexttile;
plot(offset_mm, [exit_phase_scan.records.same_coherence], 'o-', 'LineWidth', 1.5); hold on;
plot(offset_mm, [exit_phase_scan.records.opposite_coherence], 's-', 'LineWidth', 1.5);
grid on; xlabel('Probe offset after max board exit (mm)'); ylabel('phase coherence');
legend('phi - holo', 'phi + holo', 'Location', 'best'); title('Exit phase coherence');
nexttile;
plot(offset_mm, [exit_phase_scan.records.same_rms_rad], 'o-', 'LineWidth', 1.5); hold on;
plot(offset_mm, [exit_phase_scan.records.opposite_rms_rad], 's-', 'LineWidth', 1.5);
grid on; xlabel('Probe offset after max board exit (mm)'); ylabel('RMS after global offset (rad)');
legend('phi - holo', 'phi + holo', 'Location', 'best'); title('Exit phase RMS');
nexttile;
plot(offset_mm, [exit_phase_scan.records.actual_asm_pcc], 'o--', 'LineWidth', 1.0); hold on;
plot(offset_mm, [exit_phase_scan.records.repaired_asm_pcc], 's--', 'LineWidth', 1.0);
plot(offset_mm, [exit_phase_scan.records.actual_asm_best_pcc], 'o-', 'LineWidth', 1.8);
plot(offset_mm, [exit_phase_scan.records.repaired_asm_best_pcc], 's-', 'LineWidth', 1.8);
grid on; xlabel('Probe offset after max board exit (mm)'); ylabel('PCC to target');
legend('actual fixed z', 'repaired fixed z', 'actual best z', 'repaired best z', 'Location', 'best');
title('ASM target match');
nexttile;
plot(offset_mm, [exit_phase_scan.records.actual_asm_best_z_mm], 'o-', 'LineWidth', 1.5); hold on;
plot(offset_mm, [exit_phase_scan.records.repaired_asm_best_z_mm], 's-', 'LineWidth', 1.5);
yline(z_target_dist * 1e3, 'k--', 'Design z');
grid on; xlabel('Probe offset after max board exit (mm)'); ylabel('best target z (mm)');
legend('actual complex exit', 'ideal amp + exit phase', 'Location', 'best'); title('ASM best target plane');
exportgraphics(fig_scan, fullfile(out_dir, 'exit_phase_probe_scan.png'), 'Resolution', 300);

fprintf('\n==================================================\n');
fprintf('Exit amplitude repair validation summary\n');
fprintf('Design ASM PCC/SSIM/NMSE/EE: %.4f / %.4f / %.4f / %.2f%%\n', ...
    asm_iasa_metrics.pcc, asm_iasa_metrics.ssim, asm_iasa_metrics.nmse, asm_iasa_metrics.ee * 100);
fprintf('Actual exit ASM PCC/SSIM/NMSE/EE: %.4f / %.4f / %.4f / %.2f%%\n', ...
    actual_exit_asm_metrics.pcc, actual_exit_asm_metrics.ssim, actual_exit_asm_metrics.nmse, actual_exit_asm_metrics.ee * 100);
fprintf('Repaired exit ASM PCC/SSIM/NMSE/EE: %.4f / %.4f / %.4f / %.2f%%\n', ...
    theory_exit_asm_metrics.pcc, theory_exit_asm_metrics.ssim, theory_exit_asm_metrics.nmse, theory_exit_asm_metrics.ee * 100);
fprintf('Repaired k-Wave PCC/SSIM/NMSE/EE: %.4f / %.4f / %.4f / %.2f%%\n', ...
    kwave_metrics.pcc, kwave_metrics.ssim, kwave_metrics.nmse, kwave_metrics.ee * 100);
fprintf('Exit amp CV/min-max: %.4f / %.4f\n', exit_amp_cv, exit_amp_min_ratio);
fprintf('Best repaired ASM probe offset: %.2f mm | fixed PCC %.4f | scan PCC %.4f at %.2f mm | phase best=%s | coh %.4f | RMS %.4f rad\n', ...
    exit_phase_scan.best_repaired.summary.offset_mm, ...
    exit_phase_scan.best_repaired.summary.repaired_asm_pcc, ...
    exit_phase_scan.best_repaired.summary.repaired_asm_best_pcc, ...
    exit_phase_scan.best_repaired.summary.repaired_asm_best_z_mm, ...
    exit_phase_scan.best_repaired.summary.best_sign, ...
    exit_phase_scan.best_repaired.summary.best_coherence, ...
    exit_phase_scan.best_repaired.summary.best_rms_rad);
fprintf('Best phase-match probe offset: %.2f mm | fixed repaired PCC %.4f | scan PCC %.4f at %.2f mm | phase best=%s | coh %.4f | RMS %.4f rad\n', ...
    exit_phase_scan.best_phase.summary.offset_mm, ...
    exit_phase_scan.best_phase.summary.repaired_asm_pcc, ...
    exit_phase_scan.best_phase.summary.repaired_asm_best_pcc, ...
    exit_phase_scan.best_phase.summary.repaired_asm_best_z_mm, ...
    exit_phase_scan.best_phase.summary.best_sign, ...
    exit_phase_scan.best_phase.summary.best_coherence, ...
    exit_phase_scan.best_phase.summary.best_rms_rad);
fprintf('Local exit raw: repaired scan PCC %.4f at %.2f mm | phase best=%s | coh %.4f | RMS %.4f rad\n', ...
    local_exit_diagnostic.metrics.raw.repaired_best_pcc, ...
    local_exit_diagnostic.metrics.raw.repaired_best_z_mm, ...
    local_exit_diagnostic.metrics.raw.best_sign, ...
    local_exit_diagnostic.metrics.raw.best_coherence, ...
    local_exit_diagnostic.metrics.raw.best_rms_rad);
fprintf('Local exit compensated: repaired scan PCC %.4f at %.2f mm | phase best=%s | coh %.4f | RMS %.4f rad\n', ...
    local_exit_diagnostic.metrics.compensated.repaired_best_pcc, ...
    local_exit_diagnostic.metrics.compensated.repaired_best_z_mm, ...
    local_exit_diagnostic.metrics.compensated.best_sign, ...
    local_exit_diagnostic.metrics.compensated.best_coherence, ...
    local_exit_diagnostic.metrics.compensated.best_rms_rad);
fprintf('Repaired best z from exit: %.2f mm\n', full_result.best_z_mm);
fprintf('Cure IoU/Dice/over/under/coverage: %.4f / %.4f / %.2f%% / %.2f%% / %.2f%%\n', ...
    cure_result.metrics.IoU, cure_result.metrics.Dice, ...
    cure_result.metrics.over_cure_ratio * 100, cure_result.metrics.under_cure_ratio * 100, ...
    cure_result.metrics.cured_coverage * 100);
fprintf('Outputs saved to: %s\n', out_dir);
fprintf('==================================================\n');

try
    reset(gpuDevice);
catch
end

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
    U_target = fftshift(ifft2(ifftshift(A_source .* H_forward)));

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
    U_source_new = fftshift(ifft2(ifftshift(A_target_cons .* H_backward)));
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

function result = run_board_exit_simulation(net_num_board, aperture_mask, Nx, Ny, dx, dy, dz, f0, ...
    c_water, c_board, density_water, density_board, alpha_coeff_water, alpha_power_water, alpha_coeff_board, probe_offsets_voxels)

pml_size = 10;
source_z_idx = pml_size + 5;
z_board_start_idx = source_z_idx + 1;
max_layers = max(net_num_board(:));
z_board_exit_idx = z_board_start_idx + max_layers;
z_probe_indices = z_board_exit_idx + probe_offsets_voxels;
local_exit_z_indices = z_board_start_idx + net_num_board;
diagnostic_z_indices = unique([z_probe_indices(:); local_exit_z_indices(aperture_mask)]);
Nz_short = max(diagnostic_z_indices) + pml_size + 12;

kgrid = kWaveGrid(Nx, dx, Ny, dy, Nz_short, dz);
medium.sound_speed = c_water * ones(Nx, Ny, Nz_short, 'single');
medium.density = density_water * ones(Nx, Ny, Nz_short, 'single');
medium.alpha_coeff = alpha_coeff_water * ones(Nx, Ny, Nz_short, 'single');
medium.alpha_power = alpha_power_water;

for row = 1:Nx
    for col = 1:Ny
        n_layers = net_num_board(row, col);
        if n_layers > 0
            z_end = z_board_start_idx + n_layers - 1;
            medium.sound_speed(row, col, z_board_start_idx:z_end) = c_board;
            medium.density(row, col, z_board_start_idx:z_end) = density_board;
            medium.alpha_coeff(row, col, z_board_start_idx:z_end) = alpha_coeff_board;
        end
    end
end

cfl = 0.3;
t_end = (Nz_short * dz * 1.8) / c_water;
kgrid.makeTime(medium.sound_speed, cfl, t_end);

source.p_mask = zeros(Nx, Ny, Nz_short, 'single');
source.p_mask(:, :, source_z_idx) = single(aperture_mask);
t_vec = reshape(kgrid.t_array, 1, []);
source_sig = sin(2 * pi * f0 .* t_vec);
ramp_pts = min(kgrid.Nt, max(1, round(2 / f0 / kgrid.dt)));
source.p = single(source_sig .* [linspace(0, 1, ramp_pts), ones(1, kgrid.Nt - ramp_pts)]);
source.p_mode = 'dirichlet';

sensor.mask = zeros(Nx, Ny, Nz_short, 'single');
for idx = 1:numel(diagnostic_z_indices)
    sensor.mask(:, :, diagnostic_z_indices(idx)) = 1;
end
sensor.record = {'p'};
sensor.record_start_index = max(1, kgrid.Nt - round(3 / f0 / kgrid.dt));

input_args = {'PMLInside', true, 'PMLSize', pml_size, 'PlotPML', false, 'PlotSim', false, 'DataCast', 'gpuArray-single'};
try
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
catch
    fprintf('Exit simulation GPU path failed, falling back to CPU.\n');
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{1:end-2});
end

p_time = gather(sensor_data.p);
t_record = kgrid.t_array(sensor.record_start_index:end);
demod = exp(-1i * 2 * pi * f0 * t_record(:));
p_exit_complex_vec = (p_time * demod) ./ numel(t_record);
p_exit_volume = complex(zeros(Nx, Ny, Nz_short));
p_exit_volume(sensor.mask ~= 0) = p_exit_complex_vec;
local_exit_complex = extract_local_exit_field(p_exit_volume, local_exit_z_indices, aperture_mask);
common_plane_shift_voxels = z_board_exit_idx - local_exit_z_indices;
local_exit_compensated = local_exit_complex;
local_exit_compensated(aperture_mask) = local_exit_complex(aperture_mask) .* ...
    exp(1i * (2 * pi * f0 / c_water) .* common_plane_shift_voxels(aperture_mask) .* dz);

result = struct();
result.p_exit_complex_stack = p_exit_volume(:, :, z_probe_indices);
result.z_probe_indices = z_probe_indices;
result.local_exit_complex = local_exit_complex;
result.local_exit_compensated = local_exit_compensated;
result.local_exit_z_indices = local_exit_z_indices;
result.diagnostic_z_indices = diagnostic_z_indices;
result.z_board_exit_idx = z_board_exit_idx;
result.Nz_short = Nz_short;
end

function scan = analyze_exit_phase_planes(p_exit_complex_stack, z_probe_indices, z_board_exit_idx, ...
    holo_phase, aperture_mask, H_forward, Kz, propagating, asm_focus_scan_distances, ...
    center_idx, Nx_pad, Ny_pad, target_norm, dx, amp_threshold_ratio)

n_planes = size(p_exit_complex_stack, 3);
records = repmat(empty_exit_phase_record(), 1, n_planes);
best_repaired_idx = 1;
best_phase_idx = 1;
best_repaired_pcc = -inf;
best_phase_rms = inf;

for idx = 1:n_planes
    p_complex = p_exit_complex_stack(:, :, idx);
    phase_cmp = compare_phase_to_reference(p_complex, holo_phase, aperture_mask, amp_threshold_ratio);
    actual_asm = propagate_exit_field_asm(p_complex, H_forward, center_idx, Nx_pad, Ny_pad);
    actual_asm_norm = actual_asm / (max(actual_asm(:)) + eps);
    actual_metrics = calc_image_metrics(actual_asm_norm, target_norm);
    actual_focus_scan = scan_exit_field_asm_focus( ...
        p_complex, Kz, propagating, asm_focus_scan_distances, center_idx, Nx_pad, Ny_pad, target_norm);

    repaired = make_idealized_exit_field(p_complex, aperture_mask, 1.0);
    repaired_asm = propagate_exit_field_asm(repaired, H_forward, center_idx, Nx_pad, Ny_pad);
    repaired_asm_norm = repaired_asm / (max(repaired_asm(:)) + eps);
    repaired_metrics = calc_image_metrics(repaired_asm_norm, target_norm);
    repaired_focus_scan = scan_exit_field_asm_focus( ...
        repaired, Kz, propagating, asm_focus_scan_distances, center_idx, Nx_pad, Ny_pad, target_norm);

    exit_amp = abs(p_complex);
    exit_vals = exit_amp(aperture_mask);
    records(idx) = build_exit_phase_record( ...
        z_probe_indices(idx), z_board_exit_idx, dx, phase_cmp, actual_metrics, repaired_metrics, ...
        actual_focus_scan, repaired_focus_scan, exit_vals);

    if repaired_focus_scan.best_metrics.pcc > best_repaired_pcc
        best_repaired_pcc = repaired_focus_scan.best_metrics.pcc;
        best_repaired_idx = idx;
    end
    if records(idx).best_rms_rad < best_phase_rms
        best_phase_rms = records(idx).best_rms_rad;
        best_phase_idx = idx;
    end
end

scan = struct();
scan.records = records;
scan.best_repaired = struct( ...
    'summary', records(best_repaired_idx), ...
    'p_exit_complex', p_exit_complex_stack(:, :, best_repaired_idx));
scan.best_phase = struct( ...
    'summary', records(best_phase_idx), ...
    'p_exit_complex', p_exit_complex_stack(:, :, best_phase_idx));
end

function diagnostic = analyze_local_exit_field(local_exit_raw, local_exit_compensated, holo_phase, aperture_mask, ...
    H_forward, Kz, propagating, asm_focus_scan_distances, center_idx, Nx_pad, Ny_pad, target_norm, amp_threshold_ratio)

raw = summarize_local_exit_case( ...
    local_exit_raw, holo_phase, aperture_mask, H_forward, Kz, propagating, ...
    asm_focus_scan_distances, center_idx, Nx_pad, Ny_pad, target_norm, amp_threshold_ratio);
compensated = summarize_local_exit_case( ...
    local_exit_compensated, holo_phase, aperture_mask, H_forward, Kz, propagating, ...
    asm_focus_scan_distances, center_idx, Nx_pad, Ny_pad, target_norm, amp_threshold_ratio);

diagnostic = struct();
diagnostic.raw_complex = local_exit_raw;
diagnostic.compensated_complex = local_exit_compensated;
diagnostic.metrics = struct('raw', raw, 'compensated', compensated);
end

function summary = summarize_local_exit_case(exit_complex, holo_phase, aperture_mask, H_forward, Kz, propagating, ...
    asm_focus_scan_distances, center_idx, Nx_pad, Ny_pad, target_norm, amp_threshold_ratio)

phase_cmp = compare_phase_to_reference(exit_complex, holo_phase, aperture_mask, amp_threshold_ratio);
repaired = make_idealized_exit_field(exit_complex, aperture_mask, 1.0);
fixed_asm = propagate_exit_field_asm(repaired, H_forward, center_idx, Nx_pad, Ny_pad);
fixed_asm = fixed_asm / (max(fixed_asm(:)) + eps);
fixed_metrics = calc_image_metrics(fixed_asm, target_norm);
focus_scan = scan_exit_field_asm_focus( ...
    repaired, Kz, propagating, asm_focus_scan_distances, center_idx, Nx_pad, Ny_pad, target_norm);
exit_amp = abs(exit_complex);
exit_vals = exit_amp(aperture_mask);

summary = struct();
summary.best_sign = phase_cmp.best_sign;
if phase_cmp.best_sign == "same"
    summary.best_coherence = phase_cmp.same_sign.coherence;
    summary.best_rms_rad = phase_cmp.same_sign.rms_rad;
else
    summary.best_coherence = phase_cmp.opposite_sign.coherence;
    summary.best_rms_rad = phase_cmp.opposite_sign.rms_rad;
end
summary.same_coherence = phase_cmp.same_sign.coherence;
summary.same_rms_rad = phase_cmp.same_sign.rms_rad;
summary.opposite_coherence = phase_cmp.opposite_sign.coherence;
summary.opposite_rms_rad = phase_cmp.opposite_sign.rms_rad;
summary.valid_pixels = phase_cmp.valid_pixels;
summary.valid_fraction = phase_cmp.valid_fraction;
summary.repaired_fixed_pcc = fixed_metrics.pcc;
summary.repaired_fixed_ssim = fixed_metrics.ssim;
summary.repaired_fixed_nmse = fixed_metrics.nmse;
summary.repaired_best_pcc = focus_scan.best_metrics.pcc;
summary.repaired_best_ssim = focus_scan.best_metrics.ssim;
summary.repaired_best_nmse = focus_scan.best_metrics.nmse;
summary.repaired_best_ee = focus_scan.best_metrics.ee;
summary.repaired_best_z_mm = focus_scan.best_z_mm;
summary.exit_amp_cv = std(exit_vals(:)) / (mean(exit_vals(:)) + eps);
summary.exit_amp_min_ratio = min(exit_vals(:)) / (max(exit_vals(:)) + eps);
end

function record = empty_exit_phase_record()
record = struct( ...
    'z_index', 0, ...
    'offset_voxels', 0, ...
    'offset_mm', 0, ...
    'same_coherence', 0, ...
    'same_rms_rad', 0, ...
    'opposite_coherence', 0, ...
    'opposite_rms_rad', 0, ...
    'best_sign', "", ...
    'best_coherence', 0, ...
    'best_rms_rad', 0, ...
    'valid_pixels', 0, ...
    'total_mask_pixels', 0, ...
    'valid_fraction', 0, ...
    'actual_asm_pcc', 0, ...
    'actual_asm_ssim', 0, ...
    'actual_asm_nmse', 0, ...
    'actual_asm_best_pcc', 0, ...
    'actual_asm_best_ssim', 0, ...
    'actual_asm_best_nmse', 0, ...
    'actual_asm_best_ee', 0, ...
    'actual_asm_best_z_mm', 0, ...
    'repaired_asm_pcc', 0, ...
    'repaired_asm_ssim', 0, ...
    'repaired_asm_nmse', 0, ...
    'repaired_asm_best_pcc', 0, ...
    'repaired_asm_best_ssim', 0, ...
    'repaired_asm_best_nmse', 0, ...
    'repaired_asm_best_ee', 0, ...
    'repaired_asm_best_z_mm', 0, ...
    'exit_amp_cv', 0, ...
    'exit_amp_min_ratio', 0);
end

function record = build_exit_phase_record(z_index, z_board_exit_idx, dx, phase_cmp, actual_metrics, repaired_metrics, ...
    actual_focus_scan, repaired_focus_scan, exit_vals)
record = empty_exit_phase_record();
record.z_index = z_index;
record.offset_voxels = z_index - z_board_exit_idx;
record.offset_mm = record.offset_voxels * dx * 1e3;
record.same_coherence = phase_cmp.same_sign.coherence;
record.same_rms_rad = phase_cmp.same_sign.rms_rad;
record.opposite_coherence = phase_cmp.opposite_sign.coherence;
record.opposite_rms_rad = phase_cmp.opposite_sign.rms_rad;
record.best_sign = phase_cmp.best_sign;
if phase_cmp.best_sign == "same"
    record.best_coherence = record.same_coherence;
    record.best_rms_rad = record.same_rms_rad;
else
    record.best_coherence = record.opposite_coherence;
    record.best_rms_rad = record.opposite_rms_rad;
end
record.valid_pixels = phase_cmp.valid_pixels;
record.total_mask_pixels = phase_cmp.total_mask_pixels;
record.valid_fraction = phase_cmp.valid_fraction;
record.actual_asm_pcc = actual_metrics.pcc;
record.actual_asm_ssim = actual_metrics.ssim;
record.actual_asm_nmse = actual_metrics.nmse;
record.actual_asm_best_pcc = actual_focus_scan.best_metrics.pcc;
record.actual_asm_best_ssim = actual_focus_scan.best_metrics.ssim;
record.actual_asm_best_nmse = actual_focus_scan.best_metrics.nmse;
record.actual_asm_best_ee = actual_focus_scan.best_metrics.ee;
record.actual_asm_best_z_mm = actual_focus_scan.best_z_mm;
record.repaired_asm_pcc = repaired_metrics.pcc;
record.repaired_asm_ssim = repaired_metrics.ssim;
record.repaired_asm_nmse = repaired_metrics.nmse;
record.repaired_asm_best_pcc = repaired_focus_scan.best_metrics.pcc;
record.repaired_asm_best_ssim = repaired_focus_scan.best_metrics.ssim;
record.repaired_asm_best_nmse = repaired_focus_scan.best_metrics.nmse;
record.repaired_asm_best_ee = repaired_focus_scan.best_metrics.ee;
record.repaired_asm_best_z_mm = repaired_focus_scan.best_z_mm;
record.exit_amp_cv = std(exit_vals(:)) / (mean(exit_vals(:)) + eps);
record.exit_amp_min_ratio = min(exit_vals(:)) / (max(exit_vals(:)) + eps);
end

function result = run_repaired_exit_full_simulation(exit_complex, aperture_mask, target_norm, target_mask, ...
    Nx, Ny, dx, dy, dz, z_target_dist, focus_scan_radius, f0, ...
    c_water, density_water, alpha_coeff_water, alpha_power_water, ...
    c_pdms, density_pdms, alpha_coeff_pdms, pdms_thickness)

pml_size = 10;
source_z_idx = pml_size + 5;
target_plane_idx = source_z_idx + round(z_target_dist / dz);
scan_range_idx = round(focus_scan_radius / dz);
pdms_half_idx = round(pdms_thickness / (2 * dz));
pdms_z_start_idx = max(source_z_idx + 1, target_plane_idx - pdms_half_idx);
pdms_z_end_idx = pdms_z_start_idx + round(pdms_thickness / dz) - 1;
z_scan_start = target_plane_idx - scan_range_idx;
z_scan_end = target_plane_idx + scan_range_idx;
Nz_full = z_scan_end + pml_size + 12;

kgrid = kWaveGrid(Nx, dx, Ny, dy, Nz_full, dz);
medium.sound_speed = c_water * ones(Nx, Ny, Nz_full, 'single');
medium.density = density_water * ones(Nx, Ny, Nz_full, 'single');
medium.alpha_coeff = alpha_coeff_water * ones(Nx, Ny, Nz_full, 'single');
medium.alpha_power = alpha_power_water;
medium.sound_speed(:, :, pdms_z_start_idx:pdms_z_end_idx) = c_pdms;
medium.density(:, :, pdms_z_start_idx:pdms_z_end_idx) = density_pdms;
medium.alpha_coeff(:, :, pdms_z_start_idx:pdms_z_end_idx) = alpha_coeff_pdms;

cfl = 0.3;
t_end = (Nz_full * dz * 1.8) / c_water;
kgrid.makeTime(medium.sound_speed, cfl, t_end);

source.p_mask = zeros(Nx, Ny, Nz_full, 'single');
source.p_mask(:, :, source_z_idx) = single(aperture_mask);
exit_vec = exit_complex(aperture_mask);
amp_vec = abs(exit_vec);
phase_vec = angle(exit_vec);
if max(amp_vec) > 0
    amp_vec = amp_vec ./ max(amp_vec);
end
t_vec = reshape(kgrid.t_array, 1, []);
omega = 2 * pi * f0;
source_sig = amp_vec(:) .* sin(omega .* t_vec - phase_vec(:));
ramp_pts = min(kgrid.Nt, max(1, round(2 / f0 / kgrid.dt)));
window = [linspace(0, 1, ramp_pts), ones(1, kgrid.Nt - ramp_pts)];
source.p = single(source_sig .* window);
source.p_mode = 'dirichlet';

sensor.mask = zeros(Nx, Ny, Nz_full, 'single');
sensor.mask(:, :, z_scan_start:z_scan_end) = 1;
sensor.record = {'p_max'};
sensor.record_start_index = max(1, kgrid.Nt - round(3 / f0 / kgrid.dt));

input_args = {'PMLInside', true, 'PMLSize', pml_size, 'PlotPML', false, 'PlotSim', false, 'DataCast', 'gpuArray-single'};
try
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
catch
    fprintf('Repaired full simulation GPU path failed, falling back to CPU.\n');
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{1:end-2});
end

p_amp = gather(sensor_data.p_max);
p_field_3d = zeros(Nx, Ny, Nz_full);
p_field_3d(sensor.mask ~= 0) = p_amp;
scan_vol = p_field_3d(:, :, z_scan_start:z_scan_end);

best_corr = -inf;
best_slice_idx = 1;
for idx = 1:size(scan_vol, 3)
    slice_norm = scan_vol(:, :, idx);
    slice_norm = (slice_norm - min(slice_norm(:))) ./ (max(slice_norm(:)) - min(slice_norm(:)) + eps);
    current_corr = corr2(slice_norm, target_norm);
    if current_corr > best_corr
        best_corr = current_corr;
        best_slice_idx = idx;
    end
end

best_idx_global = z_scan_start + best_slice_idx - 1;
result = struct();
result.p_focal = scan_vol(:, :, best_slice_idx);
result.scan_vol = scan_vol;
result.best_corr = best_corr;
result.best_idx_global = best_idx_global;
result.best_z_mm = (best_idx_global - source_z_idx) * dz * 1e3;
result.target_mask = target_mask;
end

function cure_result = run_cavitation_cure_prediction(p_focal, target_mask, target_pressure_mpa, exposure_time)
cure_model = default_cure_model_params();
cavitation_model = default_cavitation_model_params();

roi_pressure = p_focal(target_mask);
scale_factor = (target_pressure_mpa * 1e6) / (median(roi_pressure(:)) + eps);
p_scaled = p_focal .* scale_factor;

cavitation_model.mask = true(size(p_scaled));
cav = compute_cavitation_activity_map(p_scaled, cavitation_model);
[dose_rate, dose_components] = compute_cavitation_dose_rate(cav.trigger, cav.growth, cure_model);
cavitation_dose = dose_rate .* (exposure_time / max(cure_model.cavitation_dose_time, eps));
thermal_dose = zeros(size(cavitation_dose));
[cure_score, cured_mask, components] = compute_cavitation_cure_score( ...
    cavitation_dose, thermal_dose, cav.penalty, cure_model);
metrics = evaluate_cure_prediction(cure_score, target_mask, cure_model.threshold);

cure_result = struct();
cure_result.p_scaled = p_scaled;
cure_result.cavitation = cav;
cure_result.dose_rate = dose_rate;
cure_result.dose_components = dose_components;
cure_result.cure_score = cure_score;
cure_result.cured_mask = cured_mask;
cure_result.components = components;
cure_result.metrics = metrics;
end

function params = default_cavitation_model_params()
params = struct();
params.pressure_on = 1.72e6;
params.pressure_full = 1.98e6;
params.pressure_stream = 2.35e6;
params.pressure_damage = 2.80e6;
params.saturation_shape = 4.0;
params.trigger_sharpness = 3.0;
params.streaming_penalty_strength = 0.75;
params.streaming_penalty_power = 1.5;
params.smooth_sigma_px = 0.8;
end

function params = default_cure_model_params()
params = struct();
params.threshold = 1.0;
params.cavitation_dose_time = 0.04;
params.dose_growth_floor = 0.65;
params.dose_trigger_weight = 0.35;
params.dose_cloud_radius_px = 2;
params.dose_cloud_floor = 0.45;
params.dose_cloud_power = 1.0;
params.dose_cloud_weight = 0.0;
params.dose_seed_floor = 0.85;
params.dose_seed_power = 1.0;
params.dose_fill_radius_px = 2;
params.dose_fill_weight = 0.0;
params.dose_fill_growth_ref = 0.20;
params.dose_fill_power = 1.0;
params.quality_risk_weight = 0.80;
end

function focus_amp = propagate_exit_field_asm(exit_complex, H_forward, center_idx, Nx_pad, Ny_pad)
U_exit_pad = zeros(Nx_pad, Ny_pad);
U_exit_pad(center_idx, center_idx) = exit_complex ./ (max(abs(exit_complex(:))) + eps);
A_exit = fftshift(fft2(ifftshift(U_exit_pad)));
U_target_exit = fftshift(ifft2(ifftshift(A_exit .* H_forward)));
focus_amp = abs(U_target_exit(center_idx, center_idx));
end

function focus_scan = scan_exit_field_asm_focus(exit_complex, Kz, propagating, z_distances, center_idx, Nx_pad, Ny_pad, target_norm)
U_exit_pad = zeros(Nx_pad, Ny_pad);
U_exit_pad(center_idx, center_idx) = exit_complex ./ (max(abs(exit_complex(:))) + eps);
A_exit = fftshift(fft2(ifftshift(U_exit_pad)));

n_planes = numel(z_distances);
z_mm = zeros(1, n_planes);
pcc = zeros(1, n_planes);
ssim_val = zeros(1, n_planes);
nmse = zeros(1, n_planes);
ee = zeros(1, n_planes);
best_idx = 1;
best_pcc = -inf;
best_metrics = empty_image_metrics();

for idx = 1:n_planes
    H_scan = zeros(size(Kz));
    H_scan(propagating) = exp(1i * Kz(propagating) * z_distances(idx));
    U_target = fftshift(ifft2(ifftshift(A_exit .* H_scan)));
    amp = abs(U_target(center_idx, center_idx));
    amp_norm = amp / (max(amp(:)) + eps);
    metrics = calc_image_metrics(amp_norm, target_norm);

    z_mm(idx) = z_distances(idx) * 1e3;
    pcc(idx) = metrics.pcc;
    ssim_val(idx) = metrics.ssim;
    nmse(idx) = metrics.nmse;
    ee(idx) = metrics.ee;

    if metrics.pcc > best_pcc
        best_pcc = metrics.pcc;
        best_idx = idx;
        best_metrics = metrics;
    end
end

focus_scan = struct();
focus_scan.z_mm = z_mm;
focus_scan.pcc = pcc;
focus_scan.ssim = ssim_val;
focus_scan.nmse = nmse;
focus_scan.ee = ee;
focus_scan.best_idx = best_idx;
focus_scan.best_z_mm = z_mm(best_idx);
focus_scan.best_metrics = best_metrics;
end

function metrics = calc_image_metrics(pred_img, target_img)
pred_norm = pred_img / (max(pred_img(:)) + eps);
target_norm = target_img / (max(target_img(:)) + eps);
metrics.pcc = corr2(pred_norm, target_norm);
metrics.ssim = ssim(double(pred_norm), double(target_norm));
metrics.nmse = sum((pred_norm(:) - target_norm(:)).^2) / sum(target_norm(:).^2);
target_mask = target_norm > 0.5;
metrics.ee = sum(pred_norm(target_mask).^2) / (sum(pred_norm(:).^2) + eps);
end

function metrics = empty_image_metrics()
metrics = struct('pcc', NaN, 'ssim', NaN, 'nmse', NaN, 'ee', NaN);
end

function cure_result = empty_cure_result(map_size)
empty_map = false(map_size);
cure_result = struct();
cure_result.p_scaled = NaN(map_size);
cure_result.cavitation = struct();
cure_result.dose_rate = NaN(map_size);
cure_result.dose_components = struct();
cure_result.cure_score = NaN(map_size);
cure_result.cured_mask = empty_map;
cure_result.components = struct();
cure_result.metrics = struct( ...
    'threshold', NaN, ...
    'IoU', NaN, ...
    'Dice', NaN, ...
    'over_cure_ratio', NaN, ...
    'under_cure_ratio', NaN, ...
    'cured_coverage', NaN, ...
    'cured_mask', empty_map);
end
