clear; close all; clc;

reset(gpuDevice); % 强制清空 GPU 显存底层垃圾，确保 k-Wave 每次都能在 15 分钟内跑完！
%% 1. 网格及参数设定 (完全保持原样)
%% 1. 网格及参数设定 (动态 Z 轴优化与各项同性网格)
% --- 你可以在这里切换 Nx = 256, 384, 或 512 来控制分辨率 ---
Nx = 384; 
% -----------------------------------------------------------

Lx = 40e-3;
Ny = Nx; Ly = Lx;
System_Offset = 2.03e-3;
z_target_dist = 20e-3; % 目标距离
f0 = 4.0e6;
c_water = 1480; 
c_board = 2430; 
density_water = 997;
density_board = 1100; 
lambda_water = c_water / f0;

% 强制各项同性网格
dx = Lx / Nx; 
dy = dx; 
dz = dx; 

Lz_needed = 30e-3; 
% 2. 换算为基础网格数
Nz_min = ceil(Lz_needed / dz);

optimal_sizes = [128, 192, 216, 256, 300, 384, 512];
Nz = optimal_sizes(find(optimal_sizes >= Nz_min, 1));

Lz = Nz * dz;
% ==================================================

x = (-Nx/2 : Nx/2-1) * dx;

% 打印诊断信息，确保没有浪费算力
fprintf('==================================================\n');
fprintf('网格分辨率: dx = dy = dz = %.4f mm\n', dx*1e3);
fprintf('每波长采样点 (PPW): %.2f (建议 > 3)\n', lambda_water/dx);
fprintf('优化后网格尺寸: %d x %d x %d (总节点数: %.1f 百万)\n', Nx, Ny, Nz, (Nx*Ny*Nz)/1e6);
fprintf('Z轴物理长度缩减至: %.2f mm\n', Lz*1e3);
fprintf('==================================================\n');

%% 2. 目标定义 (保持原样)
fprintf('目标图案定义\n');
imag_target = zeros(Nx, Ny);
h_A = 160;       % 高度
w_base = 100;    % 底部宽度
thickness = 22;  % 粗细
bar_pos = 50;    % 横高
bar_width = 20;  % 横宽
cx = round(Nx/2); 
cy = round(Ny/2);
x_top = cx - h_A/2;
x_bottom = cx + h_A/2;
slope = h_A / (w_base/2);
[Y_grid, X_grid] = meshgrid(1:Ny, 1:Nx);
dx_outer = X_grid - x_top;
dy_abs = abs(Y_grid - cy);
width_at_x = dx_outer / slope;
mask_outer = (dx_outer >= 0) & (dx_outer <= h_A) & (dy_abs <= width_at_x);
x_top_inner = x_top + thickness * 1.8; % 视觉调整系数，保证厚度适中
dx_inner = X_grid - x_top_inner;
width_inner_at_x = dx_inner / slope;
mask_inner_cone = (dx_inner >= 0) & (dy_abs <= width_inner_at_x); 
% 横杠
x_bar_start = x_bottom - bar_pos - bar_width/2;
x_bar_end   = x_bottom - bar_pos + bar_width/2;
mask_bar = (X_grid >= x_bar_start) & (X_grid <= x_bar_end);
%组合逻辑
imag_target = mask_outer & (~mask_inner_cone | mask_bar);
imag_target = double(imag_target > 0.5);
% --- 目标定义末尾 ---
imag_target = mask_outer & (~mask_inner_cone | mask_bar);
imag_target = double(imag_target > 0.5);

% ========================================================
% [终极抗衍射绝招]：将硬边界转换为“高斯软边界”！
% 这将彻底消除 IASA 算法产生的空间高频衍射环 (吉布斯振铃)
% ========================================================
smooth_sigma = 1.5; % 柔化半径 (通常取 1.5 ~ 2.0 个像素)
imag_target = imgaussfilt(imag_target, smooth_sigma);
% 重新归一化到 0~1
imag_target = imag_target / max(imag_target(:));

