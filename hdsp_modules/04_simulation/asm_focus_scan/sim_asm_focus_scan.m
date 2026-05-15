function ctx = sim_asm_focus_scan(ctx)
params = ctx.params;
source = double(ctx.phase.source_mask) .* exp(1i * ctx.board.actual_phase);
focus = hdsp_asm_propagate(source, params, params.z_target_dist);
exit_field = source;
focus_amp_norm = hdsp_normalize01(abs(focus));
ctx.field = struct();
ctx.field.name = 'asm_focus_scan';
ctx.field.status = "asm_only";
ctx.field.focus_complex = focus;
ctx.field.focus_amp = focus_amp_norm * params.target_pressure_pa;
ctx.field.exit_complex = exit_field;
ctx.field.exit_amp = hdsp_normalize01(abs(exit_field)) * params.target_pressure_pa;
ctx.field.p_3d = [];
end

