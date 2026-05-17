clear; close all; clc;
try
    reset(gpuDevice);
catch
end
%% 1. 参数设置
Nx = 512;
Lx = 65e-3;
Ny = Nx; Ly = Lx; 
System_Offset = 2.03e-3;
z_target_dist = 16e-3;
f0 = 4.5e6;
c_water = 1480;
c_board = 2430;
density_water = 997;
density_board = 1100;
lambda_water = c_water / f0;
phase_refine_mode = 'pure_iasa'; %相位叠加模式
phase_method = 'wiasa';
iasa_epoch = 150;
iasa_anchor_eta = 1.0;
research_mode.enabled = 0;
research_mode.export_dir = 'C:\Users\Zh89\Desktop\transport\exit_amp_surrogate';
research_mode.patch_size = 9;
research_mode.sample_stride = 1;
research_mode.max_samples_per_run = 30000;
research_mode.run_label = 'baseline';
research_mode.enable_run_export = true;

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

fprintf('==================================================\n');
fprintf('Grid dx = dy = dz = %.4f mm\n', dx * 1e3);
fprintf('PPW: %.2f\n', lambda_water / dx);
fprintf('Grid size: %d x %d x %d (%.1f M cells)\n', Nx, Ny, Nz, (Nx * Ny * Nz) / 1e6);
fprintf('==================================================\n');

%% 2.目标图案
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
imag_target_design = imag_target;
%热学固化估计，提前腐蚀目标
thermal_alpha_guess = 0.15 / (1100 * 1800);
thermal_exposure_guess = 0.35;
thermal_diff_len = sqrt(4 * thermal_alpha_guess * thermal_exposure_guess);
thermal_sigma_px = max(0.8, 0.35 * thermal_diff_len / dx);
precomp_threshold = 0.58;
design_blur = imgaussfilt(double(imag_target_raw), thermal_sigma_px);
imag_target_design = double(design_blur > precomp_threshold);
imag_target_design = imgaussfilt(imag_target_design, 0.45);
imag_target_design = imag_target_design / max(imag_target_design(:));
%%%%%%%%%%%%%%%%%%
ROI_pixels = nnz(imag_target(:) > 0.5);
fprintf('Target ROI pixels: %d\n', ROI_pixels);

transport_dir = 'C:\Users\Zh89\Desktop\transport';
if ~exist(transport_dir, 'dir')
    mkdir(transport_dir);
end
export_path = fullfile(transport_dir, 'target_for_python.mat');
min_base_layers = 2;
fprintf('\n==================================================\n');
fprintf('Pure IASA mode: %s\n', upper(phase_method));
fprintf('Skip Python transport and build the initial phase directly in MATLAB.\n');
fprintf('==================================================\n\n');

%% 3. 加载初相并用IASA复算
fprintf('IASA...\n');
%padding
pad_factor = 2;
Nx_pad = Nx * pad_factor;
Ny_pad = Ny * pad_factor;
Lx_pad = Lx * pad_factor;
dk_pad = 2 * pi / Lx_pad;
kx_pad = (-Nx_pad/2 : Nx_pad/2-1) * dk_pad;
[Kx_pad, Ky_pad] = meshgrid(kx_pad, kx_pad);
k_water = 2 * pi / lambda_water;
Kz_sq = k_water^2 - Kx_pad.^2 - Ky_pad.^2;
%倏逝波处理
propagating = (Kz_sq > 0);
Kz = zeros(size(Kz_sq));
Kz(propagating) = sqrt(Kz_sq(propagating));
H_forward = zeros(size(Kz_sq));
H_forward(propagating) = exp(1i * Kz(propagating) * z_target_dist);
H_backward = conj(H_forward);

target_amp_design = sqrt(max(imag_target_design, 0));
center_idx = Nx/2+1:Nx/2+Nx;

[Y_grid_source, X_grid_source] = meshgrid(x, x);
circle_mask_board = (X_grid_source.^2 + Y_grid_source.^2) <= (32e-3)^2;
k_board_val = 2 * pi * f0 / c_board;
k_water_val = 2 * pi * f0 / c_water;
k_diff = abs(k_water_val - k_board_val);
phase_step = k_diff * dz;
phase_result = run_arrhenius_iasa_variant( ...
    phase_method, target_amp_design, circle_mask_board, H_forward, H_backward, ...
    phase_step, min_base_layers, iasa_epoch, iasa_anchor_eta);
phase_projected_init = phase_result.initial_phase;
net_num_board = phase_result.net_num_board;
holo_phase = phase_result.final_phase;
phase_initial_label = phase_result.initial_label;
phase_final_label = phase_result.final_label;
asm_python_amp = phase_result.initial_amp;
asm_iasa_amp = phase_result.final_amp;
asm_python_norm = asm_python_amp / (max(asm_python_amp(:)) + eps);
asm_iasa_norm = asm_iasa_amp / (max(asm_iasa_amp(:)) + eps);
target_norm_asm = imag_target / (max(imag_target(:)) + eps);
asm_python_pcc = corr2(asm_python_norm, target_norm_asm);
asm_iasa_pcc = corr2(asm_iasa_norm, target_norm_asm);
asm_python_nmse = sum((target_norm_asm(:) - asm_python_norm(:)).^2) / sum(target_norm_asm(:).^2);
asm_iasa_nmse = sum((target_norm_asm(:) - asm_iasa_norm(:)).^2) / sum(target_norm_asm(:).^2);
asm_python_ssim = ssim(double(asm_python_norm), double(target_norm_asm));
asm_iasa_ssim = ssim(double(asm_iasa_norm), double(target_norm_asm));

