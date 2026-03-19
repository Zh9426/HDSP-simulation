clear; close all; clc;
reset(gpuDevice); % 强制清空 GPU 显存底层垃圾

%% 1. 网格及参数设定 (动态 Z 轴优化与各项同性网格)
Nx = 512; 
Lx = 60e-3;
Ny = Nx; Ly = Lx;
System_Offset = 2.03e-3;
z_target_dist = 16e-3; % 目标距离
f0 = 4.5e6;
c_water = 1480; 
c_board = 2430; 
density_water = 997;
density_board = 1100; 
lambda_water = c_water / f0;

dx = Lx / Nx; 
dy = dx; 
dz = dx; 
Lz_needed = 20e-3; 
Nz_min = ceil(Lz_needed / dz);
optimal_sizes = [128, 192, 216, 256, 300, 384, 512];
Nz = optimal_sizes(find(optimal_sizes >= Nz_min, 1));
Lz = Nz * dz;
x = (-Nx/2 : Nx/2-1) * dx;

fprintf('==================================================\n');
fprintf('网格分辨率: dx = dy = dz = %.4f mm\n', dx*1e3);
fprintf('每波长采样点 (PPW): %.2f (建议 > 3)\n', lambda_water/dx);
fprintf('优化后网格尺寸: %d x %d x %d (总节点数: %.1f 百万)\n', Nx, Ny, Nz, (Nx*Ny*Nz)/1e6);
fprintf('Z轴物理长度缩减至: %.2f mm\n', Lz*1e3);
fprintf('==================================================\n');

%% 2. 目标图案多孔支架
fprintf('目标图案定义\n');

[Y_grid, X_grid] = meshgrid(x, x);

strut_width = 1.0e-3;     
pore_size = 3.0e-3;        
pitch = strut_width + pore_size; 


mask_X = mod(X_grid + pitch/2, pitch) < strut_width;
mask_Y = mod(Y_grid + pitch/2, pitch) < strut_width;
scaffold_raw = mask_X | mask_Y;

target_radius = 15e-3;
circle_mask = (X_grid.^2 + Y_grid.^2) <= target_radius^2;
imag_target_raw = scaffold_raw & circle_mask;

imag_target = imgaussfilt(double(imag_target_raw), 0.5);

imag_target = imag_target / max(imag_target(:));

ROI_pixels = sum(imag_target(:) > 0.5);
fprintf('📦 多孔支架：直径 30mm, 线宽 1.0mm (ROI体素数: %d)\n', ROI_pixels);

% 导出至中转站
transport_dir = 'C:\Users\Zh89\Desktop\transport';
if ~exist(transport_dir, 'dir'), mkdir(transport_dir); end
export_path = fullfile(transport_dir, 'target_for_python.mat');
save(export_path, 'imag_target', 'Nx', 'Ny', 'Lx', 'lambda_water', 'z_target_dist');

figure(1); clf; set(gcf, 'Color', 'w');
imagesc(x*1e3, x*1e3, imag_target); axis image; colormap gray;
title('待打印的组织工程支架 (1.0mm 线宽)'); xlabel('mm'); ylabel('mm');

fprintf('\n==================================================\n');
fprintf('数据已导出至: %s\n', export_path);
fprintf('==================================================\n\n');
disp('按下【回车键 (Enter)】继续读取 Python 的结果...');
pause;
%% 3. IASA 迭代 (接收深度学习快递)
fprintf('运行 PANN-IASA 混合架构收敛...\n');
import_path = fullfile(transport_dir, 'dl_phase_init.mat');
if ~exist(import_path, 'file')
    error('❌ 中转站里没有找到 dl_phase_init.mat！请确认 Python 脚本是否成功运行。');
end
load(import_path, 'optimal_initial_phase');

