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
