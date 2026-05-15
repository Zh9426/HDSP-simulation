function ctx = hdsp_default_context(profile)
ctx = struct();
ctx.profile = profile;
ctx.completed = false;
ctx.params = struct();
ctx.target = struct('amp', [], 'mask', [], 'source_mask', []);
ctx.phase = struct('phase_map', [], 'source_mask', [], 'history', []);
ctx.board = struct('actual_phase', [], 'thickness_map', [], 'layer_map', []);
ctx.field = struct('focus_amp', [], 'exit_amp', [], 'status', "not_run");
ctx.exit_diagnostic = hdsp_disabled_stage('exit_diagnostic');
ctx.cure = hdsp_disabled_stage('cure');
ctx.metrics = struct();
end

