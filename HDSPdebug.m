clear; close all; clc;
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

%% 3. IASA 迭代 (保持原样)
fprintf('运行 IASA (引入 Padding 和 乘性权重优化)...\n');
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
rng(9426);
board_phase_pad = zeros(Nx_pad, Ny_pad);
board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = exp(1i * rand(Nx, Nx) * 2 * pi);

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
rho_match = (c_water * density_water) / c_board;

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
            medium.density(i, j, z_start:z_end) = rho_match; 
            
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
    
    % 计算实际的最佳物理聚焦距离
    actual_z_dist_idx = z_scan_start + best_slice_idx - 1 - z_board_exit_idx;
    actual_z_dist_mm = actual_z_dist_idx * dz * 1e3;
    
    fprintf('>>> 自动寻优完成！最佳焦面发生偏移: 理论 20.00mm -> 实际 %.2f mm\n', actual_z_dist_mm);

    % 可视化最佳平面
    figure(6); clf; set(gcf, 'Position', [100, 100, 1000, 400], 'Color', 'w');
    subplot(1,3,1); imagesc(x*1e3, x*1e3, imag_target); axis image; colormap gray; title('原始目标'); xlabel('mm');
    subplot(1,3,2); imagesc(x*1e3, x*1e3, best_img_recon); axis image; colormap jet; 
    title(sprintf('物理最佳焦面重建 (Z=%.2f mm)', actual_z_dist_mm)); xlabel('mm');
    subplot(1,3,3);
    center_row = round(Nx/2);
    plot(x*1e3, imag_target(center_row, :), 'k--', 'LineWidth', 1.5); hold on;
    plot(x*1e3, best_img_recon(center_row, :), 'r-', 'LineWidth', 1.5);
    legend('Target', 'Simulated'); title('最佳焦面剖面线'); grid on; xlabel('mm');

    try
        best_ssim = ssim(best_img_recon, R);
    catch
        best_ssim = NaN; 
    end
    

    fprintf('========================================\n');
    fprintf('IASA参数:\n');
    fprintf('迭代数: %d\n', epoch);
    fprintf('\n');
    
    fprintf('========================================\n');
    fprintf('仿真参数:\n');
    fprintf('目标平面距离: %.4f\n', z_target_dist);
    fprintf('完美匹配层大小: %d 格\n', pml_size); % 修改了这里的单位防报错
    fprintf('source位置 Z Index: %d\n', source_z_idx); % 修改了格式防报错
    % fprintf('目标平面位置 Z Index: %d\n', target_plane_idx);
    fprintf('\n');
    
    fprintf('========================================\n');
    fprintf(' -> 平均相位量化误差: %.4f Rad (%.1f 度)\n', mean_phase_error, mean_phase_error*180/pi);
    if mean_phase_error > 0.5
        warning('体素化误差过大！建议减小 dz (提高网格分辨率)！');
    end
    fprintf('\n========================================\n');
    fprintf('终极图像重建质量评估 (Z-Scan 最佳焦面):\n');
    fprintf('Correlation : %.4f \n', best_corr);
    fprintf('NMSE        : %.4f \n', best_nmse);
    fprintf('PSNR        : %.2f dB \n', best_psnr);
    fprintf('SSIM        : %.4f \n', best_ssim);
    fprintf('========================================\n');
end