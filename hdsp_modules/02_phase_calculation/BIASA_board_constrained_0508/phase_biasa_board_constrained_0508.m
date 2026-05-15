function ctx = phase_biasa_board_constrained_0508(ctx)
params = ctx.params;
source_mask = ctx.target.source_mask;
phase_map = angle(exp(1i * randn(params.Nx, params.Ny)));
phase_map(~source_mask) = 0;
weight = 0.05 + 1.95 * ctx.target.design_amp;
history = zeros(160, 1);
for iter = 1:160
    projected = board_project_phase_only(phase_map, params, source_mask);
    source = double(source_mask) .* exp(1i * projected.actual_phase);
    target_field = hdsp_asm_propagate(source, params, params.z_target_dist);
    amp = abs(target_field);
    amp_norm = hdsp_normalize01(amp);
    history(iter) = mean(abs(amp_norm(ctx.target.mask) - ctx.target.design_amp(ctx.target.mask)));
    correction = (ctx.target.design_amp ./ (amp_norm + 1e-6)) .^ 0.45;
    correction(~ctx.target.mask) = 0.02;
    target_constrained = weight .* correction .* exp(1i * angle(target_field));
    back_field = hdsp_asm_propagate(target_constrained, params, -params.z_target_dist);
    phase_map = angle(back_field);
    phase_map(~source_mask) = 0;
end
ctx.phase = struct('name', 'BIASA_board_constrained_0508', ...
    'phase_map', phase_map, 'source_mask', source_mask, 'history', history);
end

