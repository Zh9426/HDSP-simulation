function result = run_iasa_phase_optimizer(initial_phase, target_amp, source_mask, propagator, cfg, label)
%RUN_IASA_PHASE_OPTIMIZER Continuous-phase IASA refinement.
target_pad = zeros(propagator.Nx_pad, propagator.Ny_pad);
target_pad(propagator.center_idx, propagator.center_idx) = target_amp;

target_mask_pad = target_pad > cfg.target_mask_threshold;
dark_mask_pad = ~target_mask_pad;
weight_pad = cfg.iasa_dark_weight * ones(propagator.Nx_pad, propagator.Ny_pad);
weight_pad(target_mask_pad) = max(target_pad(target_mask_pad), cfg.iasa_dark_weight);

phase_now = wrap_phase(initial_phase);
history = zeros(cfg.iasa_epochs, 3);

for epoch = 1:cfg.iasa_epochs
    source_pad = zeros(propagator.Nx_pad, propagator.Ny_pad);
    source_crop = exp(1i * phase_now);
    source_crop(~source_mask) = 0;
    source_pad(propagator.center_idx, propagator.center_idx) = source_crop;

    source_spectrum = fftshift(fft2(ifftshift(source_pad)));
    target_field = fftshift(ifft2(ifftshift(source_spectrum .* propagator.H_forward)));
    target_amp_now = abs(target_field);
    target_amp_norm = target_amp_now / (max(target_amp_now(:)) + eps);

    if epoch > 5
        target_vals = target_amp_norm(target_mask_pad);
        desired_vals = target_pad(target_mask_pad);
        correction = (desired_vals ./ (target_vals + 1e-6)) .^ cfg.iasa_beta;
        correction = min(correction, cfg.iasa_target_gain_limit);
        weight_pad(target_mask_pad) = weight_pad(target_mask_pad) .* correction;
        weight_pad(dark_mask_pad) = cfg.iasa_dark_weight;
    end

    constrained_target = weight_pad .* exp(1i * angle(target_field));
    target_spectrum = fftshift(fft2(ifftshift(constrained_target)));
    source_back = fftshift(ifft2(ifftshift(target_spectrum .* propagator.H_backward)));
    phase_candidate = angle(source_back(propagator.center_idx, propagator.center_idx));
    phase_candidate(~source_mask) = 0;
    phase_now = wrap_phase(phase_candidate);

    focus_crop = target_amp_norm(propagator.center_idx, propagator.center_idx);
    history(epoch, :) = quick_amp_scores(focus_crop, target_amp);
end

focus = compute_asm_focus_field(phase_now, source_mask, propagator);
result.label = label;
result.phase = phase_now;
result.asm_amp = focus.amp;
result.asm_amp_norm = focus.amp_norm;
result.history = history;
end

function scores = quick_amp_scores(pred_amp, target_amp)
pred = pred_amp / (max(pred_amp(:)) + eps);
target = target_amp / (max(target_amp(:)) + eps);
pred_centered = pred(:) - mean(pred(:));
target_centered = target(:) - mean(target(:));
pcc = sum(pred_centered .* target_centered) / ...
    (sqrt(sum(pred_centered.^2) * sum(target_centered.^2)) + eps);
nmse = sum((pred(:) - target(:)).^2) / (sum(target(:).^2) + eps);
target_mask = target > 0.45;
energy_efficiency = sum(pred(target_mask).^2) / (sum(pred(:).^2) + eps);
scores = [pcc, nmse, energy_efficiency];
end
