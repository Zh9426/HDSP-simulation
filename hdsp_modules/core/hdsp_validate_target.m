function ctx = hdsp_validate_target(ctx)
target = ctx.target;
hdsp_assert_map_size(target.amp, ctx.params, 'target.amp');
hdsp_assert_map_size(target.mask, ctx.params, 'target.mask');
hdsp_assert_map_size(target.source_mask, ctx.params, 'target.source_mask');
ctx.target.amp = double(target.amp);
ctx.target.mask = logical(target.mask);
ctx.target.source_mask = logical(target.source_mask);
if ~isfield(ctx.target, 'design_amp') || isempty(ctx.target.design_amp)
    ctx.target.design_amp = ctx.target.amp;
end
end

