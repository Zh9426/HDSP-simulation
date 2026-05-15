function ctx = board_continuous_late_round_0223(ctx)
params = ctx.params;
phase = angle(exp(1i * ctx.phase.phase_map));
wrapped = mod(phase, 2 * pi);
layers = round(wrapped / params.phase_step);
layers = min(max(layers, params.min_base_layers), params.max_board_layers);
layers(~ctx.phase.source_mask) = 0;
actual_phase = mod(layers * params.phase_step, 2 * pi);
ctx.board = struct();
ctx.board.name = 'continuous_late_round_0223';
ctx.board.layer_map = layers;
ctx.board.thickness_map = layers * params.layer_thickness;
ctx.board.actual_phase = actual_phase;
ctx.board.residual = angle(exp(1i * (actual_phase - phase)));
end

