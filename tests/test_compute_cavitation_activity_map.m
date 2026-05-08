function tests = test_compute_cavitation_activity_map
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
addMainlinePath();
end

function testBelowThresholdHasNoActivity(testCase)
params = baseParams();
p_amp = [1.2, 1.6; 1.75, 1.79] * 1e6;

cav = compute_cavitation_activity_map(p_amp, params);

verifyEqual(testCase, cav.activation, zeros(size(p_amp)), 'AbsTol', 1e-12);
verifyEqual(testCase, cav.activity, zeros(size(p_amp)), 'AbsTol', 1e-12);
end

function testFullActivationReachesUnityWithoutPenalty(testCase)
params = baseParams();
p_amp = [2.2, 2.4; 2.6, 2.2] * 1e6;

cav = compute_cavitation_activity_map(p_amp, params);

verifyGreaterThan(testCase, min(cav.activity(:)), 0.999);
verifyLessThanOrEqual(testCase, max(cav.activity(:)), 1.0);
verifyEqual(testCase, cav.penalty, zeros(size(p_amp)), 'AbsTol', 1e-12);
end

function testStreamingPenaltySuppressesOverdrivenRegions(testCase)
params = baseParams();
p_amp = [2.2, 2.8; 3.0, 3.2] * 1e6;

cav = compute_cavitation_activity_map(p_amp, params);

verifyGreaterThan(testCase, cav.activity(1, 1), cav.activity(2, 1));
verifyGreaterThan(testCase, cav.activity(2, 1), cav.activity(2, 2));
verifyGreaterThan(testCase, cav.penalty(2, 2), cav.penalty(1, 2));
end

function testTriggerIsSharperThanGrowthNearThreshold(testCase)
params = baseParams();
p_amp = [1.85, 2.00; 2.10, 2.20] * 1e6;

cav = compute_cavitation_activity_map(p_amp, params);

verifyLessThan(testCase, cav.trigger(1, 1), cav.growth(1, 1));
verifyLessThan(testCase, cav.trigger(1, 2), cav.growth(1, 2));
verifyEqual(testCase, cav.trigger(2, 2), 1.0, 'AbsTol', 1e-12);
end

function testMaskZerosOutsideSupport(testCase)
params = baseParams();
params.mask = logical([1, 0; 1, 0]);
p_amp = [2.3, 2.3; 2.3, 2.3] * 1e6;

cav = compute_cavitation_activity_map(p_amp, params);

verifyGreaterThan(testCase, cav.activity(1, 1), 0.9);
verifyEqual(testCase, cav.activity(:, 2), [0; 0], 'AbsTol', 1e-12);
verifyEqual(testCase, cav.activation(:, 2), [0; 0], 'AbsTol', 1e-12);
end

function params = baseParams()
params = struct( ...
    'pressure_on', 1.8e6, ...
    'pressure_full', 2.2e6, ...
    'pressure_stream', 2.7e6, ...
    'pressure_damage', 3.2e6, ...
    'saturation_shape', 4.0, ...
    'trigger_sharpness', 3.0, ...
    'streaming_penalty_strength', 0.75, ...
    'streaming_penalty_power', 1.5, ...
    'smooth_sigma_px', 0.0);
end

function addMainlinePath()
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repo_root, 'codex_managed_reports', '01_mainline_full_pipeline', 'src_stable'));
end
