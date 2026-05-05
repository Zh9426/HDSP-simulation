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
water = build_cure_system_profile('water_arrhenius', dx);
sonoink = build_cure_system_profile('sonoink_self_enhancing', dx);
p_amp = pressureCase(target, 2.10e6, 1.20e6);

water_result = simulate_cure_from_pressure_map(p_amp, 0.60, water, target);
sono_result = simulate_cure_from_pressure_map(p_amp, 0.60, sonoink, target);

verifyEqual(testCase, sono_result.model_name, 'sonoink_self_enhancing');
verifyGreaterThan(testCase, mean(sono_result.cure_score(target)), ...
    mean(water_result.cure_score(target)));
verifyGreaterThan(testCase, max(sono_result.temperature_C(:)), ...
    max(water_result.temperature_C(:)));
end

function target = squareTarget()
target = false(48, 48);
target(13:36, 13:36) = true;
end

function p_amp = pressureCase(target, target_pressure, background_pressure)
p_amp = ones(size(target)) .* background_pressure;
p_amp(target) = target_pressure;
end
