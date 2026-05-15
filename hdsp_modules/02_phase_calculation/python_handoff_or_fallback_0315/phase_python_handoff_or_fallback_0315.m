function ctx = phase_python_handoff_or_fallback_0315(ctx)
% This module preserves the Python-handoff boundary but remains robust when
% the external optimizer is not run. It falls back to WIASA output.
handoff = struct();
handoff.expected_input = 'target_for_python.mat';
handoff.expected_output = 'dl_phase_init.mat';
handoff.status = 'fallback_not_run';
ctx = phase_wiasa_weighted_0209(ctx);
ctx.phase.name = 'python_handoff_or_fallback_0315';
ctx.phase.handoff = handoff;
end

