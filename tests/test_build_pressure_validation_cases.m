function tests = test_build_pressure_validation_cases
tests = functiontests(localfunctions);
end

function testPressureCasesIncludeIdealAndSemiIdeal(testCase)
target = false(32, 32);
target(9:24, 9:24) = true;
params = default_cure_model_params();

cases = build_pressure_validation_cases(target, params, 1.0e-4);
case_names = string({cases.name});

verifyTrue(testCase, any(case_names == "ideal_binary"));
verifyTrue(testCase, any(case_names == "blurred_edge"));
verifyTrue(testCase, any(case_names == "background_leakage"));
verifyTrue(testCase, any(case_names == "speckle_nonuniform"));
verifyTrue(testCase, any(case_names == "target_overdrive"));
verifyGreaterThanOrEqual(testCase, numel(cases), 4);
end

function testPressureCasesIncludeOverdriveRisk(testCase)
target = false(32, 32);
target(9:24, 9:24) = true;
params = default_cure_model_params();

cases = build_pressure_validation_cases(target, params, 1.0e-4);
max_pressure = max(arrayfun(@(case_def) max(case_def.pressure_map(:)), cases));

verifyGreaterThan(testCase, max_pressure, params.pressure_stream);
end

function testIdealCaseKeepsBackgroundBelowCavitationOnset(testCase)
target = false(32, 32);
target(9:24, 9:24) = true;
params = default_cure_model_params();

cases = build_pressure_validation_cases(target, params, 1.0e-4);
ideal_case = cases(strcmp({cases.name}, 'ideal_binary'));

verifyGreaterThan(testCase, mean(ideal_case.pressure_map(target)), params.pressure_full);
verifyLessThan(testCase, max(ideal_case.pressure_map(~target)), params.pressure_on);
end

function testSemiIdealCasesAreDeterministic(testCase)
target = false(32, 32);
target(9:24, 9:24) = true;
params = default_cure_model_params();

first = build_pressure_validation_cases(target, params, 1.0e-4);
second = build_pressure_validation_cases(target, params, 1.0e-4);

verifyEqual(testCase, first(4).pressure_map, second(4).pressure_map);
end