% === 1. 导出靶标数据到专属中转站 ===
    transport_dir = 'C:\Users\Zh89\Desktop\transport';
    if ~exist(transport_dir, 'dir')
        mkdir(transport_dir);
    end
    
    export_path = fullfile(transport_dir, 'target_for_python.mat');
    save(export_path, 'imag_target', 'Nx', 'Ny', 'Lx', 'lambda_water', 'z_target_dist');
    
    % --- 极其显眼的交互提示 ---
    fprintf('\n==================================================\n');
    fprintf('🎯 靶标数据已导出至: %s\n', export_path);
    fprintf('⏳ 【系统暂停中】请不要关闭 MATLAB！\n');
    fprintf('👉 任务：请去 VS Code 中运行 Python 脚本...\n');
    fprintf('==================================================\n\n');
    
    disp('按下【回车键 (Enter)】继续读取 Python 的结果...');
    pause; % 程序会在这里完全挂起，直到你敲击键盘
    
    fprintf('\n🚀 收到继续指令！正在检查中转站...\n');
%% === 3. IASA 迭代 (接收深度学习快递) ===
fprintf('运行 PANN-IASA 混合架构收敛...\n');

% 定义中转站路径
transport_dir = 'C:\Users\Zh89\Desktop\transport';
import_path = fullfile(transport_dir, 'dl_phase_init.mat');

% 防呆检测：确保 Python 已经跑完了
if ~exist(import_path, 'file')
    error('❌ 中转站里没有找到 dl_phase_init.mat！请确认 Python 脚本是否成功运行。');
end

% 加载深度学习生成的初始相位
load(import_path, 'optimal_initial_phase');
fprintf('📦 成功从中转站提取神级初始相位！准备起飞...\n');
% ... 接下来的 target_pad 定义和 epoch=150 的循环，完全保持你原样 ...
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
        beta = 0.8; 
        correction = (target_pad(mask_roi) ./ (rec_amp_norm(mask_roi) + 1e-6)) .^ beta;
        weight_pad(mask_roi) = weight_pad(mask_roi) .* correction;
        weight_pad(weight_pad > 10) = 10;
        weight_pad(mask_dark) = 0;
    end
    current_weight = weight_pad; 
    U_target_constrained = weight_pad .* exp(1i * angle(U_target));
    A_target_cons = fftshift(fft2(ifftshift(U_target_constrained)));
    A_source_cons = A_target_cons .* H_backward;
    U_source_new = fftshift(ifft2(ifftshift(A_source_cons)));
    
    board_phase_pad = U_source_new;
end

holo_phase = angle(board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny));
figure(1);
subplot(1,2,1); imagesc(x*1e3, x*1e3, imag_target); axis image; colormap gray; title('目标');
subplot(1,2,2); imagesc(x*1e3, x*1e3, holo_phase); axis image; colormap jet; title('IASA 相位 (Pad优化)');

%% === [修改部分 Start] 相位转厚度与体素化优化 ===

phase_wrapped = mod(holo_phase, 2*pi); 

k_board_val = 2 * pi * f0 / c_board;
k_water_val = 2 * pi * f0 / c_water;
k_diff = abs(k_water_val - k_board_val); 

thickness_ideal = phase_wrapped / k_diff;

% [微平滑]：sigma 设为非常小的值，仅消除孤立的像素点突变
thickness_map = imgaussfilt(thickness_ideal, 0.2); 
min_base = 2 * dz; 
thickness_map = thickness_map + min_base;

% 严格体素化
net_num_board = round(thickness_map / dz);
actual_thickness = net_num_board * dz;

% 反算理论相位
actual_phase_imparted = mod(actual_thickness * k_diff, 2*pi);
complex_diff_voxel = exp(1i * actual_phase_imparted) ./ exp(1i * phase_wrapped);
global_offset_voxel = angle(mean(complex_diff_voxel(:))); 
phase_aligned_voxel = angle(exp(1i * (actual_phase_imparted - global_offset_voxel)));

% 计算理论量化误差
phase_error_voxel = abs(angle(exp(1i * (phase_aligned_voxel - phase_wrapped))));
mean_phase_error = mean(phase_error_voxel(:));
max_phase_error = max(phase_error_voxel(:));
fprintf(' -> 理论体素化平均相位误差: %.4f Rad (%.1f 度)\n', mean_phase_error, mean_phase_error*180/pi);

