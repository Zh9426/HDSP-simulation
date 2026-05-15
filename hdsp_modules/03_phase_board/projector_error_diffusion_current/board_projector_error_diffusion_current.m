function ctx = board_projector_error_diffusion_current(ctx)
projected = board_project_phase_only(ctx.phase.phase_map, ctx.params, ctx.phase.source_mask);
projected.name = 'projector_error_diffusion_current';
ctx.board = projected;
end

