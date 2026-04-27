function tests = test_build_exit_plane_analysis_defaults
tests = functiontests(localfunctions);
end

function testCreatesStablePlaceholderFields(testCase)
Nx = 4;
Ny = 3;
thickness_map = reshape(single(1:12), Nx, Ny) * 1e-3;
circle_mask_board = logical([...
    1 1 0; ...
    1 1 1; ...
    0 1 1; ...
    0 0 1]);
dx = 0.5e-3;
dz = 0.5e-3;
net_num_board = int32(round(thickness_map / dz));

defaults = build_exit_plane_analysis_defaults(Nx, Ny, thickness_map, circle_mask_board, dx, dz, net_num_board);

verifySize(testCase, defaults.p_exit_amp_norm, [Nx, Ny]);
verifySize(testCase, defaults.p_exit_phase, [Nx, Ny]);
verifySize(testCase, defaults.board_exit_asm_norm, [Nx, Ny]);
verifySize(testCase, defaults.aperture_edge_distance_mm, [Nx, Ny]);
verifySize(testCase, defaults.local_thickness_mean, [Nx, Ny]);
verifySize(testCase, defaults.local_thickness_std, [Nx, Ny]);
verifyTrue(testCase, isnan(defaults.exit_amp_cv));
verifyTrue(testCase, isnan(defaults.board_exit_kwave_corr));
verifyEqual(testCase, defaults.exit_amp_vals, zeros(0, 1));
verifyEqual(testCase, defaults.thickness_scatter_mm, zeros(0, 1));
verifyEqual(testCase, defaults.model_pred_scatter, zeros(0, 1));
verifyEqual(testCase, defaults.unique_layers(:), unique(net_num_board(circle_mask_board)));
end
