clearvars; close all; clc;

%% 网格及参数设定
Nx = 256;
Lx = 40e-3;
Ny = Nx; Ly = Lx;
System_Offset = 2.03e-3;
z_target_dist = 30e-3; % 目标距离
z_target_dist = z_target_dist+System_Offset;

f0 = 2.28e6;
c_water = 1480;
c_board = 2430;
density_water = 997;
density_board = 1100;


lambda_water = c_water / f0;

dx = Lx / Nx;
dy = dx;
dz = dx;

Nz =384;
Lz = Nz * dz;
x = (-Nx/2 : Nx/2-1) * dx;

fprintf('网格尺寸: %d x %d x %d, dx=%.4f mm\n', Nx, Ny, Nz, dx*1e3);
%% 目标定义
imag_target = zeros(Nx, Ny);
outer_size = 100; % 外框大小
inner_size = 40;  % 内孔大小

cx = round(Nx/2);
cy = round(Ny/2);

r_out = round(outer_size/2);
r_in  = round(inner_size/2);

imag_target(cx-r_out : cx+r_out, cy-r_out : cy+r_out) = 1;
imag_target(cx-r_in  : cx+r_in,  cy-r_in  : cy+r_in)  = 0;
%% IASA 迭代
%算子定义
k_water = 2 * pi / lambda_water;
dk = 2 * pi / Lx;
kx = (-Nx/2 : Nx/2-1) * dk;
[Kx, Ky] = meshgrid(kx, kx);
Kz_sq = k_water^2 - Kx.^2 - Ky.^2;
Kz_sq(Kz_sq < 0) = 0;

H_forward = exp(1i * sqrt(Kz_sq) * z_target_dist);
H_backward = exp(-1i * sqrt(Kz_sq) * z_target_dist);

% 初始相位
rng(9426);
board_phase = exp(1i * rand(Nx, Nx) * 2 * pi);
%board_phase = exp(1i * ones(Nx, Nx)*2 * pi);
epoch = 100;
current_weight = imag_target*2;
mask_signal = (imag_target == 1); % 信号区
mask_bg = (imag_target == 0);% 背景区域掩膜
alpha = 1.5;
%开始迭代
fprintf('运行 IASA...\n');
for i = 1:epoch
    % Forward
    FFT_board = fftshift(fft2(ifftshift(board_phase)));
    target_field = fftshift(ifft2(ifftshift(FFT_board .* H_forward)));

    rec_amp = abs(target_field);
    % 归一化 (每一轮都重新归一化，模拟能量饱和)
    rec_amp = rec_amp / max(rec_amp(:));

    % === 通用权重更新逻辑 ===
    if i > 5
        weak_spots = mask_signal & (rec_amp < 0.8);

        % 对弱点进行"惩罚性"增强 (权重猛增)
        % 正常的点 (0.8~1.0) 保持温和调整
        step = 0.5 * ones(Nx, Ny);
        step(weak_spots) = 2.0; % 对弱点下猛药

        error = imag_target - rec_amp;
        current_weight(mask_signal) = current_weight(mask_signal) + step(mask_signal) .* error(mask_signal);

        % 2. 背景区策略：绝对压制
        % 强制背景区权重为0 (或者极小值)，提高对比度
        current_weight(mask_bg) = 0;

        % 物理约束
        current_weight(current_weight < 0) = 0;
    end

    % Constraint
    target_constrained = current_weight .* exp(1i * angle(target_field));

    % Backward
    FFT_target = fftshift(fft2(ifftshift(target_constrained)));
    board_field = fftshift(ifft2(ifftshift(FFT_target .* H_backward)));

    % Source Constraint
    board_phase = exp(1i * angle(board_field));
end
holo_phase = angle(board_phase);

figure(1);
subplot(1,2,1); imagesc(x*1e3, x*1e3,imag_target); axis image; colormap gray;
title('1. 目标图像'); xlabel('mm');
subplot(1,2,2); imagesc(x*1e3, x*1e3, holo_phase); axis image; colormap jet;
title('2. IASA全息相位图'); xlabel('mm'); colorbar;

