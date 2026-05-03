function export_exit_amp_surrogate_run(export_dir, run_meta, run_metrics, thickness_map, thickness_grad_norm, ...
    p_exit_amp_norm, circle_mask_board, x, y, dx, net_num_board, aperture_edge_distance_mm, ...
    local_thickness_mean, local_thickness_std, complex_ratio_same, complex_ratio_opposite)

if nargin < 15
    complex_ratio_same = [];
end
if nargin < 16
    complex_ratio_opposite = [];
end

patch_size = run_meta.patch_size;
patch_radius = floor(patch_size / 2);
sample_stride = max(1, run_meta.sample_stride);
max_samples_per_run = run_meta.max_samples_per_run;
sample_mode = 'grid';
if isfield(run_meta, 'sample_mode') && ~isempty(run_meta.sample_mode)
    sample_mode = char(run_meta.sample_mode);
end
sample_seed = 9426;
if isfield(run_meta, 'sample_seed') && ~isempty(run_meta.sample_seed)
    sample_seed = double(run_meta.sample_seed);
end

valid_mask = circle_mask_board;
[row_idx_all, col_idx_all] = find(valid_mask);
switch lower(sample_mode)
    case 'random'
        rng(sample_seed, 'twister');
        sample_order = randperm(numel(row_idx_all));
        if max_samples_per_run > 0
            sample_order = sample_order(1:min(numel(sample_order), max_samples_per_run));
        end
        sample_order = sort(sample_order);
    otherwise
        sample_order = 1:sample_stride:numel(row_idx_all);
        if max_samples_per_run > 0 && numel(sample_order) > max_samples_per_run
            sample_pick = round(linspace(1, numel(sample_order), max_samples_per_run));
            sample_order = sample_order(sample_pick);
        end
end
row_idx = row_idx_all(sample_order);
col_idx = col_idx_all(sample_order);

num_samples = numel(row_idx);
thickness_patches = zeros(patch_size, patch_size, num_samples, 'single');
feature_vector = zeros(num_samples, 10, 'single');
target_exit_amp = zeros(num_samples, 1, 'single');
target_ratio_same_real = zeros(num_samples, 1, 'single');
target_ratio_same_imag = zeros(num_samples, 1, 'single');
target_ratio_opposite_real = zeros(num_samples, 1, 'single');
target_ratio_opposite_imag = zeros(num_samples, 1, 'single');
target_phase_error_same = zeros(num_samples, 1, 'single');
target_phase_error_opposite = zeros(num_samples, 1, 'single');
x_mm = zeros(num_samples, 1, 'single');
y_mm = zeros(num_samples, 1, 'single');
radius_mm = zeros(num_samples, 1, 'single');
edge_distance_mm = zeros(num_samples, 1, 'single');
row_idx_export = single(row_idx(:));
col_idx_export = single(col_idx(:));

thickness_pad = padarray(single(thickness_map), [patch_radius, patch_radius], 'replicate', 'both');
grad_pad = padarray(single(thickness_grad_norm), [patch_radius, patch_radius], 'replicate', 'both');

for sample_idx = 1:num_samples
    r = row_idx(sample_idx);
    c = col_idx(sample_idx);
    r_pad = r + patch_radius;
    c_pad = c + patch_radius;

    patch_thickness = thickness_pad(r_pad-patch_radius:r_pad+patch_radius, c_pad-patch_radius:c_pad+patch_radius);
    patch_grad = grad_pad(r_pad-patch_radius:r_pad+patch_radius, c_pad-patch_radius:c_pad+patch_radius);

    thickness_patches(:, :, sample_idx) = patch_thickness;
    target_exit_amp(sample_idx) = single(p_exit_amp_norm(r, c));
    if ~isempty(complex_ratio_same)
        ratio_same_now = complex_ratio_same(r, c);
        ratio_opposite_now = complex_ratio_opposite(r, c);
        target_ratio_same_real(sample_idx) = single(real(ratio_same_now));
        target_ratio_same_imag(sample_idx) = single(imag(ratio_same_now));
        target_ratio_opposite_real(sample_idx) = single(real(ratio_opposite_now));
        target_ratio_opposite_imag(sample_idx) = single(imag(ratio_opposite_now));
        target_phase_error_same(sample_idx) = single(angle(ratio_same_now));
        target_phase_error_opposite(sample_idx) = single(angle(ratio_opposite_now));
    end
    x_mm(sample_idx) = single(x(c) * 1e3);
    y_mm(sample_idx) = single(y(r) * 1e3);
    radius_mm(sample_idx) = single(hypot(x(c), y(r)) * 1e3);
    edge_distance_mm(sample_idx) = single(aperture_edge_distance_mm(r, c));

    feature_vector(sample_idx, :) = single([
        thickness_map(r, c) * 1e3, ...
        thickness_grad_norm(r, c), ...
        local_thickness_mean(r, c) * 1e3, ...
        local_thickness_std(r, c), ...
        radius_mm(sample_idx), ...
        edge_distance_mm(sample_idx), ...
        net_num_board(r, c), ...
        mean(patch_thickness(:)) * 1e3, ...
        std(patch_thickness(:)) * 1e3, ...
        mean(patch_grad(:))]);
end

layer_idx = net_num_board(valid_mask);
[X_radius, Y_radius] = meshgrid(x, y);
radius_field_mm = hypot(X_radius, Y_radius) * 1e3;
radius_valid = radius_field_mm(valid_mask);
edge_valid = aperture_edge_distance_mm(valid_mask);
exit_valid = p_exit_amp_norm(valid_mask);

summary_stats = struct();
summary_stats.layer_ids = unique(layer_idx(:));
summary_stats.layer_mean_amp = accumarray(double(layer_idx(:)), exit_valid(:), [], @mean);
summary_stats.radius_bin_edges_mm = single(linspace(min(radius_valid), max(radius_valid), 9));
summary_stats.edge_bin_edges_mm = single(linspace(min(edge_valid), max(edge_valid), 9));
summary_stats.num_samples = num_samples;
summary_stats.patch_size = patch_size;
summary_stats.sample_stride = sample_stride;
summary_stats.sample_mode = sample_mode;
summary_stats.sample_seed = sample_seed;
summary_stats.dx_mm = single(dx * 1e3);

timestamp_tag = char(datetime('now', 'Format', 'yyyyMMdd_HHmmss'));
run_name = sprintf('exit_amp_run_%s_%s', run_meta.run_label, timestamp_tag);
sample_file = fullfile(export_dir, [run_name '_samples.mat']);
summary_file = fullfile(export_dir, [run_name '_summary.mat']);
material_params = single([ ...
    run_meta.c_water, run_meta.density_water, run_meta.alpha_coeff_water, ...
    run_meta.c_board, run_meta.density_board, run_meta.alpha_coeff_board, ...
    run_meta.c_pdms, run_meta.density_pdms, run_meta.alpha_coeff_pdms]);

save(sample_file, 'thickness_patches', 'feature_vector', 'target_exit_amp', ...
    'target_ratio_same_real', 'target_ratio_same_imag', ...
    'target_ratio_opposite_real', 'target_ratio_opposite_imag', ...
    'target_phase_error_same', 'target_phase_error_opposite', ...
    'x_mm', 'y_mm', 'radius_mm', 'edge_distance_mm', 'row_idx_export', 'col_idx_export', ...
    'material_params', 'run_meta');
save(summary_file, 'run_meta', 'run_metrics', 'summary_stats');
fprintf('研究样本已导出: %s\n', sample_file);
fprintf('研究摘要已导出: %s\n', summary_file);
end
