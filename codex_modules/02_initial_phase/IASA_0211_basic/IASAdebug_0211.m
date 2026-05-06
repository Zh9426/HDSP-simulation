clear; close all; clc;
%% 1. 网格及参数设定 (完全保持原样)
Nx = 256;
Lx = 40e-3;
Ny = Nx; Ly = Lx;
System_Offset = 2.03e-3;
z_target_dist = 20e-3; % 目标距离
%z_target_dist = z_target_dist+System_Offset;
f0 = 4.0e6;
c_water = 1480;
c_board = 2430;
density_water = 997;
density_board = 1100;
lambda_water = c_water / f0;
dx = Lx / Nx;
dy = dx;
dz = dx;
Nz = 384;
Lz = Nz * dz;
x = (-Nx/2 : Nx/2-1) * dx;
fprintf('网格尺寸: %d x %d x %d, dx=%.4f mm\n', Nx, Ny, Nz, dx*1e3);

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

%% 3. IASA 迭代 (核心修改区域)
fprintf('运行 IASA (引入 Padding 和 乘性权重优化)...\n');

% === [修改部分 Start] 引入 Zero-Padding 网格 ===
pad_factor = 2;
Nx_pad = Nx * pad_factor;
Ny_pad = Ny * pad_factor;
Lx_pad = Lx * pad_factor;
dk_pad = 2 * pi / Lx_pad;
kx_pad = (-Nx_pad/2 : Nx_pad/2-1) * dk_pad;
[Kx_pad, Ky_pad] = meshgrid(kx_pad, kx_pad);

% 原代码注释:
% k_water = 2 * pi / lambda_water;
% dk = 2 * pi / Lx;
% kx = (-Nx/2 : Nx/2-1) * dk;
% [Kx, Ky] = meshgrid(kx, kx);
% Kz_sq = k_water^2 - Kx.^2 - Ky.^2;
% Kz_sq(Kz_sq < 0) = 0;
% H_forward = exp(1i * sqrt(Kz_sq) * z_target_dist);
% H_backward = exp(-1i * sqrt(Kz_sq) * z_target_dist);

% 新代码: 在大网格上计算传播算子
k_water = 2 * pi / lambda_water;
Kz_sq = k_water^2 - Kx_pad.^2 - Ky_pad.^2;
Kz_sq(Kz_sq < 0) = 0; % 滤除倏逝波
H_forward = exp(1i * sqrt(Kz_sq) * z_target_dist);
H_backward = exp(-1i * sqrt(Kz_sq) * z_target_dist);
% === [修改部分 End] ===

rng(9426);

% === [修改部分 Start] 初始化在大网格中心 ===
% 原代码注释:
% board_phase = exp(1i * rand(Nx, Nx) * 2 * pi);
% current_weight = imag_target*2;
% mask_signal = (imag_target == 1);
% mask_bg = (imag_target == 0);

% 新代码:
board_phase_pad = zeros(Nx_pad, Ny_pad);
% 仅在中心区域填充随机相位
board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = exp(1i * rand(Nx, Nx) * 2 * pi);

% 将目标图像放入大网格中心
target_pad = zeros(Nx_pad, Ny_pad);
target_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = imag_target;

% 初始化权重
weight_pad = target_pad * 1.5; % 初始权重稍微给高一点
mask_roi = (target_pad > 0.5);     % 信号区
mask_dark = (target_pad < 0.5);    % 背景区
% === [修改部分 End] ===

epoch = 150; % 增加迭代次数以充分收敛

