function phase = run_weighted_iasa(ctx, iterations, signal_gain, dark_floor, name)
params = ctx.params;
source_mask = ctx.target.source_mask;
source_phase = angle(exp(1i * randn(params.Nx, params.Ny)));
source_phase(~source_mask) = 0;
target_amp = ctx.target.design_amp;
weight = dark_floor + signal_gain * target_amp;
history = zeros(iterations, 1);
for iter = 1:iterations
    source = double(source_mask) .* exp(1i * source_phase);
    target_field = hdsp_asm_propagate(source, params, params.z_target_dist);
    rec_amp = hdsp_normalize01(abs(target_field));
    err = target_amp - rec_amp;
    history(iter) = mean(abs(err(ctx.target.mask)));
    weight(ctx.target.mask) = max(weight(ctx.target.mask) + 0.15 * err(ctx.target.mask), 0.01);
    weight(~ctx.target.mask) = dark_floor;
    constrained = weight .* exp(1i * angle(target_field));
    back_field = hdsp_asm_propagate(constrained, params, -params.z_target_dist);
    source_phase = angle(back_field);
    source_phase(~source_mask) = 0;
end
phase = struct('name', name, 'phase_map', source_phase, 'source_mask', source_mask, 'history', history);
end

