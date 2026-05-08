function result = run_board_constrained_iasa_phase_optimizer(initial_phase, target_amp, source_mask, propagator, cfg, label, options)
%RUN_BOARD_CONSTRAINED_IASA_PHASE_OPTIMIZER IASA refinement with board-layer projection.
% Each IASA update is projected through project_phase_to_board so this path
% matches the constrained IASA used by the main flow instead of the older
% continuous-phase-only research helper.
if nargin < 7
    options = struct();
end

phase_step = board_phase_step(cfg);
phase_bias_seed = read_option(options, 'phase_bias_seed', 0);
anchor_eta = read_option(options, 'anchor_eta', cfg.iasa_anchor_eta);
use_dither = read_option(options, 'use_dither', true);
max_layer_index = cfg.min_base_layers + ceil((2*pi) / phase_step) + 1;

[phase_projected, layer_map, phase_bias_seed] = project_phase_to_board( ...
    initial_phase, phase_step, cfg.min_base_layers, source_mask, phase_bias_seed, use_dither);
phase_anchor = phase_projected;

target_pad = zeros(propagator.Nx_pad, propagator.Ny_pad);
target_pad(propagator.center_idx, propagator.center_idx) = target_amp;

line_mask_pad = target_pad > cfg.target_mask_threshold;
halo_mask_pad = false(size(target_pad));
if isfield(options, 'halo_mask') && ~isempty(options.halo_mask)
    halo_crop = logical(options.halo_mask);
    halo_mask_pad(propagator.center_idx, propagator.center_idx) = halo_crop & ~logical(target_amp > cfg.target_mask_threshold);
end
dark_mask_pad = ~(line_mask_pad | halo_mask_pad);

weight_pad = 0.05 + target_pad * 1.95;
history = zeros(cfg.iasa_epochs, 8);
best_quality_score = -inf;
best_epoch = 0;
best_layer_map = layer_map;
best_phase_bias = phase_bias_seed;

for epoch = 1:cfg.iasa_epochs
    source_pad = zeros(propagator.Nx_pad, propagator.Ny_pad);
    source_crop = exp(1i * phase_projected);
    source_crop(~source_mask) = 0;
    source_pad(propagator.center_idx, propagator.center_idx) = source_crop;

    source_spectrum = fftshift(fft2(ifftshift(source_pad)));
    target_field = fftshift(ifft2(ifftshift(source_spectrum .* propagator.H_forward)));
    rec_amp = abs(target_field);
    peak_val = max(rec_amp(line_mask_pad));
    if peak_val == 0
        peak_val = max(rec_amp(:));
    end
    rec_amp_norm = rec_amp / (peak_val + eps);

    if epoch > 5
        correction = (target_pad(line_mask_pad) ./ (rec_amp_norm(line_mask_pad) + 1e-6)) .^ cfg.iasa_beta;
        if isfield(cfg, 'iasa_uniformity_enabled') && cfg.iasa_uniformity_enabled
            target_vals = rec_amp_norm(line_mask_pad);
            target_level = median(target_vals(:));
            uniformity_correction = (target_level ./ (target_vals + 1e-6)) .^ cfg.iasa_uniformity_beta;
            gain_limit = cfg.iasa_uniformity_gain_limit;
            uniformity_correction = min(max(uniformity_correction, 1 / gain_limit), gain_limit);
            correction = correction .* uniformity_correction;
        end
        weight_pad(line_mask_pad) = weight_pad(line_mask_pad) .* correction;
        weight_pad(weight_pad > cfg.iasa_target_gain_limit) = cfg.iasa_target_gain_limit;
        weight_pad(halo_mask_pad) = cfg.iasa_halo_weight;
        weight_pad(dark_mask_pad) = cfg.iasa_dark_weight;
    end

    constrained_target = weight_pad .* exp(1i * angle(target_field));
    target_spectrum = fftshift(fft2(ifftshift(constrained_target)));
    source_back = fftshift(ifft2(ifftshift(target_spectrum .* propagator.H_backward)));
    source_phase_candidate = angle(source_back(propagator.center_idx, propagator.center_idx));

    [phase_projected_raw, ~, phase_bias_seed] = project_phase_to_board( ...
        source_phase_candidate, phase_step, cfg.min_base_layers, source_mask, phase_bias_seed, use_dither);

    if anchor_eta < 1
        blended_complex = (1 - anchor_eta) .* exp(1i * phase_anchor) + ...
            anchor_eta .* exp(1i * phase_projected_raw);
        blended_phase = angle(blended_complex);
    else
        blended_phase = phase_projected_raw;
    end

    [phase_projected, layer_map, phase_bias_seed] = project_phase_to_board( ...
        blended_phase, phase_step, cfg.min_base_layers, source_mask, phase_bias_seed, use_dither);

    focus_crop = rec_amp_norm(propagator.center_idx, propagator.center_idx);
    scores = quick_amp_scores(focus_crop, target_amp, target_amp > cfg.target_mask_threshold);
    history(epoch, :) = scores;

    if scores(8) > best_quality_score
        best_quality_score = scores(8);
        best_epoch = epoch;
        best_layer_map = layer_map;
        best_phase_bias = phase_bias_seed;
    end

