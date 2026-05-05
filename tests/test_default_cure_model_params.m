function tests = test_default_cure_model_params
tests = functiontests(localfunctions);
end

function testDefaultCureModelKeepsFullPhysicsEnabled(testCase)
params = default_cure_model_params();

verifyEqual(testCase, params.thermal_weight, 0.0, 'AbsTol', 1e-12);
verifyTrue(testCase, params.compute_thermal_diagnostic);
verifyEqual(testCase, params.penalty_weight, 0.0, 'AbsTol', 1e-12);
verifyGreaterThan(testCase, params.quality_risk_weight, 0);
verifyEqual(testCase, params.threshold, 1.0, 'AbsTol', 1e-12);
verifyGreaterThan(testCase, params.pressure_full, params.pressure_on);
verifyGreaterThan(testCase, params.pressure_stream, params.pressure_full);
end