%% 4. 相位转厚度
phase_wrapped = mod(holo_phase, 2 * pi);
thickness_map = net_num_board * dz;
actual_thickness = thickness_map;
actual_thickness(~circle_mask_board) = NaN;

actual_phase_imparted = mod(net_num_board * dz * k_diff, 2 * pi);
complex_diff_voxel = exp(1i * actual_phase_imparted(circle_mask_board)) ./ exp(1i * phase_wrapped(circle_mask_board));
global_offset_voxel = angle(mean(complex_diff_voxel(:)));
phase_aligned_voxel = nan(size(phase_wrapped));
phase_aligned_voxel(circle_mask_board) = angle(exp(1i * ...
    (actual_phase_imparted(circle_mask_board) - global_offset_voxel)));

%% 5. KWAVE设置
fprintf('构建空间并执行仿真\n');
kgrid = kWaveGrid(Nx, dx, Ny, dy, Nz, dz);
medium.sound_speed = c_water * ones(Nx, Ny, Nz);
medium.density = density_water * ones(Nx, Ny, Nz);
medium.alpha_coeff = 0.002 * ones(Nx, Ny, Nz);
medium.alpha_power = 1.5;
alpha_coeff_board = 1.5;
pml_size = 10;
source_z_idx = pml_size + 5;
z_board_start_idx = source_z_idx + 1;

for i = 1:Nx
    for j = 1:Ny
        n_layers = net_num_board(i, j);
        if n_layers > 0
            z_start = z_board_start_idx;
            z_end = z_board_start_idx + n_layers - 1;
            medium.sound_speed(i, j, z_start:z_end) = c_board;
            medium.density(i, j, z_start:z_end) = density_board;
            medium.alpha_coeff(i, j, z_start:z_end) = alpha_coeff_board;
        end
    end
end
thickest = max(net_num_board(:)) * dz;
%时间定义
cfl = 0.3;
t_end = (Lz * 1.5) / c_water;
kgrid.makeTime(medium.sound_speed, cfl, t_end);
%声源定义
source.p_mask = zeros(Nx, Ny, Nz);
source.p_mask(:, :, source_z_idx) = circle_mask_board;
t_vec = kgrid.t_array;
source_sig = sin(2 * pi * f0 * t_vec);
ramp_pts = round(2 / f0 / kgrid.dt);
window = [linspace(0, 1, ramp_pts), ones(1, kgrid.Nt - ramp_pts)];
source.p = source_sig .* window;
source.p_mode = 'dirichlet';
%sensor定义
sensor.mask = zeros(Nx, Ny, Nz);
z_board_exit_idx = z_board_start_idx + round(thickest / dz);
target_plane_idx = z_board_exit_idx + round(z_target_dist / dz);
scan_range_idx = round(3e-3 / dz);
z_scan_start = target_plane_idx - scan_range_idx;
z_scan_end = target_plane_idx + scan_range_idx;
if z_scan_end > Nz - pml_size
    z_scan_end = Nz - pml_size;
end
% 3mm扫描声场，寻找最佳焦平面
sensor.mask(:, :, z_scan_start:z_scan_end) = 1;
sensor.record = {'p_max'};
sensor.record_start_index = kgrid.Nt - round(3 / f0 / kgrid.dt);
% 仿真
reset(gpuDevice);
input_args = {'PMLInside', true, 'PMLSize', 10, 'PlotPML', false, 'PlotSim', false, 'DataCast', 'gpuArray-single'};
try
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
catch
    disp('GPU调用失败,使用CPU仿真');
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{1:end-2});
end

p_amp = gather(sensor_data.p_max);
p_field_3d = zeros(Nx, Ny, Nz);
p_field_3d(sensor.mask ~= 0) = p_amp;
scan_vol = p_field_3d(:, :, z_scan_start:z_scan_end);
num_slices = size(scan_vol, 3);
R = double(imag_target);
R = (R - min(R(:))) / (max(R(:)) - min(R(:)));
R_mean = mean(R(:));

best_corr = -1;
best_slice_idx = 1;
metrics_z = zeros(num_slices, 1);
metrics_corr = zeros(num_slices, 1);
for k = 1:num_slices
    A = scan_vol(:, :, k);
    A = (A - min(A(:))) / (max(A(:)) - min(A(:)) + eps);
    A_mean = mean(A(:));
    numerator = sum(sum((R - R_mean) .* (A - A_mean)));
    denominator = sqrt(sum(sum((R - R_mean).^2)) * sum(sum((A - A_mean).^2)));
    val_corr = numerator / (denominator + eps);
    metrics_z(k) = (z_scan_start + k - 1 - z_board_exit_idx) * dz * 1e3;
    metrics_corr(k) = val_corr;
    if val_corr > best_corr
        best_corr = val_corr;
        best_slice_idx = k;
    end
end
best_idx_global = z_scan_start + best_slice_idx - 1;
actual_z_dist_idx = best_idx_global - z_board_exit_idx;
actual_z_dist_mm = actual_z_dist_idx * dz * 1e3;

%% 6.相位板出口分析
fprintf('执行出口平面声场分析\n');
%记录出口平面声场
exit_sensor.mask = zeros(Nx, Ny, Nz);
exit_sensor.mask(:, :, z_board_exit_idx) = 1;
exit_sensor.record = {'p'};
exit_sensor.record_start_index = kgrid.Nt - round(3 / f0 / kgrid.dt);
reset(gpuDevice);
try
    exit_sensor_data = kspaceFirstOrder3D(kgrid, medium, source, exit_sensor, input_args{:});
