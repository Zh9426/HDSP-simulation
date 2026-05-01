function tests = test_evaluate_cure_validation_cases
tests = functiontests(localfunctions);
end

function testEvaluationRunsAllPressureCases(testCase)
target = false(32, 32);
target(9:24, 9:24) = true;
dx = 1.0e-4;
params = default_cure_model_params(dx);
cases = build_pressure_validation_cases(target, params, dx);

[records, simulations] = evaluate_cure_validation_cases(cases(1:2), 0.06, params, target);

verifyEqual(testCase, numel(records), 2);
verifyEqual(testCase, numel(simulations), 2);
verifyTrue(testCase, isfield(records, 'IoU'));
verifyGreaterThan(testCase, records(1).coverage, 0);
end

function testEvaluationReportsQualityRiskPeak(testCase)
target = false(32, 32);
target(9:24, 9:24) = true;
dx = 1.0e-4;
params = default_cure_model_params(dx);
case_def = struct( ...
    'name', 'overdrive', ...
    'description', 'overdrive test', ...
    'pressure_map', pressureCase(target, 2.55e6, 1.20e6));

records = evaluate_cure_validation_cases(case_def, 0.06, params, target);

verifyGreaterThan(testCase, records.quality_risk_roi_mean, 0);
verifyGreaterThan(testCase, records.quality_risk_peak, 0);
end

function p_amp = pressureCase(target, target_pressure, background_pressure)
p_amp = ones(size(target)) .* background_pressure;
p_amp(target) = target_pressure;
end