for i = 1:epoch
    % === [修改部分 Start] Forward 传播 (在大网格上) ===
    % 原代码注释:
    % FFT_board = fftshift(fft2(ifftshift(board_phase)));
    % target_field = fftshift(ifft2(ifftshift(FFT_board .* H_forward)));
    % rec_amp = abs(target_field);
    % rec_amp = rec_amp / max(rec_amp(:));

    % 新代码:
    % Source Constraint: 仅保留中心 Nx x Ny 区域的相位，幅度设为1，Pad区域为0
    U_source = zeros(Nx_pad, Ny_pad);
    center_phase = angle(board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny));
    U_source(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny) = 1.0 .* exp(1i * center_phase);

    % ASM 传播
    A_source = fftshift(fft2(ifftshift(U_source)));
    A_target = A_source .* H_forward;
    U_target = fftshift(ifft2(ifftshift(A_target)));

    rec_amp = abs(U_target);
    % 局部归一化: 仅针对ROI区域归一化，防止背景亮斑干扰
    peak_val = max(rec_amp(mask_roi));
    if peak_val == 0, peak_val = max(rec_amp(:)); end
    rec_amp_norm = rec_amp / peak_val;
    % === [修改部分 End] ===

    % === [修改部分 Start] 权重更新 (乘性策略) ===
    % 原代码注释:
    % if i > 5
    %     weak_spots = mask_signal & (rec_amp < 0.8);
    %     step = 0.5 * ones(Nx, Ny);
    %     step(weak_spots) = 2.0;
    %     error = imag_target - rec_amp;
    %     current_weight(mask_signal) = current_weight(mask_signal) + step(mask_signal) .* error(mask_signal);
    %     current_weight(mask_bg) = 0;
    %     current_weight(current_weight < 0) = 0;
    % end

    % 新代码: Multiplicative Weight Update (更强力压制不均匀性)
    if i > 5
        beta = 0.8; % 反馈因子
        % 信号区更新: W_new = W_old * (Target / Actual)^beta
        correction = (target_pad(mask_roi) ./ (rec_amp_norm(mask_roi) + 1e-6)) .^ beta;
        weight_pad(mask_roi) = weight_pad(mask_roi) .* correction;

        % 限制权重上限防止发散
        weight_pad(weight_pad > 10) = 10;

        % 背景区: 强制为0
        weight_pad(mask_dark) = 0;
    end
    current_weight = weight_pad; % 变量名对齐以便阅读
    % === [修改部分 End] ===

    % === [修改部分 Start] Backward 传播 ===
    % 原代码注释:
    % target_constrained = current_weight .* exp(1i * angle(target_field));
    % FFT_target = fftshift(fft2(ifftshift(target_constrained)));
    % board_field = fftshift(ifft2(ifftshift(FFT_target .* H_backward)));
    % board_phase = exp(1i * angle(board_field));

    % 新代码:
    U_target_constrained = weight_pad .* exp(1i * angle(U_target));
    A_target_cons = fftshift(fft2(ifftshift(U_target_constrained)));
    A_source_cons = A_target_cons .* H_backward;
    U_source_new = fftshift(ifft2(ifftshift(A_source_cons)));

    % 全网格更新相位 (下一轮开头会裁剪中心)
    board_phase_pad = U_source_new;
    % === [修改部分 End] ===
end

% === [修改部分 Start] 提取最终相位 ===
% 原代码注释:
% holo_phase = angle(board_phase);

% 新代码: 提取中心有效区域
holo_phase = angle(board_phase_pad(Nx/2+1:Nx/2+Nx, Ny/2+1:Ny/2+Ny));
% === [修改部分 End] ===

figure(1);
subplot(1,2,1); imagesc(x*1e3, x*1e3, imag_target); axis image; colormap gray; title('目标');
subplot(1,2,2); imagesc(x*1e3, x*1e3, holo_phase); axis image; colormap jet; title('IASA 相位 (Pad优化)');

%% 4. k-Wave 介质建模 (保持原样)
fprintf('仿真环境构建\n');
kgrid = kWaveGrid(Nx, dx, Ny, dy, Nz, dz);
% 全水环境 (Homogeneous Medium)
medium.sound_speed = c_water * ones(Nx, Ny, Nz);
medium.density = density_water * ones(Nx, Ny, Nz);
% 完美匹配层的位置
pml_size = 10;
source_z_idx = pml_size + 5;

%% 5. 时间设置 (保持原样)
fprintf('时间设置\n');
cfl = 0.3;
t_end = (Lz * 1.5) / c_water;
kgrid.makeTime(medium.sound_speed, cfl, t_end);

%% 6. 声源定义 (保持原样)
source.p_mask = zeros(Nx, Ny, Nz);
source.p_mask(:, :, source_z_idx) = 1;
fprintf('构建相位调制声源\n');
% 将 2D 相位图展平，匹配 p_mask 的索引顺序
phase_vec = holo_phase(:);
t_vec = kgrid.t_array;
omega = 2 * pi * f0;
% source_sig = sin(omega * t - phase)
source_sig = sin(omega .* t_vec - phase_vec);
% 加一个简单的斜坡窗减少瞬态冲击 (Ramp up)
ramp_pts = round(2 / f0 / kgrid.dt); % 2个周期
window = [linspace(0,1,ramp_pts), ones(1, kgrid.Nt-ramp_pts)];
source.p = source_sig .* window;
source.p_mode = 'dirichlet';