catch
    disp('GPU调用失败,使用CPU仿真');
    exit_sensor_data = kspaceFirstOrder3D(kgrid, medium, source, exit_sensor, input_args{1:end-2});
end

p_exit_time = gather(exit_sensor_data.p);
t_exit = kgrid.t_array(exit_sensor.record_start_index:end);
demod = exp(-1i * 2 * pi * f0 * t_exit(:));
p_exit_complex_vec = (p_exit_time * demod) ./ numel(t_exit);
p_exit_complex = reshape(p_exit_complex_vec, Nx, Ny);
p_exit_amp = abs(p_exit_complex);
p_exit_amp_norm = p_exit_amp / (max(p_exit_amp(:)) + eps);
p_exit_phase = angle(p_exit_complex);
exit_vals = p_exit_amp(circle_mask_board);
exit_amp_cv = std(exit_vals(:)) / (mean(exit_vals(:)) + eps);
exit_amp_min_ratio = min(exit_vals(:)) / (max(exit_vals(:)) + eps);

% 板致幅度调制规律统计：厚度、厚度梯度与出口振幅
thickness_mm = thickness_map * 1e3;
[thickness_grad_x, thickness_grad_y] = gradient(thickness_map);
thickness_grad_norm = hypot(thickness_grad_x, thickness_grad_y) / (dz + eps);
valid_exit_mask = circle_mask_board & isfinite(thickness_mm) & isfinite(p_exit_amp_norm);

window_kernel = ones(5, 5);
window_count = conv2(double(circle_mask_board), window_kernel, 'same');
local_thickness_mean = conv2(thickness_map .* double(circle_mask_board), window_kernel, 'same') ./ (window_count + eps);
local_thickness_var = conv2(((thickness_map - local_thickness_mean).^2) .* double(circle_mask_board), window_kernel, 'same') ./ (window_count + eps);
local_thickness_std = sqrt(max(local_thickness_var, 0)) * 1e3;

aperture_edge_distance_px = bwdist(~circle_mask_board);
aperture_edge_distance_mm = aperture_edge_distance_px * dx * 1e3;

thickness_vals_mm = thickness_mm(valid_exit_mask);
grad_vals = thickness_grad_norm(valid_exit_mask);
exit_amp_vals = p_exit_amp_norm(valid_exit_mask);
local_mean_vals_mm = (local_thickness_mean(valid_exit_mask) * 1e3);
local_std_vals_mm = local_thickness_std(valid_exit_mask);
edge_dist_vals_mm = aperture_edge_distance_mm(valid_exit_mask);

edge_mask = valid_exit_mask & (thickness_grad_norm > 0.25);
flat_mask = valid_exit_mask & ~edge_mask;
edge_amp_mean = mean(p_exit_amp_norm(edge_mask));
flat_amp_mean = mean(p_exit_amp_norm(flat_mask));

if numel(unique(thickness_vals_mm)) > 1
    thickness_amp_corr = corr(thickness_vals_mm(:), exit_amp_vals(:), 'type', 'Pearson');
else
    thickness_amp_corr = NaN;
end

if numel(unique(grad_vals)) > 1
    grad_amp_corr = corr(grad_vals(:), exit_amp_vals(:), 'type', 'Pearson');
else
    grad_amp_corr = NaN;
end

if numel(unique(local_mean_vals_mm)) > 1
    local_mean_amp_corr = corr(local_mean_vals_mm(:), exit_amp_vals(:), 'type', 'Pearson');
else
    local_mean_amp_corr = NaN;
end

if numel(unique(local_std_vals_mm)) > 1
    local_std_amp_corr = corr(local_std_vals_mm(:), exit_amp_vals(:), 'type', 'Pearson');
else
    local_std_amp_corr = NaN;
end

if numel(unique(edge_dist_vals_mm)) > 1
    edge_dist_amp_corr = corr(edge_dist_vals_mm(:), exit_amp_vals(:), 'type', 'Pearson');
else
    edge_dist_amp_corr = NaN;
end

design_matrix = [
    ones(numel(exit_amp_vals), 1), ...
    thickness_vals_mm(:), ...
    grad_vals(:), ...
    local_mean_vals_mm(:), ...
    local_std_vals_mm(:), ...
    edge_dist_vals_mm(:)
];
coeff_multi = design_matrix \ exit_amp_vals(:);
exit_amp_pred = design_matrix * coeff_multi;
ss_res = sum((exit_amp_vals(:) - exit_amp_pred(:)).^2);
ss_tot = sum((exit_amp_vals(:) - mean(exit_amp_vals(:))).^2);
exit_amp_model_r2 = 1 - ss_res / (ss_tot + eps);

unique_layers = unique(net_num_board(valid_exit_mask));
layer_mean_amp = zeros(numel(unique_layers), 1);
layer_std_amp = zeros(numel(unique_layers), 1);
layer_mean_thickness_mm = zeros(numel(unique_layers), 1);
for layer_idx = 1:numel(unique_layers)
    current_layer = unique_layers(layer_idx);
    current_mask = valid_exit_mask & (net_num_board == current_layer);
    current_vals = p_exit_amp_norm(current_mask);
    layer_mean_amp(layer_idx) = mean(current_vals);
    layer_std_amp(layer_idx) = std(current_vals);
    layer_mean_thickness_mm(layer_idx) = mean(thickness_mm(current_mask));
end

