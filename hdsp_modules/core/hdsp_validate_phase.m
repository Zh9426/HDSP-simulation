function ctx = hdsp_validate_phase(ctx)
hdsp_assert_map_size(ctx.phase.phase_map, ctx.params, 'phase.phase_map');
if ~isfield(ctx.phase, 'source_mask') || isempty(ctx.phase.source_mask)
    ctx.phase.source_mask = ctx.target.source_mask;
end
hdsp_assert_map_size(ctx.phase.source_mask, ctx.params, 'phase.source_mask');
ctx.phase.phase_map = angle(exp(1i * double(ctx.phase.phase_map)));
ctx.phase.source_mask = logical(ctx.phase.source_mask);
ctx.phase.phase_map(~ctx.phase.source_mask) = 0;
end