%% 7. Sensor 放置 (保持原样)
fprintf('sensor设置\n');
sensor.mask = zeros(Nx, Ny, Nz);
target_plane_idx = source_z_idx + round(z_target_dist / dz);
sensor.mask(:, :, target_plane_idx) = 1;
% 记录时域信号以便提取稳态
sensor.record = {'p'};
% 仅记录最后 3 个周期以节省内存
sensor.record_start_index = kgrid.Nt - round(3/f0/kgrid.dt);

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

%% 9. 数据处理 (保持原样)
if isfield(sensor_data, 'p')
    fprintf('处理结果\n');
    p_raw = gather(sensor_data.p);
    p_amp = max(p_raw, [], 2);

    % 还原为 2D 图像
    img_recon = reshape(p_amp, Nx, Ny);
    img_recon = img_recon / max(img_recon(:)); % 归一化

    % 可视化对比
    figure(2);
    set(gcf, 'Position', [100, 100, 1000, 400]);

    subplot(1,3,1);
    imagesc(x*1e3, x*1e3, imag_target);
    axis image; colormap gray; title('原始目标');
    xlabel('mm');

    subplot(1,3,2);
    imagesc(x*1e3, x*1e3, img_recon);
    axis image; colormap jet; title('k-Wave 直接相位重建');
    xlabel('mm');

    subplot(1,3,3);
    % 简单的剖面线对比
    center_row = round(Nx/2);
    plot(x*1e3, imag_target(center_row, :), 'k--', 'LineWidth', 1.5); hold on;
    plot(x*1e3, img_recon(center_row, :), 'r-', 'LineWidth', 1.5);
    legend('Target', 'Simulated');
    title('中心剖面线'); grid on;
    xlabel('mm');
end

%% 10. 量化评估 (保持原样)
fprintf('计算量化指标...\n');
R = double(imag_target);                 % 目标图像 (Reference)
A = double(img_recon);                   % 重建图像 (Actual/Reconstructed)
% 归一化到 [0, 1] 区间
R = (R - min(R(:))) / (max(R(:)) - min(R(:)));
A = (A - min(A(:))) / (max(A(:)) - min(A(:)));
% --- 指标 1: Correlation (相关系数) ---
R_mean = mean(R(:));
A_mean = mean(A(:));
numerator = sum(sum((R - R_mean) .* (A - A_mean)));
denominator = sqrt(sum(sum((R - R_mean).^2)) * sum(sum((A - A_mean).^2)));
val_corr = numerator / denominator;
% --- 指标 2: NMSE (归一化均方误差) ---
val_nmse = sum(sum((R - A).^2)) / sum(sum(R.^2));
% --- 指标 3: PSNR (峰值信噪比) ---
mse = mean((R(:) - A(:)).^2);
A_max = max(A(:)); % 归一化后通常为1
if mse == 0
    val_psnr = Inf;
else
    val_psnr = 20 * log10(A_max / sqrt(mse));
end
% --- 指标 4: SSIM (结构相似性) ---
% MATLAB 自带 ssim 函数 (需要 Image Processing Toolbox)
try
    val_ssim = ssim(A, R);
catch
    val_ssim = NaN; % 如果没有工具箱
    warning('SSIM 计算需要 Image Processing Toolbox');
end
% --- IASA参数---
fprintf('========================================\n');
fprintf('IASA参数:\n');
fprintf('迭代数: %.4f\n', epoch);
fprintf('\n');
% --- 仿真参数---
fprintf('========================================\n');
fprintf('仿真参数:\n');
fprintf('目标平面距离: %.4f\n', z_target_dist);
fprintf('完美匹配层大小: %.4f\n', pml_size);
fprintf('source位置: %.2f\n', source_z_idx);
fprintf('目标平面位置: %.4f\n', target_plane_idx);
fprintf('\n');
% --- 量化结果 ---
fprintf('========================================\n');
fprintf('图像重建质量评估:\n');
fprintf('Correlation (接近1越好): %.4f\n', val_corr);
fprintf('NMSE        (越低越好) : %.4f\n', val_nmse);
fprintf('PSNR        (越高越好) : %.2f dB\n', val_psnr);
fprintf('SSIM        (接近1越好): %.4f\n', val_ssim);