end

layer_map = best_layer_map;
phase_bias_seed = best_phase_bias;
final_phase = mod(layer_map * phase_step, 2*pi);
final_phase(~source_mask) = 0;
focus = compute_asm_focus_field(final_phase, source_mask, propagator);

result.label = label;
result.phase = final_phase;
result.layer_map = layer_map;
result.phase_step = phase_step;
result.phase_bias = phase_bias_seed;
result.asm_amp = focus.amp;
result.asm_amp_norm = focus.amp_norm;
result.history = history;
result.optimizer_metrics = struct( ...
    'configured_epochs', cfg.iasa_epochs, ...
    'selected_epoch', best_epoch, ...
    'best_loop_quality_score', best_quality_score, ...
    'uniformity_enabled', cfg.iasa_uniformity_enabled, ...
    'uniformity_beta', cfg.iasa_uniformity_beta, ...
    'uniformity_gain_limit', cfg.iasa_uniformity_gain_limit);
result.max_layer_index = max_layer_index;
end

function phase_step = board_phase_step(cfg)
k_board = 2 * pi * cfg.f0 / cfg.c_board;
k_water = 2 * pi * cfg.f0 / cfg.c_water;
phase_step = abs(k_water - k_board) * cfg.dz;
end

function value = read_option(options, field_name, default_value)
if isfield(options, field_name) && ~isempty(options.(field_name))
    value = options.(field_name);
else
    value = default_value;
end
end

function scores = quick_amp_scores(pred_amp, target_amp, target_mask)
pred = pred_amp / (max(pred_amp(:)) + eps);
target = target_amp / (max(target_amp(:)) + eps);
pred_centered = pred(:) - mean(pred(:));
target_centered = target(:) - mean(target(:));
pcc = sum(pred_centered .* target_centered) / ...
    (sqrt(sum(pred_centered.^2) * sum(target_centered.^2)) + eps);
nmse = sum((pred(:) - target(:)).^2) / (sum(target(:).^2) + eps);
energy_efficiency = sum(pred(target_mask).^2) / (sum(pred(:).^2) + eps);
target_vals = pred(target_mask);
target_cv = std(target_vals(:)) / (mean(target_vals(:)) + eps);
target_p10 = prctile(target_vals(:), 10);
target_p50 = prctile(target_vals(:), 50);
p10_over_p50 = target_p10 / (target_p50 + eps);
target_peak_over_mean = max(target_vals(:)) / (mean(target_vals(:)) + eps);
quality_score = pcc + energy_efficiency + p10_over_p50 - target_cv - 0.10 * target_peak_over_mean;
scores = [pcc, nmse, energy_efficiency, target_cv, p10_over_p50, max(pred(:)), target_peak_over_mean, quality_score];
end