pad_factor = 2; 
Nx_pad = Nx * pad_factor; 
Ny_pad = Ny * pad_factor;
Lx_pad = Lx * pad_factor;
dk_pad = 2 * pi / Lx_pad;
kx_pad = (-Nx_pad/2 : Nx_pad/2-1) * dk_pad;
[Kx_pad, Ky_pad] = meshgrid(kx_pad, kx_pad);
k_water = 2 * pi / lambda_water;
Kz_sq = k_water^2 - Kx_pad.^2 - Ky_pad.^2;
Kz_sq(Kz_sq < 0) = 0; 
H_forward = exp(1i * sqrt(Kz_sq) * z_target_dist); 
H_backward = exp(-1i * sqrt(Kz_sq) * z_target_dist); 

board_phase_pad = zeros(Nx_pad, Ny_pad);
board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = exp(1i * optimal_initial_phase);
target_pad = zeros(Nx_pad, Ny_pad);
target_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = imag_target;
weight_pad = target_pad * 1.5; 
mask_roi = (target_pad > 0.5);     
mask_dark = (target_pad < 0.5);    

epoch = 150; 
for i = 1:epoch
    U_source = zeros(Nx_pad, Ny_pad);
    center_phase = angle(board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny));
    U_source(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = 1.0 .* exp(1i * center_phase);
    
    A_source = fftshift(fft2(ifftshift(U_source)));
    A_target = A_source .* H_forward;
    U_target = fftshift(ifft2(ifftshift(A_target)));
    
    rec_amp = abs(U_target);
    peak_val = max(rec_amp(mask_roi)); 
    if peak_val == 0, peak_val = max(rec_amp(:)); end
    rec_amp_norm = rec_amp / peak_val;
    
    if i > 5
        beta = 0.6; 
        correction = (target_pad(mask_roi) ./ (rec_amp_norm(mask_roi) + 1e-6)) .^ beta;
        weight_pad(mask_roi) = weight_pad(mask_roi) .* correction;
        weight_pad(weight_pad > 10) = 10;
        weight_pad(mask_dark) = 0;
    end
    U_target_constrained = weight_pad .* exp(1i * angle(U_target));
    A_target_cons = fftshift(fft2(ifftshift(U_target_constrained)));
    A_source_cons = A_target_cons .* H_backward;
    U_source_new = fftshift(ifft2(ifftshift(A_source_cons)));
    
    board_phase_pad = U_source_new;
end
holo_phase = angle(board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny));

%% 4. 相位转厚度与体素化
phase_wrapped = mod(holo_phase, 2*pi); 
k_board_val = 2 * pi * f0 / c_board;
k_water_val = 2 * pi * f0 / c_water;
k_diff = abs(k_water_val - k_board_val); 
thickness_ideal = phase_wrapped / k_diff;

thickness_map = imgaussfilt(thickness_ideal, 0.2); 
min_base = 2 * dz; 
thickness_map = thickness_map + min_base;

net_num_board = round(thickness_map / dz);
actual_thickness = net_num_board * dz;

actual_phase_imparted = mod(actual_thickness * k_diff, 2*pi);
complex_diff_voxel = exp(1i * actual_phase_imparted) ./ exp(1i * phase_wrapped);
global_offset_voxel = angle(mean(complex_diff_voxel(:))); 
phase_aligned_voxel = angle(exp(1i * (actual_phase_imparted - global_offset_voxel)));

phase_error_voxel = abs(angle(exp(1i * (phase_aligned_voxel - phase_wrapped))));
mean_phase_error = mean(phase_error_voxel(:));
max_phase_error = max(phase_error_voxel(:));

%% 5. k-Wave 介质建模
fprintf('仿真环境与实体介质构建\n');
kgrid = kWaveGrid(Nx, dx, Ny, dy, Nz, dz);
medium.sound_speed = c_water * ones(Nx, Ny, Nz);
medium.density = density_water * ones(Nx, Ny, Nz);
medium.alpha_coeff = 0.002 * ones(Nx, Ny, Nz); 
medium.alpha_power = 1.5;
pml_size = 10;
source_z_idx = pml_size + 5;
z_board_stat_idx = source_z_idx + 2;