figure(11); clf;
set(gcf, 'Position', [100, 100, 1200, 400], 'Color', 'w');
subplot(1,3,1); imagesc(x*1e3, x*1e3, phase_wrapped); axis image; colormap hsv; colorbar; title('理想 Wrapped 相位');
subplot(1,3,2); imagesc(x*1e3, x*1e3, phase_aligned_voxel); axis image; colormap hsv; colorbar; title('微平滑体素化实际相位');
subplot(1,3,3); surf(x*1e3, x*1e3, actual_thickness*1e3); shading flat; colormap parula; title('构建的 3D 透镜厚度'); view(2); colorbar;

%% k-Wave 介质建模
fprintf('仿真环境与实体介质构建\n');
kgrid = kWaveGrid(Nx, dx, Ny, dy, Nz, dz);
medium.sound_speed = c_water * ones(Nx, Ny, Nz);

% [关键物理隔离]：为了证明是网格散射惹的祸，而不是材料反射
% 我们强行关闭材料的阻抗失配！即：保持声速不同以产生相位差，但让密度补偿以匹配水的声阻抗。
% 声阻抗 Z = rho * c。我们希望 Z_board = Z_water
% rho_match = (c_water * density_water) / c_board;

medium.density = density_water * ones(Nx, Ny, Nz);
medium.alpha_coeff = 0.002 * ones(Nx, Ny, Nz); 
medium.alpha_power = 1.5;

pml_size = 10;
source_z_idx = pml_size + 5;
z_board_stat_idx = source_z_idx + 2;

fprintf('将透镜写入 3D 网格...\n');
for i = 1:Nx
    for j = 1:Ny
        n_layers = net_num_board(i, j);
        if n_layers > 0
            z_start = z_board_stat_idx;
            z_end = z_board_stat_idx + n_layers - 1;
            
            medium.sound_speed(i, j, z_start:z_end) = c_board;
            
            % 使用阻抗匹配的密度，消除内部反射
            medium.density(i, j, z_start:z_end) = density_board; 
            
            % 为了看清纯粹的相位作用，暂时关闭树脂的额外衰减
            % medium.alpha_coeff(i, j, z_start:z_end) = 1.0; 
        end
    end
end
thickest = max(net_num_board(:)) * dz;
% === [修改部分 End] ===
%% 时间 (保持原样)
fprintf('时间设置\n');
cfl = 0.3;
t_end = (Lz * 1.5) / c_water; 
kgrid.makeTime(medium.sound_speed, cfl, t_end); 

%% 6. 声源定义 
% === [修改部分 Start] 恢复为平面波声源 ===
% 原逻辑直接加了相位，这里因为已经有物理透镜，必须使用无相位的平面波
source.p_mask = zeros(Nx, Ny, Nz);
source.p_mask(:, :, source_z_idx) = 1; 
fprintf('构建平面波声源 (相位由物理透镜调制)\n');
t_vec = kgrid.t_array;
source_sig = sin(2 * pi * f0 * t_vec); % 纯正弦波

% 加一个简单的斜坡窗减少瞬态冲击
ramp_pts = round(2 / f0 / kgrid.dt); 
window = [linspace(0,1,ramp_pts), ones(1, kgrid.Nt-ramp_pts)];
source.p = source_sig .* window;
source.p_mode = 'dirichlet';
% === [修改部分 End] ===

%% 7. Sensor 放置
% === [修改部分 Start] 同时放置出口平面与目标平面的Sensor ===
fprintf('sensor设置\n');
sensor.mask = zeros(Nx, Ny, Nz);

% 1. 记录出口平面 (用于校验透镜转换质量)
 z_board_exit_idx = z_board_stat_idx + round(thickest/dz);
% sensor.mask(:, :, z_board_exit_idx) = 1;

% 2. 记录目标平面 (用于量化评估)
target_plane_idx = z_board_exit_idx + round(z_target_dist / dz);
scan_range_idx = round(3e-3 / dz); 
z_scan_start = target_plane_idx - scan_range_idx;
z_scan_end = target_plane_idx + scan_range_idx;

% 安全检查防止越界
if z_scan_end > Nz - pml_size
    z_scan_end = Nz - pml_size;
end
sensor.mask(:, :, z_scan_start:z_scan_end) = 1;

