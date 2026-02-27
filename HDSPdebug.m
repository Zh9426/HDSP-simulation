clear; close all; clc;

%% ==================================================
%  【核心测试区】四大优化方案独立开关
% ==================================================
Use_Amplitude_Compensation = false; % [方案1] 振幅补偿 (补偿厚度吸收导致的不均匀)
Use_Apodization            = true; % [方案2] 切趾滤波 (加 Tukey 窗消除硬边缘同心圆)
Use_Phase_Unwrapping       = false; % [方案3] 相位解卷 (生成平滑厚透镜，消除断崖散射)
Use_Impedance_Matching     = true; % [方案4] 阻抗匹配 (消除透镜内外声波反射)
% ==================================================

%% 1. 网格及参数设定 (动态 Z 轴优化与各项同性网格)
Nx = 300; 
Lx = 40e-3;
Ny = Nx; Ly = Lx;
System_Offset = 2.03e-3;
z_target_dist = 20e-3; 
f0 = 4.0e6;
c_water = 1480; 
c_board = 2430; 
density_water = 997;
density_board_real = 1100; 

% [开关 4 逻辑应用]：阻抗匹配
if Use_Impedance_Matching
    density_board = (c_water * density_water) / c_board;
    fprintf('>>> 已开启: [阻抗匹配] (消除内部反射)\n');
else
    density_board = density_board_real;
end

lambda_water = c_water / f0;
dx = Lx / Nx; dy = dx; dz = dx; 
Lz_needed = 30e-3; 
Nz_min = ceil(Lz_needed / dz);
optimal_sizes = [128, 192, 216, 256, 300, 384, 512];
Nz = optimal_sizes(find(optimal_sizes >= Nz_min, 1));
Lz = Nz * dz;

x = (-Nx/2 : Nx/2-1) * dx;
[Y_grid, X_grid] = meshgrid(1:Ny, 1:Nx);

% [开关 2 逻辑预备]：生成 2D Tukey 窗
tukey_1d = tukeywin(Nx, 0.2); % 边缘有 20% 是平滑滚降的
tukey_2d = tukey_1d * tukey_1d';

fprintf('==================================================\n');
fprintf('网格分辨率: dx = dy = dz = %.4f mm\n', dx*1e3);
fprintf('每波长采样点 (PPW): %.2f\n', lambda_water/dx);
fprintf('优化后网格尺寸: %d x %d x %d\n', Nx, Ny, Nz);
fprintf('==================================================\n');

%% 2. 目标定义
fprintf('目标图案定义\n');
imag_target = zeros(Nx, Ny);
h_A = 160; w_base = 100; thickness = 22; bar_pos = 50; bar_width = 20;
cx = round(Nx/2); cy = round(Ny/2);
x_top = cx - h_A/2; x_bottom = cx + h_A/2;
slope = h_A / (w_base/2);
dx_outer = X_grid - x_top; dy_abs = abs(Y_grid - cy);
width_at_x = dx_outer / slope;
mask_outer = (dx_outer >= 0) & (dx_outer <= h_A) & (dy_abs <= width_at_x);
x_top_inner = x_top + thickness * 1.8; 
dx_inner = X_grid - x_top_inner;
width_inner_at_x = dx_inner / slope;
mask_inner_cone = (dx_inner >= 0) & (dy_abs <= width_inner_at_x); 
x_bar_start = x_bottom - bar_pos - bar_width/2;
x_bar_end   = x_bottom - bar_pos + bar_width/2;
mask_bar = (X_grid >= x_bar_start) & (X_grid <= x_bar_end);
imag_target = mask_outer & (~mask_inner_cone | mask_bar);
imag_target = double(imag_target > 0.5);

%% 3. IASA 迭代
fprintf('运行 IASA...\n');
pad_factor = 2; 
Nx_pad = Nx * pad_factor; Ny_pad = Ny * pad_factor;
Lx_pad = Lx * pad_factor; dk_pad = 2 * pi / Lx_pad;
kx_pad = (-Nx_pad/2 : Nx_pad/2-1) * dk_pad;
[Kx_pad, Ky_pad] = meshgrid(kx_pad, kx_pad);
k_water = 2 * pi / lambda_water;
Kz_sq = k_water^2 - Kx_pad.^2 - Ky_pad.^2; Kz_sq(Kz_sq < 0) = 0; 
H_forward = exp(1i * sqrt(Kz_sq) * z_target_dist); 
H_backward = exp(-1i * sqrt(Kz_sq) * z_target_dist); 
rng(9426);
board_phase_pad = zeros(Nx_pad, Ny_pad);
board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = exp(1i * rand(Nx, Nx) * 2 * pi);
target_pad = zeros(Nx_pad, Ny_pad);
target_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = imag_target;
weight_pad = target_pad * 1.5; 
mask_roi = (target_pad > 0.5); mask_dark = (target_pad < 0.5);    

