function tests = test_sonoink_fullflow_validation_entrypoint
tests = functiontests(localfunctions);
end

function testDryRunBuildsSonoinkProfile(testCase)
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repo_root, 'sonoink_test'));

transport_dir = fullfile(repo_root, 'sonoink_test', 'test_transport');
cleanup = onCleanup(@() cleanup_dir(transport_dir)); %#ok<NASGU>

result = HDSP_sonoink_fullflow_validation( ...
    'dry_run', true, ...
    'transport_dir', transport_dir);

verifyEqual(testCase, result.status, 'dry_run_complete');
verifyEqual(testCase, result.cure_params.model_name, 'sonoink_self_enhancing');
verifyEqual(testCase, result.cure_params.cure_mechanism, 'self_enhancing_sonothermal');
verifyTrue(testCase, exist(result.export_path, 'file') == 2);
end

function cleanup_dir(path_to_remove)
if exist(path_to_remove, 'dir')
    rmdir(path_to_remove, 's');
end
end