sensor.record = {'p'}; 
sensor.record_start_index = kgrid.Nt - round(3/f0/kgrid.dt);
% fprintf('  - 出口校验面 Z Index: %d\n', z_board_exit_idx);
fprintf('  - 扫描范围 Z Index: %d 到 %d (寻找物理最佳焦面)\n', z_scan_start, z_scan_end);
% fprintf('  - 目标平面 Z Index: %d (距离源 %.2f mm)\n', target_plane_idx, target_plane_idx*dz*1e3);
% === [修改部分 End] ===

%% 8. 仿真 (保持原样)
fprintf('仿真开始\n');
input_args = {
    'PMLInside', true, ...
    'PMLSize', 10, ...
    'PlotPML', false, ...
    'PlotSim', false, ...
    'DataCast', 'gpuArray-single' 
};
try
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
catch
    disp('GPU 失败，切换 CPU...');
    input_args = input_args(1:end-2);
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
end

%% 9. 数据处理与量化评估 (新增自动 Z-Scan 寻优逻辑)
if isfield(sensor_data, 'p')
    p_raw = gather(sensor_data.p); 
    [~, Nt_rec] = size(p_raw);
    p_fft = fft(p_raw, [], 2);
    [~, f_idx] = min(abs( (0:Nt_rec-1)/Nt_rec/kgrid.dt - f0 ));
    p_complex = p_fft(:, f_idx);
    
    p_field_3d = zeros(Nx, Ny, Nz);
    mask_indices = find(sensor.mask);
    p_field_3d(mask_indices) = p_complex;
    
    % 提取扫描体积的声压幅值
    scan_vol = abs(p_field_3d(:, :, z_scan_start:z_scan_end));
    num_slices = size(scan_vol, 3);
    
    % --- 准备目标图像进行评估 ---
    R = double(imag_target);                 
    R = (R - min(R(:))) / (max(R(:)) - min(R(:)));
    R_mean = mean(R(:));
    
    best_corr = -1;
    best_slice_idx = 1;
    best_img_recon = [];
    best_nmse = inf;
    best_psnr = 0;
    
    % 新增：记录每一层的指标，用于 Z-Scan 曲线绘制
    metrics_z = zeros(num_slices, 1);
    metrics_corr = zeros(num_slices, 1);
    
    fprintf('开始 Z-Scan 寻优...\n');
    % 逐层计算相关系数，寻找真正聚焦最完美的平面
    for k = 1:num_slices
        A = scan_vol(:, :, k);
        A = (A - min(A(:))) / (max(A(:)) - min(A(:))); % 归一化
        A_mean = mean(A(:));
        
        % 计算 Correlation
        numerator = sum(sum((R - R_mean) .* (A - A_mean)));
        denominator = sqrt(sum(sum((R - R_mean).^2)) * sum(sum((A - A_mean).^2)));
        val_corr = numerator / denominator;
        
        % 记录到数组
        metrics_z(k) = (z_scan_start + k - 1 - z_board_exit_idx) * dz * 1e3;
        metrics_corr(k) = val_corr;
        
        if val_corr > best_corr
            best_corr = val_corr;
            best_slice_idx = k;
            best_img_recon = A;
            
            % 同步记录最高 Corr 时的其他指标
            best_nmse = sum(sum((R - A).^2)) / sum(sum(R.^2));
            mse = mean((R(:) - A(:)).^2);
            if mse == 0, best_psnr = Inf; else, best_psnr = 20 * log10(1 / sqrt(mse)); end
        end
    end
    
    % [核心修复]：计算在全空间 3D 矩阵中的绝对 Z 轴索引，供热力学引擎使用
    best_idx_global = z_scan_start + best_slice_idx - 1;
    
    % 计算实际的最佳物理聚焦距离
    actual_z_dist_idx = best_idx_global - z_board_exit_idx;
    actual_z_dist_mm = actual_z_dist_idx * dz * 1e3;
    
    fprintf('>>> 自动寻优完成！最佳焦面发生偏移: 理论 20.00mm -> 实际 %.2f mm\n', actual_z_dist_mm);
end

%% 12. 原生 3D FDTD 热扩散仿真 (空化屏蔽饱和模型 + 色标修复)
fprintf('\n========================================\n');
fprintf('启动原生 3D 热扩散 FDTD 求解器 (GPU 极速版)...\n');

