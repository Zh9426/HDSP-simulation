function ctx = hdsp_validate_field(ctx)
hdsp_assert_map_size(ctx.field.focus_amp, ctx.params, 'field.focus_amp');
if ~isfield(ctx.field, 'exit_amp') || isempty(ctx.field.exit_amp)
    ctx.field.exit_amp = double(ctx.phase.source_mask);
end
hdsp_assert_map_size(ctx.field.exit_amp, ctx.params, 'field.exit_amp');
if ~isfield(ctx.field, 'status')
    ctx.field.status = "ok";
end
end

