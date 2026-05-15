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

%% 2. 目标定义 (A字形图案)
fprintf('定义目标图案...\n');
imag_target = zeros(Nx, Ny);
h_A = round(0.016/dx);       % 16mm高度
w_base = round(0.010/dx);    % 10mm底部宽度
thickness = round(0.002/dx); % 2mm粗细
bar_pos = round(0.005/dx);   
bar_width = round(0.002/dx); 

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

x_top_inner = x_top + thickness * 2;
dx_inner = X_grid - x_top_inner;
width_inner_at_x = dx_inner / slope;
mask_inner_cone = (dx_inner >= 0) & (dy_abs <= width_inner_at_x); 

x_bar_start = x_bottom - bar_pos - bar_width/2;
x_bar_end = x_bottom - bar_pos + bar_width/2;
mask_bar = (X_grid >= x_bar_start) & (X_grid <= x_bar_end);

imag_target = mask_outer & (~mask_inner_cone | mask_bar);
imag_target = double(imag_target > 0.5);

%% 3. IASA迭代 (改进版，带收敛监控)
fprintf('运行 IASA (高分辨率版)...\n');
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

% 传播函数
H_forward = exp(1i * sqrt(Kz_sq) * z_target_dist); 
H_backward = exp(-1i * sqrt(Kz_sq) * z_target_dist); 

% 初始化
rng(9426);
board_phase_pad = zeros(Nx_pad, Ny_pad);
board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = exp(1i * rand(Nx, Ny) * 2 * pi);

target_pad = zeros(Nx_pad, Ny_pad);
target_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = imag_target;

% 权重初始化
weight_pad = target_pad * 1.2; 
mask_roi = (target_pad > 0.5);     
mask_dark = (target_pad < 0.5);    

% 迭代参数
epoch = 300; 
error_history = zeros(epoch, 1);
best_error = inf;
best_phase = board_phase_pad;
patience = 50;
patience_counter = 0;

for i = 1:epoch
    % 前向传播
    U_source = zeros(Nx_pad, Ny_pad);
    center_phase = angle(board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny));
    U_source(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = 1.0 .* exp(1i * center_phase);
    
    A_source = fftshift(fft2(ifftshift(U_source)));
    A_target = A_source .* H_forward;
    U_target = fftshift(ifft2(ifftshift(A_target)));
    
    % 计算误差
    rec_amp = abs(U_target);
    peak_val = max(rec_amp(mask_roi)); 
    if peak_val == 0, peak_val = max(rec_amp(:)); end
    rec_amp_norm = rec_amp / peak_val;
    
    error_history(i) = mean((rec_amp_norm(mask_roi) - target_pad(mask_roi)).^2);
    
    % 保存最佳
    if error_history(i) < best_error
        best_error = error_history(i);
        best_phase = board_phase_pad;
        patience_counter = 0;
    else
        patience_counter = patience_counter + 1;
    end
    
    % 早停
    if patience_counter > patience
        fprintf('  早停于第 %d 步 (最佳误差: %.6f)\n', i, best_error);
        break;
    end
    
    % 自适应权重更新
    if i > 20
        beta = 0.5;
        correction = (target_pad(mask_roi) ./ (rec_amp_norm(mask_roi) + 1e-6)) .^ beta;
        weight_pad(mask_roi) = weight_pad(mask_roi) .* correction;
        weight_pad(weight_pad > 10) = 10;
        weight_pad(weight_pad < 0.1) = 0.1;
        weight_pad(mask_dark) = 0;
    end
    
    % 反向传播
    U_target_constrained = weight_pad .* exp(1i * angle(U_target));
    A_target_cons = fftshift(fft2(ifftshift(U_target_constrained)));
    A_source_cons = A_target_cons .* H_backward;
    U_source_new = fftshift(ifft2(ifftshift(A_source_cons)));
    board_phase_pad = U_source_new;
end

% 使用最佳相位
board_phase_pad = best_phase;
holo_phase = angle(board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny));

%% 4. 相位转厚度 (回滚至稳定基线无损版，修复绘图变量)
fprintf('相位转厚度 (无损台阶版)...\n');
phase_wrapped = mod(holo_phase, 2*pi); 