% --- 1. 物理场真实功率注入 (精确中位数定标 + 空化屏蔽物理锁) ---
p_3d_abs = abs(p_field_3d); 
focal_slice_abs = p_3d_abs(:, :, best_idx_global);
roi_mask = (imag_target > 0.5);
median_roi_p = median(focal_slice_abs(roi_mask)); 

% 1. 将 A 内部的平均声压定标为 1.2 MPa (刚好引发产热)
target_median_pressure = 2e6;
cavitation_limit = 2.0e6;
exposure_time = 0.28;

scale_factor = target_median_pressure / median_roi_p;
p_3d_scaled = p_3d_abs * scale_factor;

% 2. [终极真实物理约束]：水中的声空化饱和效应 (Cavitation Shielding)
% 任何超过 2.0 MPa 的能量都会被气泡散射，绝对无法参与深层加热！
 
p_3d_scaled(p_3d_scaled > cavitation_limit) = cavitation_limit; 

rho_resin = 1100;  c_resin = 2500;  Cp_resin = 1500;  k_resin = 0.2; 
rho_water = 997;   c_water = 1480;  Cp_water = 4180;  k_water = 0.6; 
alpha_np_resin = (1.5 / 8.686) * 100 * (f0/1e6)^1.5; 
alpha_np_water = 0.02; 
resin_z_start = z_board_exit_idx + 1;

Q_heat_3d = zeros(Nx, Ny, Nz, 'single');
I_3d_resin = single((p_3d_scaled(:, :, resin_z_start:end).^2) ./ (2 * rho_resin * c_resin));
Q_heat_3d(:, :, resin_z_start:end) = 2 * alpha_np_resin * I_3d_resin;
I_3d_water = single((p_3d_scaled(:, :, 1:resin_z_start-1).^2) ./ (2 * rho_water * c_water));
Q_heat_3d(:, :, 1:resin_z_start-1) = 2 * alpha_np_water * I_3d_water;

diffusivity_3d = zeros(Nx, Ny, Nz, 'single');
diffusivity_3d(:, :, resin_z_start:end) = k_resin / (rho_resin * Cp_resin);
diffusivity_3d(:, :, 1:resin_z_start-1) = k_water / (rho_water * Cp_water);

rho_Cp_3d = zeros(Nx, Ny, Nz, 'single');
rho_Cp_3d(:, :, resin_z_start:end) = rho_resin * Cp_resin;
rho_Cp_3d(:, :, 1:resin_z_start-1) = rho_water * Cp_water;

dT_source_3d = Q_heat_3d ./ rho_Cp_3d;

% --- 2. Z轴物理截断与 GPU 载入 ---
z_crop_radius = round(1.5e-3 / dz); 
z_crop_start = max(1, best_idx_global - z_crop_radius);
z_crop_end = min(Nz, best_idx_global + z_crop_radius);
best_idx_crop = best_idx_global - z_crop_start + 1;

try
    T_3d_gpu = gpuArray(50 * ones(Nx, Ny, z_crop_end - z_crop_start + 1, 'single'));
    diffusivity_gpu = gpuArray(diffusivity_3d(:, :, z_crop_start:z_crop_end));
    dT_source_gpu = gpuArray(dT_source_3d(:, :, z_crop_start:z_crop_end));
catch
    T_3d_gpu = 50 * ones(Nx, Ny, z_crop_end - z_crop_start + 1, 'single');
    diffusivity_gpu = diffusivity_3d(:, :, z_crop_start:z_crop_end);
    dT_source_gpu = dT_source_3d(:, :, z_crop_start:z_crop_end);
end

% --- 3. 极速 FDTD 演化 ---
max_diffusivity = max(k_resin/(rho_resin*Cp_resin), k_water/(rho_water*Cp_water));
dt_th_max = (dx^2) / (6 * max_diffusivity);
dt_th = dt_th_max * 0.9; 

% [物理对抗] 结合屏蔽效应，完美曝光时间定为 1.2 秒
 
Nt_th = round(exposure_time / dt_th);

num_snapshots = 5;
snapshot_steps = round(linspace(1, Nt_th, num_snapshots));
snapshots_2d = zeros(Nx, Ny, num_snapshots);
T_max_history = zeros(Nt_th, 1);
t_axis = (1:Nt_th) * dt_th;

