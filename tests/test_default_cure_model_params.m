function tests = test_default_cure_model_params
tests = functiontests(localfunctions);
end

function testDefaultCureModelKeepsFullPhysicsEnabled(testCase)
params = default_cure_model_params();

verifyGreaterThan(testCase, params.thermal_weight, 0);
verifyGreaterThan(testCase, params.penalty_weight, 0);
verifyEqual(testCase, params.threshold, 1.0, 'AbsTol', 1e-12);
verifyGreaterThan(testCase, params.pressure_full, params.pressure_on);
verifyGreaterThan(testCase, params.pressure_stream, params.pressure_full);
end