for i = 1:Nx
    for j = 1:Ny
        n_layers = net_num_board(i, j);
        if n_layers > 0
            z_start = z_board_stat_idx;
            z_end = z_board_stat_idx + n_layers - 1;
            medium.sound_speed(i, j, z_start:z_end) = c_board;
            medium.density(i, j, z_start:z_end) = density_board; 
        end
    end
end
thickest = max(net_num_board(:)) * dz;

%% 6. 时间与声源定义
cfl = 0.3;
t_end = (Lz * 1.5) / c_water; 
kgrid.makeTime(medium.sound_speed, cfl, t_end); 

source.p_mask = zeros(Nx, Ny, Nz);
source.p_mask(:, :, source_z_idx) = 1; 
t_vec = kgrid.t_array;
source_sig = sin(2 * pi * f0 * t_vec); 
ramp_pts = round(2 / f0 / kgrid.dt); 
window = [linspace(0,1,ramp_pts), ones(1, kgrid.Nt-ramp_pts)];
source.p = source_sig .* window;
source.p_mode = 'dirichlet';

%% 7. Sensor 放置
sensor.mask = zeros(Nx, Ny, Nz);
z_board_exit_idx = z_board_stat_idx + round(thickest/dz);
target_plane_idx = z_board_exit_idx + round(z_target_dist / dz);
scan_range_idx = round(3e-3 / dz); 
z_scan_start = target_plane_idx - scan_range_idx;
z_scan_end = target_plane_idx + scan_range_idx;
if z_scan_end > Nz - pml_size, z_scan_end = Nz - pml_size; end
sensor.mask(:, :, z_scan_start:z_scan_end) = 1;

sensor.record = {'p_max'}; 
sensor.record_start_index = kgrid.Nt - round(3/f0/kgrid.dt);

%% 8. 仿真开始
fprintf('k-Wave 仿真开始\n');
input_args = {'PMLInside', true, 'PMLSize', 10, 'PlotPML', false, 'PlotSim', false, 'DataCast', 'gpuArray-single'};
try
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
catch
    disp('GPU 失败，切换 CPU...');
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{1:end-2});
end

%% 9. 数据处理与自动 Z-Scan
p_amp = gather(sensor_data.p_max); 
p_field_3d = zeros(Nx, Ny, Nz);
mask_indices = find(sensor.mask);
p_field_3d(mask_indices) = p_amp; 

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
    A = (A - min(A(:))) / (max(A(:)) - min(A(:)));
    A_mean = mean(A(:));
    
    numerator = sum(sum((R - R_mean) .* (A - A_mean)));
    denominator = sqrt(sum(sum((R - R_mean).^2)) * sum(sum((A - A_mean).^2)));
    val_corr = numerator / denominator;
    
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

%% 12. 原生 3D FDTD 自适应寻优引擎 (粗细双阶 + 能量启发式剪枝)
fprintf('\n========================================\n');
fprintf('🚀 启动 3D 非均匀介质【粗细双阶自适应】寻优引擎...\n');
p_3d_abs = abs(p_field_3d); 
focal_slice_abs = p_3d_abs(:, :, best_idx_global);
roi_mask = (imag_target > 0.5);
median_roi_p = median(focal_slice_abs(roi_mask)); 

rho_resin = 1100;  c_resin = 2500;  Cp_resin_liq = 1800;  k_resin_liq = 0.15; 
rho_water = 997;   c_water = 1480;  Cp_water = 4180;      k_water = 0.6; 
alpha_np_resin_liq = (1.5 / 8.686) * 100 * (f0/1e6)^1.5; 
alpha_np_water = 0.02; 
resin_z_start = z_board_exit_idx + 1;
cavitation_limit = 2.0e6;