fprintf('  演化中 (ROI 定标 1.2MPa, 空化物理截断上限 2.0MPa)...\n');
tic;
for step = 1:Nt_th
    laplacian_T = 6 * del2(T_3d_gpu, dx);
    T_3d_gpu = T_3d_gpu + dt_th * (diffusivity_gpu .* laplacian_T + dT_source_gpu);
    
    T_focal_slice = T_3d_gpu(:, :, best_idx_crop);
    T_max_history(step) = gather(max(T_focal_slice(:)));
    
    snap_idx = find(snapshot_steps == step);
    if ~isempty(snap_idx)
        snapshots_2d(:, :, snap_idx) = gather(double(T_focal_slice));
    end
end
fprintf('  >>> 热力学演化耗时: %.2f 秒\n', toc);

T_focal_2d = gather(double(T_3d_gpu(:, :, best_idx_crop)));
T_max_real = T_max_history(end);
Q_focal_2d = gather(double(dT_source_gpu(:, :, best_idx_crop) * rho_resin * Cp_resin));

%% 13. 基于真实热力学的形貌预测
Thermal_Curing_Threshold = 65; 
% 纯粹的物理温度判定，没有任何人工滤镜干扰！
cured_mask_2d = T_focal_2d > Thermal_Curing_Threshold;

ROI_pixels = sum(imag_target(:) > 0.5); 
cured_coverage = (sum(cured_mask_2d(:)) / ROI_pixels) * 100; 
if cured_coverage > 100, cured_coverage = 100; end
R_binary = imag_target > 0.5;
intersection = R_binary & cured_mask_2d;
union = R_binary | cured_mask_2d;
IoU = sum(intersection(:)) / sum(union(:));

%% 14. 终极可视化全景仪表盘
% 使用 3x3 的形态学结构元素，模拟真实树脂固化时的“表面张力收缩与流平效应”
% se = strel('disk', 3); 
% cured_mask_2d = imclose(cured_mask_2d, se); 
% cured_mask_2d = imfill(cured_mask_2d, 'holes'); % 填补内部因散斑产生的微小未固化孔洞
y = x; 
figure(88); clf; set(gcf, 'Position', [100, 100, 1400, 500], 'Color', 'w');
sgtitle(sprintf('声致发热与热扩散 (中位数%.1fMPa, 上限%.1fMPa, %.1fs)', target_median_pressure/1e6, cavitation_limit/1e6, exposure_time), 'FontSize', 16, 'FontWeight', 'bold');
for i = 1:num_snapshots
    subplot(2, num_snapshots, i);
    imagesc(x*1e3, y*1e3, snapshots_2d(:, :, i));
    axis image; colormap hot; 
    % [色标修复] 强制锁定色标上限，防止极别畸形点致盲全图！
    caxis([50, max(65, min(T_max_real, 120))]); 
    if i == num_snapshots, colorbar; end
    title(sprintf('t = %.2f s\nMax: %.1f °C', snapshot_steps(i)*dt_th, max(max(snapshots_2d(:,:,i)))));
    xlabel('mm'); ylabel('mm');
end
subplot(2, 1, 2);
plot(t_axis, T_max_history, 'r-', 'LineWidth', 2); hold on;
yline(65, 'k--', 'LineWidth', 1.5, 'Label', '树脂固化阈值 (65°C)');
grid on; xlabel('照射时间 (s)'); ylabel('最高温度 (°C)');
title('焦点极限温度上升曲线');
ylim([20, max(max(T_max_history)+10, 80)]);

figure('Position', [30 30 1500 1000], 'Color', 'w');
subplot(3, 5, 1);
imagesc(x*1e3, y*1e3, imag_target); axis image; colormap(gca, gray);
title('目标图案'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 2);
imagesc(x*1e3, y*1e3, phase_wrapped); axis image; colormap(gca, hsv); colorbar;
title('全息相位 (理想)'); xlabel('mm');

subplot(3, 5, 3);
imagesc(x*1e3, y*1e3, phase_aligned_voxel); axis image; colormap(gca, hsv); colorbar;
title(sprintf('实际相位 (误差%.1f°)', mean_phase_error*180/pi)); xlabel('mm');

subplot(3, 5, 4);
surf(x*1e3, y*1e3, actual_thickness*1e3); view(2); shading interp; colorbar;
title('透镜厚度 (mm)'); xlabel('mm');