%% 相位转厚度
k_board = 2 * pi * f0 / c_board;
k_diff = k_water - k_board;
phase_unwrapped = holo_phase + pi;
%% 构建厚度
thickness_map = phase_unwrapped / k_diff;
thickness_map = imgaussfilt(thickness_map, 0.4);
min_base = 3 * dx;
thickness_map = thickness_map + min_base;

figure(2);
surf(x*1e3, x*1e3, thickness_map*1e3);
shading interp; colormap parula; colorbar;
title('透镜厚度分布 (mm)');
xlabel('x (mm)'); ylabel('y (mm)'); zlabel('Height (mm)');
%% k-Wave 介质建模
%定义声速和密度
kgrid = kWaveGrid(Nx, dx, Ny, dy, Nz, dz);
medium.sound_speed = c_water * ones(Nx, Ny, Nz);
medium.density = density_water * ones(Nx, Ny, Nz);
pml_size = 10;
source_z_idx = pml_size + 5;

%% 厚度构建-正向构建
thickest = max(thickness_map(:));
z_board_stat_idx = source_z_idx + 1;
net_num_board = round(thickness_map / dz);
fprintf('构建透镜...\n');
for i = 1:Nx
    for j = 1:Ny
        n_layers = net_num_board(i, j);
        if n_layers > 0
            % 反向生长
            z_start = z_board_stat_idx;
            z_end = z_board_stat_idx + n_layers-1;

            medium.sound_speed(i, j, z_start:z_end) = c_board;
            medium.density(i, j, z_start:z_end) = density_board;
        end
    end
end

%% 时间
cfl = 0.3;
t_end = (Lz * 1.5) / c_water;
kgrid.makeTime(medium.sound_speed, cfl, t_end);

%% 声源定义
source.p_mask = zeros(Nx, Ny, Nz);
source.p_mask(:, :, source_z_idx) = 1;
source.p = sin(2 * pi * f0 * kgrid.t_array);
source.p_mode = 'dirichlet';

%% sensor
sensor.mask = zeros(Nx, Ny, Nz);
% z_target_idx = z_board_stat_idx + round(thickest / dz ) + round(z_target_dist / dz);
% if z_target_idx > Nz
%     error('网格 Z 轴太短，请增加 Lz');
% end
% sensor.mask(:, :, z_target_idx) = 1;
% sensor.record = {'p_max'};

%多sensordebug
z_board_exit_idx = z_board_stat_idx + round(thickest/dz) + 1;
z_target_idx = z_board_exit_idx + round(z_target_dist / dz);

%计算目标扫描范围 (前后 6mm)
z_target_center_idx = z_board_exit_idx + round(z_target_dist / dz);
scan_range_idx = round(6e-3 / dz);
z_scan_start = z_target_center_idx - scan_range_idx;
z_scan_end = z_target_center_idx + scan_range_idx;

% 安全检查
if z_scan_end > Nz - pml_size
    warning('扫描范围超出网格，已自动截断');
    z_scan_end = Nz - pml_size;
end

% [Sensor 1] 出口平面 (用于相位对比)
sensor.mask(:, :, z_board_exit_idx) = 1;

% [Sensor 2] 目标体积扫描
sensor.mask(:, :, z_scan_start:z_scan_end) = 1;

sensor.record = {'p'};
t_period = 1/f0;
sensor.record_start_index = kgrid.Nt - round(3 * t_period / kgrid.dt);

fprintf('Sensor 配置:\n  - 出口校验面 Z: %d\n  - 目标扫描 Z: %d -> %d\n', ...
    z_board_exit_idx, z_scan_start, z_scan_end);
%% 仿真
% 参数
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