k_board_val = 2 * pi * f0 / c_board;
k_water_val = 2 * pi * f0 / c_water;
k_diff = abs(k_water_val - k_board_val); 

thickness_ideal = phase_wrapped / k_diff;

% 直接添加基础厚度，不做任何破坏包裹边缘的滤波！保留完美的菲涅尔断崖！
min_base = 5 * dx; 
thickness_map = thickness_ideal + min_base;

% 严格体素化
net_num_board = round(thickness_map / dx);
actual_thickness = net_num_board * dx;

% --- 补回画图需要的 phase_aligned 和 误差统计变量 ---
actual_phase_imparted = mod(actual_thickness * k_diff, 2*pi);

% 全局相位对齐 (为了公平比较误差)
phase_diff = angle(exp(1i * (actual_phase_imparted - phase_wrapped)));
global_offset = median(phase_diff(:));
phase_aligned = mod(actual_phase_imparted - global_offset, 2*pi);

% 量化误差评估
phase_error = abs(angle(exp(1i * (phase_aligned - phase_wrapped))));
mean_phase_error = mean(phase_error(:));
max_phase_error = max(phase_error(:));

fprintf('  平均相位量化误差: %.4f rad (%.2f°)\n', mean_phase_error, mean_phase_error*180/pi);
fprintf('  最大相位量化误差: %.4f rad (%.2f°)\n', max_phase_error, max_phase_error*180/pi);
% figure(11); clf;
% set(gcf, 'Position', [100, 100, 1200, 400], 'Color', 'w');
% subplot(1,3,1); imagesc(x*1e3, x*1e3, phase_wrapped); axis image; colormap hsv; colorbar; title('理想 Wrapped 相位');
% subplot(1,3,2); imagesc(x*1e3, x*1e3, phase_aligned_voxel); axis image; colormap hsv; colorbar; title('微平滑体素化实际相位');
% subplot(1,3,3); surf(x*1e3, x*1e3, actual_thickness*1e3); shading flat; colormap parula; title('构建的 3D 透镜厚度'); view(2); colorbar;

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

%% 6. 时间设置
fprintf('时间设置...\n');
cfl = 0.2; % 保守CFL
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
scan_range_idx = round(1.5e-3 / dz); 
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
%% 9. 主声学仿真
fprintf('开始声学仿真...\n');
input_args = {
    'PMLInside', true, ...
    'PMLSize', pml_size, ...
    'PlotPML', false, ...
    'PlotSim', false, ...
    'DataCast', 'gpuArray-single'
};

try
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
catch ME
    % warning('GPU失败: %s，切换CPU...', ME.message);
    input_args_cpu = {'PMLInside', true, 'PMLSize', pml_size, 'PlotPML', false, 'PlotSim', false};
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args_cpu{:});
end

fprintf('声学仿真完成，开始数据处理...\n');

%% 10. 声场后处理 (提取稳态场)
p_data = gather(sensor_data.p);
[~, Nt] = size(p_data);

% FFT提取基频分量
p_fft = fft(p_data, [], 2);
freq_axis = (0:Nt-1)/(Nt*kgrid.dt);
[~, f_idx] = min(abs(freq_axis - f0));

p_complex = p_fft(:, f_idx);
p_amplitude = abs(p_complex);
p_phase = angle(p_complex);

% 重建3D场
p_field_3d = zeros(Nx, Ny, Nz);
mask_indices = find(sensor.mask);
p_field_3d(mask_indices) = p_amplitude;

%% 11. Z-Scan寻优 (评估成像质量)
fprintf('Z-Scan寻优...\n');
R = double(imag_target);
R = (R - min(R(:))) / (max(R(:)) - min(R(:)) + eps);
R_mean = mean(R(:));

best_corr = -1;
best_idx = z_scan_start;
best_slice = [];

metrics = struct('corr', [], 'nmse', [], 'psnr', [], 'z', []);

