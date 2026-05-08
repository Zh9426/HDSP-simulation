function tests = test_evaluate_cure_prediction
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
addMainlinePath();
end

function testUsesFixedPhysicalThreshold(testCase)
cure_score = [0.9, 1.1; 1.2, 0.4];
target_mask = logical([1, 1; 0, 0]);

result = evaluate_cure_prediction(cure_score, target_mask, 1.0);

verifyEqual(testCase, result.threshold, 1.0);
verifyEqual(testCase, result.cured_mask, logical([0, 1; 1, 0]));
verifyEqual(testCase, result.cured_coverage, 0.5, 'AbsTol', 1e-12);
verifyEqual(testCase, result.over_cure_ratio, 0.5, 'AbsTol', 1e-12);
verifyEqual(testCase, result.under_cure_ratio, 0.5, 'AbsTol', 1e-12);
end

function testTargetOnlyAffectsMetricsNotCureMask(testCase)
cure_score = [0.9, 1.1; 1.2, 0.4];
target_a = logical([1, 1; 0, 0]);
target_b = logical([0, 1; 1, 0]);

result_a = evaluate_cure_prediction(cure_score, target_a, 1.0);
result_b = evaluate_cure_prediction(cure_score, target_b, 1.0);

verifyEqual(testCase, result_a.cured_mask, result_b.cured_mask);
verifyNotEqual(testCase, result_a.IoU, result_b.IoU);
end

function addMainlinePath()
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repo_root, 'codex_managed_reports', '01_mainline_full_pipeline', 'src_stable'));
end