scatter_stride = max(1, floor(numel(exit_amp_vals) / 4000));
scatter_sample_idx = 1:scatter_stride:numel(exit_amp_vals);
thickness_scatter_mm = thickness_vals_mm(scatter_sample_idx);
grad_scatter = grad_vals(scatter_sample_idx);
exit_amp_scatter = exit_amp_vals(scatter_sample_idx);
local_std_scatter_mm = local_std_vals_mm(scatter_sample_idx);
edge_dist_scatter_mm = edge_dist_vals_mm(scatter_sample_idx);
model_pred_scatter = exit_amp_pred(scatter_sample_idx);

U_exit_pad = zeros(Nx_pad, Ny_pad);
U_exit_pad(center_idx, center_idx) = p_exit_complex ./ (max(p_exit_amp(:)) + eps);
A_exit = fftshift(fft2(ifftshift(U_exit_pad)));
U_target_exit = fftshift(ifft2(ifftshift(A_exit .* H_forward)));
board_exit_asm_amp = abs(U_target_exit(center_idx, center_idx));
board_exit_asm_norm = board_exit_asm_amp / (max(board_exit_asm_amp(:)) + eps);
board_exit_asm_pcc = corr2(board_exit_asm_norm, target_norm_asm);
board_exit_kwave_corr = corr2(board_exit_asm_norm, ...
    (scan_vol(:, :, best_slice_idx) - min(scan_vol(:, :, best_slice_idx), [], 'all')) / ...
    (max(scan_vol(:, :, best_slice_idx), [], 'all') - min(scan_vol(:, :, best_slice_idx), [], 'all') + eps));

if research_mode.enabled && research_mode.enable_run_export
    if ~exist(research_mode.export_dir, 'dir')
        mkdir(research_mode.export_dir);
    end
    run_metrics = struct( ...
        'exit_amp_cv', exit_amp_cv, ...
        'exit_amp_min_ratio', exit_amp_min_ratio, ...
        'thickness_amp_corr', thickness_amp_corr, ...
        'grad_amp_corr', grad_amp_corr, ...
        'local_mean_amp_corr', local_mean_amp_corr, ...
        'local_std_amp_corr', local_std_amp_corr, ...
        'edge_dist_amp_corr', edge_dist_amp_corr, ...
        'multi_factor_r2', exit_amp_model_r2, ...
        'board_exit_asm_pcc', board_exit_asm_pcc, ...
        'board_exit_kwave_corr', board_exit_kwave_corr);
    run_meta = struct( ...
        'run_label', research_mode.run_label, ...
        'patch_size', research_mode.patch_size, ...
        'sample_stride', research_mode.sample_stride, ...
        'max_samples_per_run', research_mode.max_samples_per_run, ...
        'Nx', Nx, 'Ny', Ny, 'dx', dx, 'dz', dz, ...
        'f0', f0, 'Lx', Lx, 'z_target_dist', z_target_dist, ...
        'c_water', c_water, 'c_board', c_board, ...
        'density_water', density_water, 'density_board', density_board, ...
        'alpha_coeff_board', alpha_coeff_board, ...
        'actual_z_dist_mm', actual_z_dist_mm);
    export_exit_amp_surrogate_run( ...
        research_mode.export_dir, run_meta, run_metrics, ...
        thickness_map, thickness_grad_norm, p_exit_amp_norm, ...
        circle_mask_board, x, y, dx, net_num_board, ...
        aperture_edge_distance_mm, local_thickness_mean, local_thickness_std);
end

%% 7.热场与固化
fprintf('热场分析与固化预测\n');
p_3d_abs = abs(p_field_3d);
focal_slice_abs = p_3d_abs(:, :, best_idx_global);
roi_mask = (imag_target > 0.5);
median_roi_p = median(focal_slice_abs(roi_mask));

rho_resin = 1100; c_resin = 2500; Cp_resin_liq = 1800; k_resin_liq = 0.15;
rho_water = 997;  c_water_heat = 1480; Cp_water = 4180; k_water_heat = 0.6;
alpha_np_resin_liq = (1.5 / 8.686) * 100 * (f0 / 1e6)^1.5;
alpha_np_water = 0.02;
resin_z_start = z_board_exit_idx + 1;
cavitation_limit = 2.0e6;

E_a = 9.5e4; A_freq = 8.0e15; R_gas = 8.314;
inv_dx2 = 1 / (dx^2);
max_diff = max(k_water_heat / (rho_water * Cp_water), k_resin_liq / (rho_resin * Cp_resin_liq));
dt_th = (dx^2 / (6 * max_diff)) * 0.8;

z_crop_radius = round(1.5e-3 / dz);
z_crop_start = max(1, best_idx_global - z_crop_radius);
z_crop_end = min(Nz, best_idx_global + z_crop_radius);
best_idx_crop = best_idx_global - z_crop_start + 1;
z_crop_len = z_crop_end - z_crop_start + 1;

best_IoU_global = 0;
best_record = struct();
best_coarse = struct('P', 1.5e6, 'E', 0.3, 'C', 0.2);