% %% [修改] 结果分析与可视化 (FFT处理 + Z-Scan + 相位验证)
% if isfield(sensor_data, 'p')
%     fprintf('仿真完成，开始后处理...\n');
%
%     % 1. 提取复振幅 (FFT)
%     p_raw = gather(sensor_data.p);
%     [~, Nt_rec] = size(p_raw);
%     % 计算基频分量
%     p_fft = fft(p_raw, [], 2);
%     [~, f_idx] = min(abs( (0:Nt_rec-1)/Nt_rec/kgrid.dt - f0 ));
%     p_complex = p_fft(:, f_idx);
%
%     % 2. 还原 3D 场数据
%     p_field_3d = zeros(Nx, Ny, Nz);
%     mask_indices = find(sensor.mask);
%     p_field_3d(mask_indices) = p_complex;
%
%     % === 验证一：出口相位校验 ===
%     sim_exit_complex = p_field_3d(:, :, z_board_exit_idx);
%     sim_exit_phase = angle(sim_exit_complex);
%     % 归一化相位以进行纹理对比 (去除活塞相位差)
%     sim_exit_phase_norm = angle(exp(1i * (sim_exit_phase - mean(sim_exit_phase(:)))));
%     holo_phase_norm = angle(exp(1i * (holo_phase - mean(holo_phase(:)))));
%
%     figure(5); clf;
%     subplot(1,2,1); imagesc(holo_phase_norm); axis image; colormap jet;
%     title('设计相位 (IASA)');
%     subplot(1,2,2); imagesc(sim_exit_phase_norm); axis image; colormap jet;
%     title('仿真出口相位 (Check)');
%     sgtitle('透镜构建质量校验');
%
%     % === 验证二：Z-Scan 寻找最佳聚焦 ===
%     % 提取扫描区域的强度体积
% scan_vol = abs(p_field_3d(:, :, z_scan_start:z_scan_end));
%     [~, ~, n_slices] = size(scan_vol);
%
%     % 准备掩膜 (Mask)
%     % imag_target 是我们设计的目标(口字)，0和1
%     mask_signal = (imag_target > 0.5); % 目标区域 (口字的边框)
%     mask_bg = (imag_target < 0.5);     % 背景区域 (中间空心 + 外部)
%
%     contrast_curve = zeros(1, n_slices);
%     avg_signal_curve = zeros(1, n_slices);
%     avg_bg_curve = zeros(1, n_slices);
%
%     % 逐层计算您的"自定义指标"
%     for k = 1:n_slices
%         slice_img = scan_vol(:, :, k);
%
%         % 计算区域平均声强
%         avg_signal = mean(slice_img(mask_signal)); % 目标区域平均
%         avg_bg = mean(slice_img(mask_bg));         % 背景区域平均
%
%         % === 您的核心算法 ===
%         % 评分 = 目标越亮越好 + 背景越暗越好
%         % 数学上等同于：最大化 (信号平均 - 背景平均)
%         contrast_curve(k) = avg_signal - avg_bg;
%
%         % 记录中间变量以便绘图分析
%         avg_signal_curve(k) = avg_signal;
%         avg_bg_curve(k) = avg_bg;
%     end
%
%     % 绘制分析曲线
%     z_axis_scan = ((z_scan_start:z_scan_end) - z_board_exit_idx) * dz * 1e3;
%
%     figure(6); clf;
%     yyaxis left;
%     plot(z_axis_scan, contrast_curve, 'b-o', 'LineWidth', 2);
%     ylabel('聚焦评分 (Contrast Score)');
%     xlabel('距离透镜出口 (mm)');
%
%     yyaxis right;
%     plot(z_axis_scan, avg_signal_curve, 'r--', 'LineWidth', 1);
%     hold on;
%     plot(z_axis_scan, avg_bg_curve, 'k:', 'LineWidth', 1);
%     ylabel('平均声强 (Abs)');
%     legend('聚焦评分 (Signal-BG)', '目标区平均 (Signal)', '背景区平均 (BG)');
%     grid on;
%     title('Z-Scan 智能聚焦分析 (基于区域对比度)');
%
%     % 找到评分最高的焦面
%     [~, max_idx] = max(contrast_curve);
%     best_z_idx = z_scan_start + max_idx - 1;
%     best_z_mm = z_axis_scan(max_idx);
%
%     fprintf('>>> 最佳焦面位置: %.2f mm (基于最大对比度)\n', best_z_mm);
%     fprintf('    该平面目标区强度: %.4f, 背景区强度: %.4f\n', ...
%         avg_signal_curve(max_idx), avg_bg_curve(max_idx));
%
%     % === 最终成像结果 ===
%     best_img = abs(p_field_3d(:, :, best_z_idx));
%
%     max_intensity = max(best_img(:));
%     fprintf('>>> 聚焦平面最大声强: %.2f (预期应该很高)\n', max_intensity);
%
%     figure(4); clf;
%     imagesc(kgrid.y_vec*1e3, kgrid.x_vec*1e3, best_img);
%     axis image; colormap jet;
%     title(['最佳对比度平面 @ Z=' num2str(best_z_mm, '%.2f') 'mm']);
%     xlabel('y (mm)'); ylabel('x (mm)');
%
%     % 切除底噪显示
%     best_img_norm = best_img / max(best_img(:));
%     figure(7); clf;
%     imagesc(kgrid.y_vec*1e3, kgrid.x_vec*1e3, best_img_norm);
%     axis image; colormap jet;
%     clim([0.1, 1]);
%     title('去除底噪后的最佳重建');
%     xlabel('y (mm)'); ylabel('x (mm)');
% end

