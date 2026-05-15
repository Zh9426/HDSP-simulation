function ctx = diag_exit_field_basic(ctx)
mask = ctx.phase.source_mask;
exit_amp = ctx.field.exit_amp;
actual_phase = ctx.board.actual_phase;
ctx.exit_diagnostic = struct();
ctx.exit_diagnostic.name = 'basic_exit_field';
ctx.exit_diagnostic.enabled = true;
ctx.exit_diagnostic.status = "ok";
ctx.exit_diagnostic.mean_exit_amp = mean(exit_amp(mask));
ctx.exit_diagnostic.std_exit_amp = std(exit_amp(mask));
ctx.exit_diagnostic.phase_residual_mean_abs = mean(abs(ctx.board.residual(mask)));
ctx.exit_diagnostic.unique_layers = numel(unique(ctx.board.layer_map(mask)));
ctx.exit_diagnostic.actual_phase = actual_phase;
end