for phase = 1:2
    if phase == 1
        %曝光时间，声压与冷却时间粗查
        fprintf('\n[第一阶段:粗扫]...\n');
        P_list = (1.2 : 0.2 : 1.8) * 1e6;
        E_list = 0.15 : 0.10 : 0.45;
        C_list = 0.10 : 0.10 : 0.30;
    else
        %细查
         fprintf('\n[第二阶段: 微调](P=%.2f, E=%.2f, C=%.2f)...\n', ...
            best_coarse.P/1e6, best_coarse.E, best_coarse.C);
        P_list = (best_coarse.P - 0.1e6) : 0.05e6 : (best_coarse.P + 0.1e6);
        E_list = max(0.10, best_coarse.E - 0.05) : 0.02 : (best_coarse.E + 0.05);
        C_list = max(0.05, best_coarse.C - 0.05) : 0.05 : (best_coarse.C + 0.05);
    end

    [Pg, Eg, Cg] = ndgrid(P_list, E_list, C_list);
    params_all = [Pg(:), Eg(:), Cg(:)];
    energy_index = (params_all(:, 1) / 1e6).^2 .* params_all(:, 2);
    valid_mask = (energy_index >= 0.3) & (energy_index <= 1.2);
    params_valid = sortrows(params_all(valid_mask, :), 1);
    num_tests = size(params_valid, 1);
    current_P = -1;

    for i = 1:num_tests
        p_target = params_valid(i, 1);
        t_exp = params_valid(i, 2);
        t_cool = params_valid(i, 3);

        if p_target ~= current_P
            scale_factor = p_target / median_roi_p;
            p_3d_scaled = p_3d_abs * scale_factor;
            p_3d_scaled(p_3d_scaled > cavitation_limit) = cavitation_limit;

            k_3d = k_water_heat * ones(Nx, Ny, Nz, 'single');
            k_3d(:, :, resin_z_start:end) = k_resin_liq;
            rho_Cp_3d = (rho_water * Cp_water) * ones(Nx, Ny, Nz, 'single');
            rho_Cp_3d(:, :, resin_z_start:end) = rho_resin * Cp_resin_liq;

            Q_heat_3d = zeros(Nx, Ny, Nz, 'single');
            I_3d_resin = single((p_3d_scaled(:, :, resin_z_start:end).^2) ./ (2 * rho_resin * c_resin));
            Q_heat_3d(:, :, resin_z_start:end) = 2 * alpha_np_resin_liq * I_3d_resin;
            I_3d_water = single((p_3d_scaled(:, :, 1:resin_z_start-1).^2) ./ (2 * rho_water * c_water_heat));
            Q_heat_3d(:, :, 1:resin_z_start-1) = 2 * alpha_np_water * I_3d_water;

            k_3d_base_gpu = gpuArray(k_3d(:, :, z_crop_start:z_crop_end));
            rho_Cp_3d_gpu = gpuArray(rho_Cp_3d(:, :, z_crop_start:z_crop_end));
            Q_heat_3d_gpu = gpuArray(Q_heat_3d(:, :, z_crop_start:z_crop_end));
            current_P = p_target;
        end

        total_time = t_exp + t_cool;
        Nt_th = round(total_time / dt_th);
        step_exposure_end = round(t_exp / dt_th);

        T_3d_gpu = 25 * ones(Nx, Ny, z_crop_len, 'single', 'gpuArray');
        k_3d_gpu = k_3d_base_gpu;
        Arrhenius_Omega_gpu = zeros(Nx, Ny, 'single', 'gpuArray');
        T_max_history_tmp = zeros(Nt_th, 1);

        for step = 1:Nt_th
            chi_focal = 1.0 - exp(-Arrhenius_Omega_gpu);
            k_3d_gpu(:, :, best_idx_crop) = k_resin_liq * (1.0 + 0.6 * chi_focal);

            T_diff_x = diff(T_3d_gpu, 1, 1);
            k_mid_x = (k_3d_gpu(1:end-1, :, :) + k_3d_gpu(2:end, :, :)) / 2;
            div_flux_x = diff([zeros(1, Ny, z_crop_len, 'single', 'gpuArray'); ...
                k_mid_x .* T_diff_x; zeros(1, Ny, z_crop_len, 'single', 'gpuArray')], 1, 1);

            T_diff_y = diff(T_3d_gpu, 1, 2);
            k_mid_y = (k_3d_gpu(:, 1:end-1, :) + k_3d_gpu(:, 2:end, :)) / 2;
            div_flux_y = diff([zeros(Nx, 1, z_crop_len, 'single', 'gpuArray'), ...
                k_mid_y .* T_diff_y, zeros(Nx, 1, z_crop_len, 'single', 'gpuArray')], 1, 2);

            T_diff_z = diff(T_3d_gpu, 1, 3);
            k_mid_z = (k_3d_gpu(:, :, 1:end-1) + k_3d_gpu(:, :, 2:end)) / 2;
            div_flux_z = diff(cat(3, zeros(Nx, Ny, 1, 'single', 'gpuArray'), ...
                k_mid_z .* T_diff_z, zeros(Nx, Ny, 1, 'single', 'gpuArray')), 1, 3);

            thermal_diffusion_term = (div_flux_x + div_flux_y + div_flux_z) ./ rho_Cp_3d_gpu * inv_dx2;

            if step <= step_exposure_end
                abs_multiplier = 1.0 + 3.0 * chi_focal;
                Q_dynamic = Q_heat_3d_gpu;
                Q_dynamic(:, :, best_idx_crop) = Q_heat_3d_gpu(:, :, best_idx_crop) .* abs_multiplier;
                T_3d_gpu = T_3d_gpu + dt_th * (thermal_diffusion_term + Q_dynamic ./ rho_Cp_3d_gpu);
            else
                T_3d_gpu = T_3d_gpu + dt_th * thermal_diffusion_term;
            end

            T_focal_slice = T_3d_gpu(:, :, best_idx_crop);
            T_max_history_tmp(step) = gather(max(T_focal_slice(:)));
            T_current_K = T_focal_slice + 273.15;
            reaction_rate = A_freq .* exp(-E_a ./ (R_gas .* T_current_K));
            Arrhenius_Omega_gpu = Arrhenius_Omega_gpu + reaction_rate .* dt_th;
        end

        Omega_tmp = gather(double(Arrhenius_Omega_gpu));
        cured_mask_tmp = (Omega_tmp >= 1.0);
        target_mask_2d = double(imag_target > 0.5);
        intersection = sum(cured_mask_tmp(:) & target_mask_2d(:));
        union_area = sum(cured_mask_tmp(:) | target_mask_2d(:));
        current_IoU = intersection / (union_area + 1e-10);

        fprintf('  [%02d/%02d] P=%.2f MPa, Exp=%.2f s, Cool=%.2f s | Tmax: %4.1f C | IoU: %.4f\n', ...
            i, num_tests, p_target / 1e6, t_exp, t_cool, max(T_max_history_tmp), current_IoU);

        if current_IoU > best_IoU_global
            best_IoU_global = current_IoU;
            best_record.p_target = p_target;
            best_record.t_exp = t_exp;
            best_record.t_cool = t_cool;
            best_record.T_focal_2d = gather(double(T_3d_gpu(:, :, best_idx_crop)));
            best_record.Q_focal_2d = gather(double(Q_heat_3d_gpu(:, :, best_idx_crop)));
            best_record.Omega_final_2d = Omega_tmp;
            best_record.T_max_history = T_max_history_tmp;
            best_record.Nt_th = Nt_th;
            best_record.p_3d_scaled = p_3d_scaled;
            if phase == 1
                best_coarse.P = p_target;
                best_coarse.E = t_exp;
                best_coarse.C = t_cool;
            end
        end
    end