for k = z_scan_start:z_scan_end
    A = p_field_3d(:, :, k);
    if max(A(:)) == 0, continue; end
    
    A = A / max(A(:));
    A_mean = mean(A(:));
    
    % Correlation
    numerator = sum(sum((R - R_mean) .* (A - A_mean)));
    denominator = sqrt(sum(sum((R - R_mean).^2)) * sum(sum((A - A_mean).^2)));
    corr = numerator / (denominator + eps);
    
    % NMSE
    nmse = sum(sum((R - A).^2)) / sum(sum(R.^2));
    
    % PSNR
    mse = mean((R(:) - A(:)).^2);
    psnr = 20 * log10(1 / sqrt(mse + eps));
    
    metrics.corr(end+1) = corr;
    metrics.nmse(end+1) = nmse;
    metrics.psnr(end+1) = psnr;
    metrics.z(end+1) = k * dx * 1e3;
    
    if corr > best_corr
        best_corr = corr;
        best_idx = k;
        best_slice = A;
    end
end

actual_z_dist = (best_idx - z_board_exit_idx) * dx * 1e3;
fprintf('  最佳焦面: Z = %.2f mm (理论: %.2f mm, 偏移: %.2f mm)\n', ...
    actual_z_dist, z_target_dist*1e3, abs(actual_z_dist - z_target_dist*1e3));
target_focal_pressure = 2.5e6; % 设定焦点峰值声压为 2.5 MPa
% 将整个 3D 声压场等比例线性放大
p_field_3d = (p_field_3d / max(p_field_3d(:))) * target_focal_pressure;

%% 12. 真实树脂温度场计算 (针对最佳焦面)
fprintf('计算焦平面树脂温度演化...\n');

% 提取最佳焦平面的绝对声压分布 (并注入 2.5 MPa 物理功率)
target_focal_pressure = 2.5e6; 
p_focal_2d = (best_slice / max(best_slice(:))) * target_focal_pressure;

% 真实 3D 打印树脂的物理参数
rho_resin = 1100;     % 树脂密度 (kg/m^3)
c_resin = 2500;       % 树脂声速 (m/s)
Cp_resin = 1500;      % 树脂比热容 (J/kg.K)
% 树脂声吸收系数 (假设 1.5 dB/cm/MHz，这里以 4MHz 换算为 Np/m)
alpha_np_resin = (1.5 / 8.686) * 100 * (f0/1e6)^1.5; 

% 计算焦平面的声强与体积产热率
I_focal = (p_focal_2d.^2) ./ (2 * rho_resin * c_resin);
Q_focal = 2 * alpha_np_resin * I_focal;

% 计算稳态曝光温升 (例如 5秒 短时高能曝光)
exposure_time = 0.3; 
delta_T_focal = Q_focal * exposure_time ./ (rho_resin * Cp_resin);
T_final_focal = 20 + delta_T_focal; % 基础室温 20°C

%% 13. 空化与固化预测 (针对焦平面)
% p_cav_threshold = 2.0e6; % 2.0 MPa
p_cav_threshold = max(p_focal_2d(:)) * 0.5;
cavitation_mask_2d = p_focal_2d > p_cav_threshold;

% 计算焦面有效区域占比
ROI_pixels = sum(imag_target(:) > 0.5); % 目标字母 A 的像素面积
cavitation_coverage = (sum(cavitation_mask_2d(:)) / ROI_pixels) * 100; 
if cavitation_coverage > 100, cavitation_coverage = 100; end

%% 14. 终极可视化全景仪表盘
figure('Position', [30 30 1500 1000], 'Color', 'w');
y = x; % 补齐 y 轴变量

% 第1行: 全息图与目标
subplot(3, 5, 1);
imagesc(x*1e3, y*1e3, imag_target); axis image; colormap(gca, gray);
title('目标图案'); xlabel('mm'); ylabel('mm');

subplot(3, 5, 2);
imagesc(x*1e3, y*1e3, phase_wrapped); axis image; colormap(gca, hsv); colorbar;
title('全息相位 (理想)'); xlabel('mm');

subplot(3, 5, 3);
imagesc(x*1e3, y*1e3, phase_aligned); axis image; colormap(gca, hsv); colorbar;
title(sprintf('实际相位 (误差%.1f°)', mean_phase_error*180/pi)); xlabel('mm');

subplot(3, 5, 4);
surf(x*1e3, y*1e3, actual_thickness*1e3); view(2); shading interp; colorbar;
title('透镜厚度 (mm)'); xlabel('mm');

subplot(3, 5, 5);
semilogy(1:length(error_history), error_history, 'b-', 'LineWidth', 1.5);
xlabel('迭代'); ylabel('MSE'); title('IASA收敛曲线'); grid on;