%% [修改] 结果分析与可视化 (FFT处理 + Z-Scan + 相位严格对齐 + 固化模拟)
if isfield(sensor_data, 'p')
    fprintf('仿真完成，开始后处理...\n');

    % --- 1. 提取复振幅 (FFT) ---
    p_raw = gather(sensor_data.p);
    [~, Nt_rec] = size(p_raw);
    % 计算基频分量
    p_fft = fft(p_raw, [], 2);
    [~, f_idx] = min(abs( (0:Nt_rec-1)/Nt_rec/kgrid.dt - f0 ));
    p_complex = p_fft(:, f_idx);

    % --- 2. 还原 3D 场数据 ---
    p_field_3d = zeros(Nx, Ny, Nz);
    mask_indices = find(sensor.mask);
    p_field_3d(mask_indices) = p_complex;

    % --- 3. 验证一：出口相位校验 (严格对齐版) ---
    sim_exit_complex = p_field_3d(:, :, z_board_exit_idx);
    sim_exit_phase_raw = angle(sim_exit_complex);

    % [核心修改] 复数域相位对齐 (彻底解决色差问题)
    % 计算 (仿真 / 设计) 的平均复数因子，提取全局相位差
    complex_diff = exp(1i * sim_exit_phase_raw) ./ exp(1i * holo_phase);
    global_phase_offset = angle(mean(complex_diff(:)));

    % 反向旋转仿真相位，使其与设计相位重合
    sim_exit_phase_aligned = angle(exp(1i * (sim_exit_phase_raw - global_phase_offset)));

    figure(5); clf;
    set(gcf, 'Position', [100, 100, 1000, 400]);

    subplot(1,3,1);
    imagesc(holo_phase); axis image; colormap hsv; % [修改] 使用 HSV 循环色
    clim([-pi, pi]); colorbar;
    title('1. 设计相位 (IASA)');

    subplot(1,3,2);
    imagesc(sim_exit_phase_aligned); axis image; colormap hsv;
    clim([-pi, pi]); colorbar; % 锁定范围，确保颜色一致
    title('2. 仿真出口相位 (已对齐)');

    subplot(1,3,3);
    % 计算残差图 (越黑越好)
    phase_error = angle(exp(1i * (sim_exit_phase_aligned - holo_phase)));
    imagesc(abs(phase_error)); axis image; colormap gray;
    clim([0, 1]); colorbar;
    title('3. 差异残差 (黑=完美)');
    sgtitle('透镜构建质量校验 (相位)');

    % --- 4. 验证二：Z-Scan 寻找最佳聚焦 (区域对比度法) ---
    scan_vol = abs(p_field_3d(:, :, z_scan_start:z_scan_end));
    [~, ~, n_slices] = size(scan_vol);

    % 准备掩膜 (Mask)
    mask_signal = (imag_target > 0.5); % 目标区域
    mask_bg = (imag_target < 0.5);     % 背景区域

    contrast_curve = zeros(1, n_slices);
    avg_signal_curve = zeros(1, n_slices);
    avg_bg_curve = zeros(1, n_slices);

    for k = 1:n_slices
        slice_img = scan_vol(:, :, k);
        avg_signal = mean(slice_img(mask_signal));
        avg_bg = mean(slice_img(mask_bg));

        % 评分 = 信号平均 - 背景平均
        contrast_curve(k) = avg_signal - avg_bg;
        avg_signal_curve(k) = avg_signal;
        avg_bg_curve(k) = avg_bg;
    end

    % 绘制分析曲线
    z_axis_scan = ((z_scan_start:z_scan_end) - z_board_exit_idx) * dz * 1e3;

    figure(6); clf;
    yyaxis left;
    plot(z_axis_scan, contrast_curve, 'b-o', 'LineWidth', 2);
    ylabel('聚焦评分 (Contrast Score)');
    xlabel('距离透镜出口 (mm)');

    yyaxis right;
    plot(z_axis_scan, avg_signal_curve, 'r--', 'LineWidth', 1);
    hold on;
    plot(z_axis_scan, avg_bg_curve, 'k:', 'LineWidth', 1);
    ylabel('平均声强 (Abs)');
    legend('聚焦评分', '目标区强度', '背景区强度');
    grid on;
    title('Z-Scan 智能聚焦分析');

    % 找到评分最高的焦面
    [~, max_idx] = max(contrast_curve);
    best_z_idx = z_scan_start + max_idx - 1;
    best_z_mm = z_axis_scan(max_idx);

    fprintf('>>> 最佳焦面位置: %.2f mm\n', best_z_mm);

    % --- 5. 最终成像与打印模拟 ---
    best_img = abs(p_field_3d(:, :, best_z_idx));
    max_intensity = max(best_img(:));

    % 归一化
    best_img_norm = best_img / max_intensity;

    figure(4); clf;
    set(gcf, 'Position', [100, 100, 1000, 400]);

    % (1) 声强热图
    subplot(1,2,1);
    imagesc(kgrid.y_vec*1e3, kgrid.x_vec*1e3, best_img_norm);
    axis image; colormap jet; colorbar;
    clim([0, 1]);
    title(['最佳焦面声强 @ Z=' num2str(best_z_mm, '%.2f') 'mm']);
    xlabel('y (mm)'); ylabel('x (mm)');

    % (2) [新增] 固化模拟 (Thresholding)
    % 假设阈值为 0.5 (可根据需要调整)
    Print_Threshold = 0.5;
    cured_simulation = best_img_norm > Print_Threshold;

    subplot(1,2,2);
    imagesc(kgrid.y_vec*1e3, kgrid.x_vec*1e3, cured_simulation);
    axis image; colormap jet;
    title(['打印固化模拟 (阈值=' num2str(Print_Threshold) ')']);
    xlabel('y (mm)'); ylabel('x (mm)');

    % --- 6. [新增] 剖面线检查 (Flat-Top Check) ---
    % 检查中心横截面，看是否平顶
    center_row = round(Nx/2);
    profile_line = best_img_norm(center_row, :);

    figure(8); clf;
    plot(kgrid.y_vec*1e3, profile_line, 'LineWidth', 2);
    hold on;
    yline(Print_Threshold, 'r--', '固化阈值', 'LineWidth', 1.5);
    grid on;
    ylim([0, 1.1]);
    xlabel('Y 位置 (mm)'); ylabel('归一化声强');
    title('中心剖面线 (检查平顶度)');
    legend('声强分布', '阈值线');
end