end
fprintf('定标声压: %.2f MPa\n', best_record.p_target / 1e6);
fprintf('曝光时长: %.2f 秒\n', best_record.t_exp);
fprintf('冷却时长: %.2f 秒\n', best_record.t_cool);
fprintf('IoU: %.4f\n', best_IoU_global);

target_median_pressure = best_record.p_target;
exposure_time = best_record.t_exp;
cooling_time = best_record.t_cool;
T_focal_2d = best_record.T_focal_2d;
Q_focal_2d = best_record.Q_focal_2d;
Omega_final_2d = best_record.Omega_final_2d;
T_max_history = best_record.T_max_history;
Nt_th = best_record.Nt_th;
p_3d_scaled = best_record.p_3d_scaled;
t_axis = (1:Nt_th) * dt_th;
T_max_real = max(T_max_history);

%% 8.结果处理
Thermal_Dose_Threshold = 1.0;
cured_mask_2d = Omega_final_2d >= Thermal_Dose_Threshold;
R_binary = imag_target > 0.5;
ROI_pixels = sum(R_binary(:));

cured_coverage = (sum(cured_mask_2d(:) & R_binary(:)) / ROI_pixels) * 100;
if cured_coverage > 100, cured_coverage = 100; end
intersection = R_binary & cured_mask_2d;
union_mask = R_binary | cured_mask_2d;
IoU = sum(intersection(:)) / (sum(union_mask(:)) + 1e-8);
Dice = 2 * sum(intersection(:)) / (sum(R_binary(:)) + sum(cured_mask_2d(:)) + 1e-8);
over_cure_ratio = sum(cured_mask_2d(:) & ~R_binary(:)) / ROI_pixels;
under_cure_ratio = sum(~cured_mask_2d(:) & R_binary(:)) / ROI_pixels;

p_focal_scaled = gather(p_3d_scaled(:, :, best_idx_global));
p_focal_norm = p_focal_scaled / max(p_focal_scaled(:));
NMSE = sum((target_norm_asm(:) - p_focal_norm(:)).^2) / sum(target_norm_asm(:).^2);
SSIM_val = ssim(double(p_focal_norm), double(target_norm_asm));
Energy_Efficiency = sum(p_focal_norm(R_binary).^2) / sum(p_focal_norm(:).^2);
asm_kwave_corr = corr2(asm_iasa_norm, p_focal_norm);
asm_kwave_nmse = sum((asm_iasa_norm(:) - p_focal_norm(:)).^2) / sum(asm_iasa_norm(:).^2);
asm_python_kwave_corr = corr2(asm_python_norm, p_focal_norm);
asm_python_kwave_nmse = sum((asm_python_norm(:) - p_focal_norm(:)).^2) / sum(asm_python_norm(:).^2);

%% 9.可视化
figure(1); clf; set(gcf, 'Position', [120, 120, 1400, 420], 'Color', 'w');
subplot(1, 4, 1);
imagesc(x * 1e3, y * 1e3, target_norm_asm); axis image; colormap(gca, gray);
title('Target'); xlabel('mm'); ylabel('mm');

subplot(1, 4, 2);
imagesc(x * 1e3, y * 1e3, asm_python_norm); axis image; colormap(gca, turbo); colorbar;
title(sprintf('%s ASM\nPCC %.4f | SSIM %.4f', phase_initial_label, asm_python_pcc, asm_python_ssim)); xlabel('mm'); ylabel('mm');

subplot(1, 4, 3);
imagesc(x * 1e3, y * 1e3, asm_iasa_norm); axis image; colormap(gca, turbo); colorbar;
title(sprintf('%s ASM\nPCC %.4f | SSIM %.4f', phase_final_label, asm_iasa_pcc, asm_iasa_ssim)); xlabel('mm'); ylabel('mm');

