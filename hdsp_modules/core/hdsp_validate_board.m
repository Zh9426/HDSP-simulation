function ctx = hdsp_validate_board(ctx)
hdsp_assert_map_size(ctx.board.actual_phase, ctx.params, 'board.actual_phase');
hdsp_assert_map_size(ctx.board.thickness_map, ctx.params, 'board.thickness_map');
hdsp_assert_map_size(ctx.board.layer_map, ctx.params, 'board.layer_map');
ctx.board.actual_phase(~ctx.phase.source_mask) = 0;
end