% [方案 1 & 2 相关准备]
if Use_Apodization, fprintf('>>> 已开启: [切趾滤波] (消除同心边缘衍射)\n'); end
if Use_Amplitude_Compensation, fprintf('>>> 已开启: [振幅补偿] (补偿树脂吸收)\n'); end
alpha_board_Np_m = (1.5 / 8.686) * 100 * (f0/1e6)^1.5; % dB/cm/MHz^y 转换为 Np/m

epoch = 150; 
for i = 1:epoch
    U_source = zeros(Nx_pad, Ny_pad);
    center_phase = angle(board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny));
    
    % --- [开关 1 逻辑应用]：振幅补偿 ---
    amplitude_mask = ones(Nx, Ny);
    if Use_Amplitude_Compensation && i > 10
        % 估算当前相位所需的厚度，并计算物理衰减
        k_board_val_temp = 2 * pi * f0 / c_board;
        k_diff_temp = abs(k_water - k_board_val_temp); 
        h_temp = mod(center_phase, 2*pi) / k_diff_temp;
        amplitude_mask = exp(-alpha_board_Np_m * h_temp);
        % 归一化衰减遮罩，避免能量无限缩小
        amplitude_mask = amplitude_mask / max(amplitude_mask(:));
    end
    
    % --- [开关 2 逻辑应用]：切趾窗 ---
    if Use_Apodization
        amplitude_mask = amplitude_mask .* tukey_2d;
    end
    
    U_source(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = amplitude_mask .* exp(1i * center_phase);
    
    % ASM
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
    U_target_constrained = weight_pad .* exp(1i * angle(U_target));
    A_target_cons = fftshift(fft2(ifftshift(U_target_constrained)));
    A_source_cons = A_target_cons .* H_backward;
    U_source_new = fftshift(ifft2(ifftshift(A_source_cons)));
    board_phase_pad = U_source_new;
end

holo_phase = angle(board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny));

%% 4. 相位转厚度与体素化优化
fprintf('进行物理厚度构建...\n');

k_board_val = 2 * pi * f0 / c_board;
k_diff = abs(k_water - k_board_val); 

% --- [开关 3 逻辑应用]：相位解卷 ---
if Use_Phase_Unwrapping
    fprintf('>>> 已开启: [相位解卷] (生成完美平滑透镜)\n');
    % 简易 2D 解卷 (先按行再按列解卷)
    phase_unwrapped = unwrap(unwrap(holo_phase, [], 1), [], 2);
    % 保证解卷后的相位为正
    phase_unwrapped = phase_unwrapped - min(phase_unwrapped(:));
    thickness_ideal = phase_unwrapped / k_diff;
else
    % 传统包裹相位 (菲涅尔透镜)
    phase_wrapped = mod(holo_phase, 2*pi); 
    thickness_ideal = phase_wrapped / k_diff;
end

thickness_map = imgaussfilt(thickness_ideal, 0.2); 
min_base = 2 * dz; 
thickness_map = thickness_map + min_base;

net_num_board = round(thickness_map / dz);
actual_thickness = net_num_board * dz;

figure(11); clf; set(gcf, 'Position', [100, 100, 1200, 400], 'Color', 'w');
subplot(1,3,1); imagesc(x*1e3, x*1e3, holo_phase); axis image; colormap hsv; colorbar; title('IASA 原始相位');
subplot(1,3,2); surf(x*1e3, x*1e3, thickness_ideal*1e3); shading flat; colormap parula; title('理想连续厚度 (mm)'); view(2); colorbar;
subplot(1,3,3); surf(x*1e3, x*1e3, actual_thickness*1e3); shading flat; colormap parula; title('体素化实际厚度 (mm)'); view(2); colorbar;

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
            
            % 只有在解卷模式下，如果透镜太厚，可以选择关闭衰减看纯干涉
            % 如果开启振幅补偿，则保留真实衰减
            medium.alpha_coeff(i, j, z_start:z_end) = 1.5; 
        end
    end
end
thickest = max(net_num_board(:)) * dz;

%% 6. 时间与声源设置
fprintf('时间与声源设置\n');
cfl = 0.3;
t_end = (Lz * 1.5) / c_water; 
kgrid.makeTime(medium.sound_speed, cfl, t_end); 

source.p_mask = zeros(Nx, Ny, Nz);
source.p_mask(:, :, source_z_idx) = 1; 
t_vec = kgrid.t_array;
source_sig = sin(2 * pi * f0 * t_vec); 
ramp_pts = round(2 / f0 / kgrid.dt); 
time_window = [linspace(0,1,ramp_pts), ones(1, kgrid.Nt-ramp_pts)];

% 生成基础的 1D 时域信号
p_time = source_sig .* time_window; 