E_a = 9.5e4; A_freq = 8.0e15; R_gas = 8.314;
inv_dx2 = 1 / (dx^2);
max_diff = max(k_water/(rho_water*Cp_water), k_resin_liq/(rho_resin*Cp_resin_liq));
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
        fprintf('\n🟢 [第一阶段: 全局粗扫] 寻找物理能量甜点区...\n');
        P_list = (1.2 : 0.2 : 1.8) * 1e6;   
        E_list = 0.15 : 0.10 : 0.45;        
        C_list = 0.10 : 0.10 : 0.30;        
    else
        fprintf('\n🔴 [第二阶段: 局部微调] 围绕粗搜最优点 (P=%.2f, E=%.2f, C=%.2f) 进行极限压榨...\n', ...
            best_coarse.P/1e6, best_coarse.E, best_coarse.C);
        P_list = (best_coarse.P - 0.1e6) : 0.05e6 : (best_coarse.P + 0.1e6);
        E_list = max(0.10, best_coarse.E - 0.05) : 0.02 : (best_coarse.E + 0.05);
        C_list = max(0.05, best_coarse.C - 0.05) : 0.05 : (best_coarse.C + 0.05);
    end
    
    [Pg, Eg, Cg] = ndgrid(P_list, E_list, C_list);
    params_all = [Pg(:), Eg(:), Cg(:)];
    
    energy_index = (params_all(:,1)/1e6).^2 .* params_all(:,2);
    valid_mask = (energy_index >= 0.3) & (energy_index <= 1.2);
    params_valid = params_all(valid_mask, :);
    params_valid = sortrows(params_valid, 1);
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
            
            k_3d = k_water * ones(Nx, Ny, Nz, 'single');
            k_3d(:, :, resin_z_start:end) = k_resin_liq;
            rho_Cp_3d = (rho_water * Cp_water) * ones(Nx, Ny, Nz, 'single');
            rho_Cp_3d(:, :, resin_z_start:end) = rho_resin * Cp_resin_liq;
            
            Q_heat_3d = zeros(Nx, Ny, Nz, 'single');
            I_3d_resin = single((p_3d_scaled(:, :, resin_z_start:end).^2) ./ (2 * rho_resin * c_resin));
            Q_heat_3d(:, :, resin_z_start:end) = 2 * alpha_np_resin_liq * I_3d_resin;
            I_3d_water = single((p_3d_scaled(:, :, 1:resin_z_start-1).^2) ./ (2 * rho_water * c_water));
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
            k_mid_x = (k_3d_gpu(1:end-1,:,:) + k_3d_gpu(2:end,:,:)) / 2;
            div_flux_x = diff([zeros(1,Ny,z_crop_len,'single','gpuArray'); k_mid_x .* T_diff_x; zeros(1,Ny,z_crop_len,'single','gpuArray')], 1, 1);
            
            T_diff_y = diff(T_3d_gpu, 1, 2);
            k_mid_y = (k_3d_gpu(:,1:end-1,:) + k_3d_gpu(:,2:end,:)) / 2;
            div_flux_y = diff([zeros(Nx,1,z_crop_len,'single','gpuArray'), k_mid_y .* T_diff_y, zeros(Nx,1,z_crop_len,'single','gpuArray')], 1, 2);
            
            T_diff_z = diff(T_3d_gpu, 1, 3);
            k_mid_z = (k_3d_gpu(:,:,1:end-1) + k_3d_gpu(:,:,2:end)) / 2;
            div_flux_z = diff(cat(3, zeros(Nx,Ny,1,'single','gpuArray'), k_mid_z .* T_diff_z, zeros(Nx,Ny,1,'single','gpuArray')), 1, 3);

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
        
        fprintf('  [%02d/%02d] P=%.2fMPa, 照=%.2fs, 冷=%.2fs | Max Temp: %4.1f°C | IoU: %.4f\n', ...
            i, num_tests, p_target/1e6, t_exp, t_cool, max(T_max_history_tmp), current_IoU);
            
        if current_IoU > best_IoU_global
            best_IoU_global = current_IoU;
            best_record.p_target = p_target; best_record.t_exp = t_exp; best_record.t_cool = t_cool;
            best_record.T_focal_2d = gather(double(T_3d_gpu(:, :, best_idx_crop)));
            best_record.Q_focal_2d = gather(double(Q_heat_3d_gpu(:, :, best_idx_crop)));
            best_record.Omega_final_2d = Omega_tmp;
            best_record.T_max_history = T_max_history_tmp;
            best_record.Nt_th = Nt_th; best_record.p_3d_scaled = p_3d_scaled;
            if phase == 1
                best_coarse.P = p_target; best_coarse.E = t_exp; best_coarse.C = t_cool;
            end
        end
    end
