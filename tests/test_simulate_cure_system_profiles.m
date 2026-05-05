function tests = test_simulate_cure_system_profiles
tests = functiontests(localfunctions);
end

function testPdmsProfileStillUsesCavitationDose(testCase)
target = squareTarget();
params = build_cure_system_profile('pdms_cavitation', 1.0e-4);
p_amp = pressureCase(target, 2.25e6, 1.20e6);

result = simulate_cure_from_pressure_map(p_amp, 0.06, params, target);

verifyGreaterThan(testCase, result.metrics.IoU, 0.95);
verifyEqual(testCase, result.model_name, 'pdms_cavitation');
verifyEqual(testCase, mean(result.score_components.thermal_contribution(target)), 0, 'AbsTol', 1e-12);
end

function testWaterArrheniusIgnoresCavitationAsCureSource(testCase)
target = squareTarget();
params = build_cure_system_profile('water_arrhenius', 1.0e-4);
p_amp = pressureCase(target, 1.60e6, 1.20e6);

result = simulate_cure_from_pressure_map(p_amp, 0.50, params, target);

verifyEqual(testCase, result.model_name, 'water_arrhenius');
verifyEqual(testCase, nnz(result.cavitation.activity), 0);
verifyGreaterThanOrEqual(testCase, mean(result.cure_score(target)), 0);
verifyEqual(testCase, result.score_components.cure_mechanism, 'arrhenius_thermal');
end

function testSonoinkSelfEnhancementRaisesGelDose(testCase)
target = squareTarget();
dx = 1.0e-4;
sonoink = build_cure_system_profile('sonoink_self_enhancing', dx);
p_amp = pressureCase(target, 55e6, 5e6);

short_result = simulate_cure_from_pressure_map(p_amp, 0.50, sonoink, target);
long_result = simulate_cure_from_pressure_map(p_amp, 5.00, sonoink, target);

verifyEqual(testCase, long_result.model_name, 'sonoink_self_enhancing');
verifyGreaterThan(testCase, mean(long_result.cure_score(target)), ...
    mean(short_result.cure_score(target)));
verifyGreaterThan(testCase, max(long_result.temperature_C(:)), ...
    max(short_result.temperature_C(:)));
verifyGreaterThanOrEqual(testCase, max(long_result.temperature_C(:)), ...
    sonoink.cure_temp_C);
end

function testSonoinkDoesNotCureAtPdmsPressureScale(testCase)
target = squareTarget();
sonoink = build_cure_system_profile('sonoink_self_enhancing', 1.0e-4);
p_amp = pressureCase(target, 2.50e6, 1.20e6);

result = simulate_cure_from_pressure_map(p_amp, 0.60, sonoink, target);

verifyLessThan(testCase, max(result.temperature_C(:)), 30.0);
verifyEqual(testCase, nnz(result.cured_mask), 0);
end

function target = squareTarget()
target = false(48, 48);
target(13:36, 13:36) = true;
end

function p_amp = pressureCase(target, target_pressure, background_pressure)
p_amp = ones(size(target)) .* background_pressure;
p_amp(target) = target_pressure;
end