% [开关 2 修复]：k-Wave 中如果声源各点振幅不同，需要构建 [网格点数, 时间步数] 的矩阵
if Use_Apodization
    tukey_flat = tukey_2d(:); % 展平为一维列向量 [Nx*Ny, 1]
    source.p = tukey_flat * p_time; % 矩阵乘法生成 [Nx*Ny, Nt] 的波形矩阵
else
    source.p = p_time; % 统一振幅，大小为 [1, Nt]
end
source.p_mode = 'dirichlet';
%% 7. Sensor 放置
fprintf('sensor设置\n');
sensor.mask = zeros(Nx, Ny, Nz);
z_board_exit_idx = z_board_stat_idx + round(thickest/dz);
target_plane_idx = z_board_exit_idx + round(z_target_dist / dz);

scan_range_idx = round(3e-3 / dz); 
z_scan_start = target_plane_idx - scan_range_idx;
z_scan_end = target_plane_idx + scan_range_idx;
if z_scan_end > Nz - pml_size, z_scan_end = Nz - pml_size; end
sensor.mask(:, :, z_scan_start:z_scan_end) = 1;

sensor.record = {'p'}; 
sensor.record_start_index = kgrid.Nt - round(3/f0/kgrid.dt);
fprintf('  - 扫描范围 Z Index: %d 到 %d\n', z_scan_start, z_scan_end);

%% 8. 仿真
fprintf('仿真开始\n');
input_args = {'PMLInside', true, 'PMLSize', 10, 'PlotPML', false, 'PlotSim', false, 'DataCast', 'gpuArray-single'};
try
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
catch
    disp('GPU 失败，切换 CPU...');
    input_args = input_args(1:end-2);
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
end

%% 9. 数据处理与 Z-Scan 寻优
if isfield(sensor_data, 'p')
    p_raw = gather(sensor_data.p); 
    [~, Nt_rec] = size(p_raw);
    p_fft = fft(p_raw, [], 2);
    [~, f_idx] = min(abs( (0:Nt_rec-1)/Nt_rec/kgrid.dt - f0 ));
    p_complex = p_fft(:, f_idx);
    
    p_field_3d = zeros(Nx, Ny, Nz);
    mask_indices = find(sensor.mask);
    p_field_3d(mask_indices) = p_complex;
    
    scan_vol = abs(p_field_3d(:, :, z_scan_start:z_scan_end));
    num_slices = size(scan_vol, 3);
    
    R = double(imag_target);                 
    R = (R - min(R(:))) / (max(R(:)) - min(R(:)));
    R_mean = mean(R(:));
    
    best_corr = -1; best_slice_idx = 1; best_img_recon = []; best_nmse = inf; best_psnr = 0;
    
    for k = 1:num_slices
        A = scan_vol(:, :, k);
        A = (A - min(A(:))) / (max(A(:)) - min(A(:))); 
        A_mean = mean(A(:));
        
        val_corr = sum(sum((R - R_mean) .* (A - A_mean))) / sqrt(sum(sum((R - R_mean).^2)) * sum(sum((A - A_mean).^2)));
        
        if val_corr > best_corr
            best_corr = val_corr; best_slice_idx = k; best_img_recon = A;
            best_nmse = sum(sum((R - A).^2)) / sum(sum(R.^2));
            mse = mean((R(:) - A(:)).^2);
            if mse == 0, best_psnr = Inf; else, best_psnr = 20 * log10(1 / sqrt(mse)); end
        end
    end
    
    actual_z_dist_mm = (z_scan_start + best_slice_idx - 1 - z_board_exit_idx) * dz * 1e3;
    
    figure(6); clf; set(gcf, 'Position', [100, 100, 1000, 400], 'Color', 'w');
    subplot(1,3,1); imagesc(x*1e3, x*1e3, imag_target); axis image; colormap gray; title('原始目标'); xlabel('mm');
    subplot(1,3,2); imagesc(x*1e3, x*1e3, best_img_recon); axis image; colormap jet; 
    title(sprintf('物理最佳焦面 (Z=%.2f mm)', actual_z_dist_mm)); xlabel('mm');
    subplot(1,3,3); center_row = round(Nx/2);
    plot(x*1e3, imag_target(center_row, :), 'k--', 'LineWidth', 1.5); hold on;
    plot(x*1e3, best_img_recon(center_row, :), 'r-', 'LineWidth', 1.5);
    legend('Target', 'Simulated'); title('最佳焦面剖面线'); grid on; xlabel('mm');

    try best_ssim = ssim(best_img_recon, R); catch, best_ssim = NaN; end
    
    fprintf('\n========================================\n');
    fprintf('终极图像重建质量评估 (Z-Scan 最佳焦面):\n');
    fprintf('Correlation : %.4f \n', best_corr);
    fprintf('NMSE        : %.4f \n', best_nmse);
    fprintf('PSNR        : %.2f dB \n', best_psnr);
    fprintf('SSIM        : %.4f \n', best_ssim);
    fprintf('========================================\n');
end