% 第2行: 声场结果
subplot(3, 5, 6);
p_exit = p_field_3d(:, :, z_board_exit_idx);
p_exit = (p_exit / max(p_field_3d(:))) * target_focal_pressure; % 同步缩放
imagesc(x*1e3, y*1e3, p_exit/1e6); axis image; colormap(gca, jet); colorbar;
title('出口声压 (MPa)'); xlabel('mm');

subplot(3, 5, 7);
imagesc(x*1e3, y*1e3, p_focal_2d/1e6); axis image; colormap(gca, jet); colorbar;
title(sprintf('最佳焦面 (Z=%.2fmm)', actual_z_dist)); xlabel('mm');

subplot(3, 5, 8);
imagesc(x*1e3, y*1e3, cavitation_mask_2d); axis image;
colormap(gca, [0.05 0.05 0.2; 0 0.8 1]);
title('有效声致固化/空化区'); xlabel('mm');

subplot(3, 5, 9);
imagesc(x*1e3, y*1e3, T_final_focal); axis image; colormap(gca, hot); colorbar;
title(sprintf('树脂温度(°C) Max:%.1f', max(T_final_focal(:)))); xlabel('mm');

subplot(3, 5, 10);
plot(metrics.z, metrics.corr, 'b-', 'LineWidth', 1.5);
hold on; plot(actual_z_dist, best_corr, 'ro', 'MarkerSize', 10);
xlabel('Z (mm)'); ylabel('Correlation'); title('Z-Scan 景深寻优'); grid on;

% 第3行: 剖面对比
subplot(3, 5, [11 12 13]);
center = round(Nx/2);
plot(x*1e3, imag_target(center, :), 'k--', 'LineWidth', 2); hold on;
plot(x*1e3, p_focal_2d(center, :)/max(p_focal_2d(:)), 'r-', 'LineWidth', 1.5);
plot(x*1e3, p_exit(center, :)/max(p_exit(:)), 'b:', 'LineWidth', 1);
legend('目标', '焦面', '出口'); title('中心剖面对比'); grid on; xlabel('mm');

subplot(3, 5, [14 15]);
[X_surf, Y_surf] = meshgrid(x*1e3, y*1e3);
surf(X_surf, Y_surf, p_focal_2d/1e6); shading interp; colormap(gca, jet);
title('3D焦面绝对声压分布 (MPa)'); xlabel('mm'); ylabel('mm'); zlabel('MPa');

%% 15. 输出报告
fprintf('\n========================================\n');
fprintf('HDSP 严谨物理仿真报告 (Final)\n');
fprintf('========================================\n');
fprintf('网格配置:\n');
fprintf('  分辨率: %.2f μm\n', dx*1e6);
fprintf('  PPW: %.2f\n', lambda_water/dx);
fprintf('  节点: %.2fM\n', (Nx*Ny*Nz)/1e6);
fprintf('----------------------------------------\n');
fprintf('IASA 全息生成:\n');
fprintf('  最佳截断步数: %d\n', length(error_history) - patience_counter);
fprintf('  最终MSE: %.6f\n', best_error);
fprintf('  相位误差 (连续台阶): %.2f° (最大%.2f°)\n', mean_phase_error*180/pi, max_phase_error*180/pi);
fprintf('----------------------------------------\n');
fprintf('成像质量 (最佳焦面):\n');
fprintf('  位置: %.2f mm (理论%.2f mm)\n', actual_z_dist, z_target_dist*1e3);
fprintf('  Correlation: %.4f\n', best_corr);
[~, best_nmse_idx] = min(abs(metrics.corr - best_corr));
fprintf('  NMSE: %.4f\n', metrics.nmse(best_nmse_idx));
fprintf('  PSNR: %.2f dB\n', metrics.psnr(best_nmse_idx));
fprintf('----------------------------------------\n');
fprintf('3D打印物理预测 (靶材: 液态树脂):\n');
fprintf('  换能器等效焦面峰值声压: %.2f MPa\n', max(p_focal_2d(:))/1e6);
fprintf('  目标笔画区固化覆盖率(>2MPa): %.1f%%\n', cavitation_coverage);
fprintf('  5秒曝光中心极值温度: %.1f°C\n', max(T_final_focal(:)));
fprintf('========================================\n');
