function tests = test_select_cure_threshold
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
addMainlinePath();
end

function testSelectsThresholdWithBestIoU(testCase)
cure_score = [1.4, 0.9, 0.2; 1.3, 1.1, 0.4];
target_mask = logical([1, 0, 0; 1, 1, 0]);
threshold_candidates = [0.5, 1.0, 1.2];

result = select_cure_threshold(cure_score, target_mask, threshold_candidates);

verifyEqual(testCase, result.threshold, 1.0);
verifyEqual(testCase, result.IoU, 1.0, 'AbsTol', 1e-10);
verifyEqual(testCase, result.cured_mask, target_mask);
end

function testHigherThresholdCanReduceOverCure(testCase)
cure_score = [1.2, 1.1, 0.9; 0.8, 0.7, 0.1];
target_mask = logical([1, 0, 0; 1, 0, 0]);
threshold_candidates = [0.75, 1.0];

result = select_cure_threshold(cure_score, target_mask, threshold_candidates);

verifyEqual(testCase, result.threshold, 0.75);
verifyEqual(testCase, result.cured_coverage, 1.0, 'AbsTol', 1e-12);
verifyEqual(testCase, result.over_cure_ratio, 1.0, 'AbsTol', 1e-12);
end

function testReportsDiceAndCoverage(testCase)
cure_score = [1.1, 0.2; 0.8, 0.1];
target_mask = logical([1, 0; 1, 0]);
threshold_candidates = [0.5, 1.0];

result = select_cure_threshold(cure_score, target_mask, threshold_candidates);

verifyEqual(testCase, result.threshold, 0.5);
verifyEqual(testCase, result.cured_coverage, 1.0, 'AbsTol', 1e-12);
verifyEqual(testCase, result.under_cure_ratio, 0.0, 'AbsTol', 1e-12);
verifyGreaterThan(testCase, result.Dice, 0.0);
end

function testSelectionScoreCanPreferLowerOverCure(testCase)
cure_score = [...
    1.1, 1.1, 1.1, 1.1, 1.1, ...
    1.1, 1.1, 0.8, 0.8, 0.8, ...
    0.8, 0.8];
target_mask = logical([...
    1, 1, 1, 1, 1, ...
    1, 1, 1, 1, 1, ...
    0, 0]);
threshold_candidates = [0.5, 1.0];
params = struct( ...
    'selection_mode', 'score', ...
    'over_cure_target', 0.0, ...
    'under_cure_target', 0.5, ...
    'over_cure_weight', 1.0, ...
    'under_cure_weight', 0.0, ...
    'dice_weight', 0.0);

result = select_cure_threshold(cure_score, target_mask, threshold_candidates, params);

verifyEqual(testCase, result.threshold, 1.0);
verifyLessThan(testCase, result.IoU, 0.8);
verifyEqual(testCase, result.over_cure_ratio, 0.0, 'AbsTol', 1e-12);
end

function testNearBestModeProtectsIoU(testCase)
cure_score = [1.2, 1.1, 1.0, 0.9, 0.8, 0.1];
target_mask = logical([1, 1, 1, 1, 0, 0]);
threshold_candidates = [0.75, 1.05];
params = struct( ...
    'selection_mode', 'near_best_iou', ...
    'iou_drop_tolerance', 0.005, ...
    'over_cure_target', 0.0, ...
    'under_cure_target', 1.0, ...
    'over_cure_weight', 10.0, ...
    'under_cure_weight', 0.0, ...
    'dice_weight', 0.0, ...
    'global_penalty_weight', 0.0);

result = select_cure_threshold(cure_score, target_mask, threshold_candidates, params);

verifyEqual(testCase, result.threshold, 0.75);
verifyEqual(testCase, result.IoU, 0.8, 'AbsTol', 1e-10);
end

function addMainlinePath()
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repo_root, 'codex_managed_reports', '01_mainline_full_pipeline', 'src_stable'));
end
