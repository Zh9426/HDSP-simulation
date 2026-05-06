%RUN_A_LETTER_IASA_0211_SMOKE Compose a target module with an initial-phase module.
%
% This is intentionally small and code-only. It is a smoke example for the
% functionized module interface, not a production simulation.

target = build_target_A_letter_edge_blur_0302(96, 40e-3);

phase_result = compute_initial_phase_IASA_0211(target.image, struct( ...
    'Lx', target.Lx, ...
    'epoch', 5, ...
    'pad_factor', 2));

fprintf('Target: %s, IASA phase size: %dx%d\n', ...
    target.name, size(phase_result.phase, 1), size(phase_result.phase, 2));
