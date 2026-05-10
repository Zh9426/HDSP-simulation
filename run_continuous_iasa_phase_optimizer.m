function result = run_continuous_iasa_phase_optimizer(initial_phase, target_amp, source_mask, propagator, cfg, label, mode)
%RUN_CONTINUOUS_IASA_PHASE_OPTIMIZER Continuous-phase GS / weighted IASA optimizer.
% The optimizer uses a phase-only uniform source aperture. It deliberately
% avoids board-layer projection so GS/WIASA can be compared against BIASA.
mode = lower(string(mode));
if mode ~= "gs" && mode ~= "wiasa"
    error('Unsupported continuous optimizer mode: %s', mode);
end

phase_now = wrap_phase(initial_phase);
phase_now(~source_mask) = 0;

target_pad = zeros(propagator.Nx_pad, propagator.Ny_pad);
target_pad(propagator.center_idx, propagator.center_idx) = target_amp;

line_mask_pad = target_pad > cfg.target_mask_threshold;
dark_mask_pad = ~line_mask_pad;
weight_pad = 0.05 + target_pad * 1.95;

history = zeros(cfg.iasa_epochs, 8);
best_quality_score = -inf;
best_epoch = 0;
best_phase = phase_now;

for epoch = 1:cfg.iasa_epochs
    source_pad = zeros(propagator.Nx_pad, propagator.Ny_pad);
    source_crop = exp(1i * phase_now);
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

    if mode == "gs"
        constrained_amp = target_pad;
    else
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
            weight_pad(dark_mask_pad) = cfg.iasa_dark_weight;
        end
        constrained_amp = weight_pad;
    end

    constrained_target = constrained_amp .* exp(1i * angle(target_field));
    target_spectrum = fftshift(fft2(ifftshift(constrained_target)));
    source_back = fftshift(ifft2(ifftshift(target_spectrum .* propagator.H_backward)));
    phase_candidate = angle(source_back(propagator.center_idx, propagator.center_idx));
    phase_now = wrap_phase(phase_candidate);
    phase_now(~source_mask) = 0;

    focus_crop = rec_amp_norm(propagator.center_idx, propagator.center_idx);
    scores = quick_amp_scores(focus_crop, target_amp, target_amp > cfg.target_mask_threshold);
    history(epoch, :) = scores;

    if scores(8) > best_quality_score
        best_quality_score = scores(8);
        best_epoch = epoch;
        best_phase = phase_now;
    end
end

focus = compute_asm_focus_field(best_phase, source_mask, propagator);

result.label = label;
result.phase = best_phase;
result.asm_amp = focus.amp;
result.asm_amp_norm = focus.amp_norm;
result.history = history;
result.optimizer_metrics = struct( ...
    'configured_epochs', cfg.iasa_epochs, ...
    'selected_epoch', best_epoch, ...
    'best_loop_quality_score', best_quality_score, ...
    'optimizer_mode', char(mode), ...
    'board_projection', false);
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