end

fprintf('\n🏆 全局自适应寻优彻底结束！最终【天命参数】出炉：\n');
fprintf('   👑 最优定标声压: %.2f MPa\n', best_record.p_target / 1e6);
fprintf('   👑 最优照射时间: %.2f 秒\n', best_record.t_exp);
fprintf('   👑 最优冷却时间: %.2f 秒\n', best_record.t_cool);
fprintf('   🔥 极限压榨 IoU: %.4f\n', best_IoU_global);

% 覆盖全局变量
target_median_pressure = best_record.p_target;
exposure_time = best_record.t_exp; cooling_time = best_record.t_cool;
T_focal_2d = best_record.T_focal_2d; Q_focal_2d = best_record.Q_focal_2d;
Omega_final_2d = best_record.Omega_final_2d; T_max_history = best_record.T_max_history;
Nt_th = best_record.Nt_th; p_3d_scaled = best_record.p_3d_scaled;
t_axis = (1:Nt_th) * dt_th; T_max_real = max(T_max_history);

%% 13. 基于真实动力学的全体系形貌量化分析
Thermal_Dose_Threshold = 1.0; 
cured_mask_2d = Omega_final_2d >= Thermal_Dose_Threshold;
R_binary = imag_target > 0.5;
ROI_pixels = sum(R_binary(:)); 

cured_coverage = (sum(cured_mask_2d(:) & R_binary(:)) / ROI_pixels) * 100; 
if cured_coverage > 100, cured_coverage = 100; end

% --- 1. 形貌学量化指标 (Morphological Metrics) ---
intersection = R_binary & cured_mask_2d;
union_mask = R_binary | cured_mask_2d;

IoU = sum(intersection(:)) / (sum(union_mask(:)) + 1e-8);
Dice = 2 * sum(intersection(:)) / (sum(R_binary(:)) + sum(cured_mask_2d(:)) + 1e-8);

% 过固化 (Over-cure): 固化了但不该固化的地方占目标面积的比例
over_cure_ratio = sum(cured_mask_2d(:) & ~R_binary(:)) / ROI_pixels;
% 欠固化 (Under-cure): 该固化但没固化的地方占目标面积的比例
under_cure_ratio = sum(~cured_mask_2d(:) & R_binary(:)) / ROI_pixels;

% --- 2. 声场学量化指标 (Acoustic Field Metrics) ---
% 🚀 【修复报错】：先从 3D 声压场中提取当前焦面的 2D 声压，再进行计算
p_focal_scaled = gather(p_3d_scaled(:, :, best_idx_global)); 

p_focal_norm = p_focal_scaled / max(p_focal_scaled(:));
target_norm = imag_target / max(imag_target(:));

% NMSE (归一化均方误差)
NMSE = sum((target_norm(:) - p_focal_norm(:)).^2) / sum(target_norm(:).^2);

% SSIM (结构相似度)
% MATLAB 自带 ssim 函数
SSIM_val = ssim(double(p_focal_norm), double(target_norm));

% Energy Efficiency (声能聚焦效率)
% 定义为：落入目标掩膜区域的声压平方和 / 整个焦面的声压平方和
Energy_Efficiency = sum(p_focal_norm(R_binary).^2) / sum(p_focal_norm(:).^2);
%% 14. 终极可视化全景仪表盘 (全参数调试版)
y = x; 
figure(88); clf; set(gcf, 'Position', [100, 100, 1400, 500], 'Color', 'w');
num_snapshots = 5;
snapshot_steps = round(linspace(1, Nt_th, num_snapshots));