subplot(1, 4, 4);
imagesc(x * 1e3, y * 1e3, p_focal_norm); axis image; colormap(gca, turbo); colorbar;
title(sprintf('k-Wave Focal\nPCC %.4f | SSIM %.4f', best_corr, SSIM_val)); xlabel('mm'); ylabel('mm');

figure(2); clf; set(gcf, 'Position', [100, 100, 1500, 420], 'Color', 'w');
subplot(1, 4, 1);
imagesc(x * 1e3, y * 1e3, p_exit_amp_norm); axis image; colormap(gca, turbo); colorbar;
title(sprintf('Exit Amp\nCV %.4f | min/max %.4f', exit_amp_cv, exit_amp_min_ratio)); xlabel('mm'); ylabel('mm');

subplot(1, 4, 2);
imagesc(x * 1e3, y * 1e3, p_exit_phase); axis image; colormap(gca, hsv); colorbar;
title('Exit Phase'); xlabel('mm'); ylabel('mm');

subplot(1, 4, 3);
imagesc(x * 1e3, y * 1e3, board_exit_asm_norm); axis image; colormap(gca, turbo); colorbar;
title(sprintf('Exit-Field ASM\nTarget PCC %.4f', board_exit_asm_pcc)); xlabel('mm'); ylabel('mm');

subplot(1, 4, 4);
imagesc(x * 1e3, y * 1e3, p_focal_norm); axis image; colormap(gca, turbo); colorbar;
title(sprintf('k-Wave Focal\nExit-ASM PCC %.4f', board_exit_kwave_corr)); xlabel('mm'); ylabel('mm');

figure(3); clf; set(gcf, 'Position', [60, 40, 1550, 980], 'Color', 'w');
subplot(3, 3, 1);
imagesc(x * 1e3, y * 1e3, thickness_mm); axis image; colormap(gca, parula); colorbar;
title('Board Thickness (mm)'); xlabel('mm'); ylabel('mm');

subplot(3, 3, 2);
imagesc(x * 1e3, y * 1e3, thickness_grad_norm); axis image; colormap(gca, hot); colorbar;
title('Thickness Gradient'); xlabel('mm'); ylabel('mm');

subplot(3, 3, 3);
imagesc(x * 1e3, y * 1e3, p_exit_amp_norm); axis image; colormap(gca, turbo); colorbar;
title('Exit Amplitude'); xlabel('mm'); ylabel('mm');

subplot(3, 3, 4);
scatter(thickness_scatter_mm, exit_amp_scatter, 8, grad_scatter, 'filled');
grid on; colorbar; colormap(gca, turbo);
title(sprintf('Thickness vs Exit Amp\nCorr %.4f', thickness_amp_corr));
xlabel('Thickness (mm)'); ylabel('Exit amplitude');

subplot(3, 3, 5);
scatter(grad_scatter, exit_amp_scatter, 8, thickness_scatter_mm, 'filled');
grid on; colorbar; colormap(gca, turbo);
title(sprintf('Gradient vs Exit Amp\nCorr %.4f', grad_amp_corr));
xlabel('Thickness gradient'); ylabel('Exit amplitude');

subplot(3, 3, 6);
errorbar(layer_mean_thickness_mm, layer_mean_amp, layer_std_amp, 'o-', 'LineWidth', 1.2, 'MarkerSize', 5);
grid on;
title(sprintf('Layer-group Mean Exit Amp\nEdge %.4f | Flat %.4f', edge_amp_mean, flat_amp_mean));
xlabel('Mean thickness (mm)'); ylabel('Mean exit amplitude');

subplot(3, 3, 7);
scatter(local_std_scatter_mm, exit_amp_scatter, 8, thickness_scatter_mm, 'filled');
grid on; colorbar; colormap(gca, turbo);
title(sprintf('Local Std vs Exit Amp\nCorr %.4f', local_std_amp_corr));
xlabel('Local thickness std (mm)'); ylabel('Exit amplitude');

subplot(3, 3, 8);
scatter(edge_dist_scatter_mm, exit_amp_scatter, 8, local_std_scatter_mm, 'filled');
grid on; colorbar; colormap(gca, turbo);
title(sprintf('Edge Distance vs Exit Amp\nCorr %.4f', edge_dist_amp_corr));
xlabel('Distance to aperture edge (mm)'); ylabel('Exit amplitude');

subplot(3, 3, 9);
scatter(exit_amp_scatter, model_pred_scatter, 8, edge_dist_scatter_mm, 'filled');
hold on;
plot([0, 1], [0, 1], 'k--', 'LineWidth', 1);
grid on; colorbar; colormap(gca, turbo);
title(sprintf('Multi-factor Fit\nR^2 %.4f', exit_amp_model_r2));
xlabel('Measured exit amplitude'); ylabel('Predicted exit amplitude');