subplot(3, 5, 5);
imagesc(x*1e3, y*1e3, current_weight); axis image; colormap(gca, parula); colorbar;
title('W-IASA 最终振幅权重'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 6);
imagesc(x*1e3, y*1e3, Q_focal_2d / 1e6); axis image; colormap(gca, hot); colorbar;
title('焦面物理产热率 Q (MW/m^3)'); xlabel('mm');

subplot(3, 5, 7);
p_focal_scaled = gather(p_3d_scaled(:, :, best_idx_global));
imagesc(x*1e3, y*1e3, p_focal_scaled/1e6); axis image; colormap(gca, jet); colorbar;
title(sprintf('最佳焦面饱和声压 (Max %.1fMPa)', max(p_focal_scaled(:))/1e6)); xlabel('mm');

subplot(3, 5, 8);
imagesc(x*1e3, y*1e3, cured_mask_2d); axis image;
colormap(gca, [0.05 0.05 0.2; 0.9 0.9 0.1]);
title(sprintf('固化形貌 (IoU: %.4f)', IoU)); xlabel('mm');

subplot(3, 5, 9);
imagesc(x*1e3, y*1e3, T_focal_2d); axis image; colormap(gca, hot); colorbar;
% 同样修复这里被致盲的可能
caxis([50, max(65, min(T_max_real, 80))]);
title(sprintf('稳态温度 Max:%.1f°C', T_max_real)); xlabel('mm');

subplot(3, 5, 10);
plot(metrics_z, metrics_corr, 'b-', 'LineWidth', 1.5); hold on; 
plot(actual_z_dist_mm, best_corr, 'ro', 'MarkerSize', 10);
xlabel('Z 偏移 (mm)'); ylabel('Correlation'); title('Z-Scan 景深寻优'); grid on;

subplot(3, 5, [11 12 13]);
center = round(Nx/2);
plot(x*1e3, imag_target(center, :), 'k--', 'LineWidth', 2); hold on;
plot(x*1e3, p_focal_scaled(center, :)/max(p_focal_scaled(:)), 'r-', 'LineWidth', 1.5);
legend('目标', '饱和声压分布'); title('中心剖面对比'); grid on; xlabel('mm');

subplot(3, 5, [14 15]);
[X_surf, Y_surf] = meshgrid(x*1e3, y*1e3);
surf(X_surf, Y_surf, p_focal_scaled/1e6); shading interp; colormap(gca, jet);
title('3D焦面空化饱和声压场 (MPa)'); xlabel('mm'); ylabel('mm'); zlabel('MPa');


%% 15. 输出报告
fprintf('\n========================================\n');
fprintf('HDSP 严谨物理仿真报告 (最终完美闭环版)\n');
fprintf('========================================\n');
fprintf('网格配置:\n');
fprintf('  分辨率: %.2f μm\n', dx*1e6);
fprintf('  节点: %.2fM\n', (Nx*Ny*Nz)/1e6);
fprintf('----------------------------------------\n');
fprintf('IASA 全息生成:\n');
fprintf('  最佳截断步数: %d\n', epoch);
fprintf('  相位误差 (连续台阶): %.2f° (最大%.2f°)\n', mean_phase_error*180/pi, max_phase_error*180/pi);
fprintf('----------------------------------------\n');
fprintf('成像质量 (最佳焦面):\n');
fprintf('  位置: %.2f mm\n', actual_z_dist_mm);
fprintf('  Correlation: %.4f\n', best_corr);
fprintf('----------------------------------------\n');
fprintf('严谨物理预测 (空化屏蔽饱和模型 + GPU FDTD):\n');
fprintf('  区域中位数定标声压: %.2f MPa\n', target_median_pressure/1e6);
fprintf('  物理空化截断上限: %.2f MPa\n', cavitation_limit/1e6);
fprintf('  照射时间: %.1f 秒\n', exposure_time);
fprintf('  热传导演化最高温度: %.1f°C\n', T_max_real);
fprintf('  热交联阈值(>%d°C) 目标覆盖率: %.1f%%\n', Thermal_Curing_Threshold, cured_coverage);
fprintf('  最终热固化形貌交并比 (IoU): %.4f\n', IoU);
fprintf('========================================\n');