subplot(2, 1, 2);
plot(t_axis, T_max_history, 'r-', 'LineWidth', 2); hold on;
yline(65, 'k--', 'LineWidth', 1.5, 'Label', '65°C 参考线'); 
grid on; set(gca, 'Color', 'w');
xlabel('时间 (s)'); ylabel('最高温度 (°C)');

figure('Position', [30 30 1500 1000], 'Color', 'w');
subplot(3, 5, 1);
imagesc(x*1e3, y*1e3, imag_target); axis image; colormap(gca, gray);
title('目标图案'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 2);
imagesc(x*1e3, y*1e3, phase_wrapped); axis image; colormap(gca, hsv); colorbar;
title('全息相位'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 3);
imagesc(x*1e3, y*1e3, phase_aligned_voxel); axis image; colormap(gca, hsv); colorbar;
title('实际体素相位'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 4);
surf(x*1e3, y*1e3, actual_thickness*1e3); view(2); shading interp; axis image; colorbar;
title('透镜厚度 (mm)'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 5);
imagesc(x*1e3, y*1e3, Omega_final_2d); axis image; colormap(gca, turbo); colorbar;
caxis([0, max(2.0, max(Omega_final_2d(:)))]); 
title('热剂量 Omega'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 6);
imagesc(x*1e3, y*1e3, Q_focal_2d / 1e6); axis image; colormap(gca, hot); colorbar;
title('物理产热率 (MW/m^3)'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 7);
p_focal_scaled = gather(p_3d_scaled(:, :, best_idx_global));
imagesc(x*1e3, y*1e3, p_focal_scaled/1e6); axis image; colormap(gca, jet); colorbar;
title('焦面饱和声压 (MPa)'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 8);
imagesc(x*1e3, y*1e3, cured_mask_2d); axis image;
colormap(gca, [1 1 1; 0.1 0.1 0.3]); 
title(sprintf('最终固化形貌 (IoU: %.4f)', IoU)); xlabel('mm'); ylabel('mm');

subplot(3, 5, 9);
imagesc(x*1e3, y*1e3, T_focal_2d); axis image; colormap(gca, hot); colorbar;
caxis([25, max(65, min(T_max_real, 80))]);
title(sprintf('极限温度 %.1f°C', T_max_real)); xlabel('mm'); ylabel('mm');

subplot(3, 5, 10);
plot(metrics_z, metrics_corr, 'b-', 'LineWidth', 1.5); hold on; 
plot(actual_z_dist_mm, best_corr, 'ro', 'MarkerSize', 10);
grid on; set(gca, 'Color', 'w');
title('Z-Scan 寻优'); xlabel('Z 偏移 (mm)'); ylabel('Correlation');

subplot(3, 5, [11 12 13]);
center = round(Nx/2);
plot(x*1e3, imag_target(center, :), 'k--', 'LineWidth', 2); hold on;
plot(x*1e3, p_focal_scaled(center, :)/max(p_focal_scaled(:)), 'r-', 'LineWidth', 1.5);
grid on; set(gca, 'Color', 'w');
title('中心剖面强度对比'); xlabel('mm'); ylabel('归一化幅值'); legend('目标', '饱和声压分布');

subplot(3, 5, [14 15]);
[X_surf, Y_surf] = meshgrid(x*1e3, y*1e3);
surf(X_surf, Y_surf, p_focal_scaled/1e6); shading interp; colormap(gca, jet); colorbar;
set(gca, 'Color', 'w');
title('3D焦面空化饱和声压场 (MPa)'); xlabel('mm'); ylabel('mm'); zlabel('MPa');