figure('Position', [30 30 1500 1000], 'Color', 'w');
subplot(3, 5, 1);
imagesc(x * 1e3, y * 1e3, imag_target); axis image; colormap(gca, gray);
title('Target'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 2);
imagesc(x * 1e3, y * 1e3, phase_wrapped); axis image; colormap(gca, hsv); colorbar;
title('理论相位'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 3);
imagesc(x * 1e3, y * 1e3, phase_aligned_voxel); axis image; colormap(gca, hsv); colorbar;
title('实际相位'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 4);
surf(x * 1e3, y * 1e3, actual_thickness * 1e3); view(2); shading interp; axis image; colorbar;
title('厚度 (mm)'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 5);
imagesc(x * 1e3, y * 1e3, Omega_final_2d); axis image; colormap(gca, turbo); colorbar;
clim([0, max(2.0, max(Omega_final_2d(:)))]);
title('热剂量'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 6);
imagesc(x * 1e3, y * 1e3, Q_focal_2d / 1e6); axis image; colormap(gca, hot); colorbar;
title('热源 (MW/m^3)'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 7);
imagesc(x * 1e3, y * 1e3, focal_slice_abs / 1e6); axis image; colormap(gca, jet); colorbar;
title('声压 (MPa)'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 8);
imagesc(x * 1e3, y * 1e3, cured_mask_2d); axis image; colormap(gca, [1 1 1; 0.1 0.1 0.3]);
title(sprintf('预测固化 (IoU %.4f)', IoU)); xlabel('mm'); ylabel('mm');

subplot(3, 5, 9);
imagesc(x * 1e3, y * 1e3, T_focal_2d); axis image; colormap(gca, hot); colorbar;
clim([25, max(65, min(T_max_real, 80))]);
title(sprintf('峰值温度 %.1f C', T_max_real)); xlabel('mm'); ylabel('mm');

subplot(3, 5, 10);
plot(metrics_z, metrics_corr, 'b-', 'LineWidth', 1.5); hold on;
plot(actual_z_dist_mm, best_corr, 'ro', 'MarkerSize', 10);
grid on;
title('Z-scan'); xlabel('Z轴偏移量(mm)'); ylabel('Correlation');

subplot(3, 5, [11 12 13]);
center = round(Nx / 2);
plot(x * 1e3, imag_target(center, :), 'k--', 'LineWidth', 2); hold on;
plot(x * 1e3, p_focal_scaled(center, :) / max(p_focal_scaled(:)), 'r-', 'LineWidth', 1.5);
grid on;
title('中心剖面强度'); xlabel('mm'); ylabel('归一化幅值'); legend('目标', '饱和声压分布');

subplot(3, 5, [14 15]);
[X_surf, Y_surf] = meshgrid(x * 1e3, y * 1e3);
surf(X_surf, Y_surf, p_focal_scaled / 1e6); shading interp; colormap(gca, jet); colorbar;
title('3D焦面声压场(MPa)'); xlabel('mm'); ylabel('mm'); zlabel('MPa');

%% 10. Report
fprintf('\n========================================\n');
fprintf('系统参数\n');
fprintf('频率: %.2f MHz | Lens OD: %.1f mm\n', f0 / 1e6, Lx * 1e3);
fprintf('网格分辨率: %.2f um |节点总数: %.1f M\n', dx * 1e6, (Nx * Ny * Nz) / 1e6);
fprintf('----------------------------------------\n');
fprintf('声场质量评估\n');
fprintf('最佳声场距离: %.2f mm\n', actual_z_dist_mm);
fprintf('PCC: %.4f\n', best_corr);
fprintf('SSIM: %.4f\n', SSIM_val);
fprintf('NMSE: %.4f\n', NMSE);
fprintf('EE: %.2f%%\n', Energy_Efficiency * 100);
fprintf('%s ASM PCC/SSIM/NMSE: %.4f / %.4f / %.4f\n', phase_initial_label, asm_python_pcc, asm_python_ssim, asm_python_nmse);
fprintf('%s ASM PCC/SSIM/NMSE: %.4f / %.4f / %.4f\n', phase_final_label, asm_iasa_pcc, asm_iasa_ssim, asm_iasa_nmse);
fprintf('ASM(IASA)-kWave PCC/NMSE: %.4f / %.4f\n', asm_kwave_corr, asm_kwave_nmse);
fprintf('ASM(%s)-kWave PCC/NMSE: %.4f / %.4f\n', phase_initial_label, asm_python_kwave_corr, asm_python_kwave_nmse);
fprintf('出口平面最大幅值: %.4f | min/max ratio: %.4f\n', exit_amp_cv, exit_amp_min_ratio);
fprintf('Exit-field ASM target PCC: %.4f | Exit-field ASM vs k-Wave PCC: %.4f\n', ...
    board_exit_asm_pcc, board_exit_kwave_corr);
fprintf('Thickness-ExitAmp Corr: %.4f | Gradient-ExitAmp Corr: %.4f\n', ...
    thickness_amp_corr, grad_amp_corr);
fprintf('LocalMean-ExitAmp Corr: %.4f | LocalStd-ExitAmp Corr: %.4f\n', ...
    local_mean_amp_corr, local_std_amp_corr);
fprintf('EdgeDist-ExitAmp Corr: %.4f | Multi-factor R^2: %.4f\n', ...
    edge_dist_amp_corr, exit_amp_model_r2);
fprintf('Edge Mean ExitAmp: %.4f | Flat Mean ExitAmp: %.4f\n', edge_amp_mean, flat_amp_mean);
fprintf('----------------------------------------\n');
fprintf('固化分析\n');
fprintf('最佳固化指标出自: %.2f MPa + %.2f s曝光 ( %.2f s冷却)\n', target_median_pressure / 1e6, exposure_time, cooling_time);
fprintf('峰值温度: %.1f C\n', T_max_real);
fprintf('有效固化: %.1f%%\n', cured_coverage);
fprintf('IoU: %.4f\n', IoU);
fprintf('Dice: %.4f\n', Dice);
fprintf('过固化: %.1f%%\n', over_cure_ratio * 100);
fprintf('欠固化: %.1f%%\n', under_cure_ratio * 100);
fprintf('----------------------------------------\n');

try
    reset(gpuDevice);
catch
end