%% 15. 输出报告
fprintf('\n========================================\n');
fprintf('HDSP 严谨物理仿真报告 (全体系量化版)\n');
fprintf('========================================\n');
fprintf('【仿真系统配置】\n');
fprintf('  超声频率: %.2f MHz  |  透镜孔径 (OD): %.1f mm\n', f0/1e6, Lx*1e3);
fprintf('  网格分辨率: %.2f μm  |  节点数: %.1fM\n', dx*1e6, (Nx*Ny*Nz)/1e6);
fprintf('----------------------------------------\n');
fprintf('【声场聚焦质量评估 (Acoustic Field)】\n');
fprintf('  最佳焦面偏移: %.2f mm\n', actual_z_dist_mm);
fprintf('  Pearson 相关系数 (PCC): %.4f (越大越好)\n', best_corr);
fprintf('  结构相似度 (SSIM): %.4f (越大越好)\n', SSIM_val);
fprintf('  归一化均方误差 (NMSE): %.4f (越小越好)\n', NMSE);
fprintf('  声能聚焦效率 (EE): %.2f%% (越高代表散斑旁瓣越少)\n', Energy_Efficiency * 100);
fprintf('----------------------------------------\n');
fprintf('【热动力学与固化评估 (Thermal & Curing)】\n');
fprintf('  最优曝光组合: %.2f MPa + %.2f s (冷却 %.2fs)\n', target_median_pressure/1e6, exposure_time, cooling_time);
fprintf('  极限温度: %.1f°C\n', T_max_real);
fprintf('  目标有效覆盖率: %.1f%%\n', cured_coverage);
fprintf('  交并比 (IoU): %.4f\n', IoU);
fprintf('  Dice 相似系数: %.4f\n', Dice);
fprintf('  过固化率 (Over-cure): %.1f%% (热晕染指标)\n', over_cure_ratio * 100);
fprintf('  欠固化率 (Under-cure): %.1f%% (未反应指标)\n', under_cure_ratio * 100);
fprintf('========================================\n');
fprintf('========================================\n');
%% 16. 现实级连续物理渲染 (Photo-realistic Rendering，不改变底层量化数据)
fprintf('\n========================================\n');
fprintf('🎨 启动连续介质物理渲染引擎...\n');

figure(100); clf; 
set(gcf, 'Color', 'w', 'Position', [300, 200, 700, 700], 'Name', '真实打印形貌预测');

% 1. 亚像素级物理还原：将连续的热剂量场提升 4 倍分辨率 (模拟真实的连续空间)
[X_hi, Y_hi] = meshgrid(linspace(min(x), max(x), Nx*4)*1e3);
% 使用 cubic (三次插值) 是因为它最符合真实世界热传导的平滑梯度特性
Omega_hi = interp2(x*1e3, y*1e3, Omega_final_2d, X_hi, Y_hi, 'cubic');

% 2. 在连续的高分辨率场中执行阿伦尼乌斯绝对阈值截断
cured_hi = double(Omega_hi >= Thermal_Dose_Threshold);

% 3. 模拟真实液态树脂固化时的“微小表面张力” (极微弱的边缘圆角化)
cured_hi_render = imgaussfilt(cured_hi, 1.5);

% 4. 引入光影材质系统，渲染 3D 实体质感
% 构造一个微小的厚度，让它看起来像个实物
Z_hi = cured_hi_render * 0.5; 

surf(X_hi, Y_hi, Z_hi, 'EdgeColor', 'none', 'FaceColor', [0.15, 0.25, 0.45]);
view(0, 90); 

camlight('headlight'); 
camlight('left');
lighting gouraud;
material dull; 

axis image; 
set(gca, 'Color', 'w', 'XColor', 'k', 'YColor', 'k');
title(sprintf('真实物理打印形貌预测 (连续介质还原)\n底层严格评估 IoU: %.4f', IoU), 'FontSize', 14, 'FontWeight', 'bold');
xlabel('物理尺度 X (mm)'); ylabel('物理尺度 Y (mm)');
grid off;

fprintf('✅ 渲染完成！请查看 Figure 100。\n');
fprintf('========================================\n');

reset(gpuDevice); % 强制清空 GPU 显存底层垃圾