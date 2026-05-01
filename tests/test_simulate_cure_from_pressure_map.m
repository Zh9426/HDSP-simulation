function tests = test_simulate_cure_from_pressure_map
tests = functiontests(localfunctions);
end

function testIdealTargetPressureCuresTargetOnly(testCase)
target = squareTarget();
params = baseParams();
p_amp = pressureCase(target, 2.25e6, 1.20e6);

result = simulate_cure_from_pressure_map(p_amp, 0.06, params, target);

verifyGreaterThan(testCase, result.metrics.IoU, 0.99);
verifyGreaterThan(testCase, result.metrics.cured_coverage, 0.99);
verifyEqual(testCase, result.metrics.over_cure_ratio, 0.0, 'AbsTol', 1e-12);
end

function testBelowOnsetPressureDoesNotCure(testCase)
target = squareTarget();
params = baseParams();
p_amp = pressureCase(target, 1.65e6, 1.20e6);

result = simulate_cure_from_pressure_map(p_amp, 0.60, params, target);

verifyEqual(testCase, nnz(result.cured_mask), 0);
verifyEqual(testCase, result.metrics.cured_coverage, 0.0, 'AbsTol', 1e-12);
verifyEqual(testCase, result.metrics.under_cure_ratio, 1.0, 'AbsTol', 1e-12);
end

function testExposureMonotonicallyIncreasesCure(testCase)
target = squareTarget();
params = baseParams();
p_amp = pressureCase(target, 1.85e6, 1.20e6);
p_amp(target) = linspace(1.85e6, 2.25e6, nnz(target));

short_run = simulate_cure_from_pressure_map(p_amp, 0.02, params, target);
long_run = simulate_cure_from_pressure_map(p_amp, 0.10, params, target);

verifyGreaterThanOrEqual(testCase, long_run.metrics.cured_coverage, ...
    short_run.metrics.cured_coverage);
verifyGreaterThan(testCase, mean(long_run.cure_score(target)), ...
    mean(short_run.cure_score(target)));
end

function testBackgroundOverpressureProducesOvercure(testCase)
target = squareTarget();
params = baseParams();
p_amp = pressureCase(target, 2.25e6, 2.25e6);

result = simulate_cure_from_pressure_map(p_amp, 0.06, params, target);

verifyGreaterThan(testCase, result.metrics.over_cure_ratio, 1.0);
verifyGreaterThan(testCase, nnz(result.cured_mask & ~target), 0);
end

function testThermalAuxIsComputedWhenSpatialDxIsProvided(testCase)
target = squareTarget();
params = baseParams();
params.thermal_weight = 0.15;
params.thermal_pressure_ref = 2.25e6;
params.thermal_peak_deltaT = 8.0;
params.thermal_delta_ref = 20.0;
params.thermal_dose_time = 0.12;
params.thermal_diffusivity = 1.0e-7;
params.thermal_blur_scale = 1.0;
params.spatial_dx = 1.0e-4;
p_amp = pressureCase(target, 2.25e6, 1.20e6);

result = simulate_cure_from_pressure_map(p_amp, 0.06, params, target);

verifyGreaterThan(testCase, mean(result.score_components.thermal_dose(target)), 0);
verifyGreaterThan(testCase, mean(result.score_components.thermal_contribution(target)), 0);
end

function testEnabledThermalModelRequiresThermalInput(testCase)
target = squareTarget();
params = baseParams();
params.thermal_weight = 0.15;
p_amp = pressureCase(target, 2.25e6, 1.20e6);

verifyError(testCase, ...
    @() simulate_cure_from_pressure_map(p_amp, 0.06, params, target), ...
    'simulate_cure_from_pressure_map:MissingThermalInput');
end

function target = squareTarget()
target = false(48, 48);
target(13:36, 13:36) = true;
end

function p_amp = pressureCase(target, target_pressure, background_pressure)
p_amp = ones(size(target)) .* background_pressure;
p_amp(target) = target_pressure;
end

function params = baseParams()
params = struct( ...
    'pressure_on', 1.72e6, ...
    'pressure_full', 1.98e6, ...
    'pressure_stream', 2.35e6, ...
    'pressure_damage', 2.80e6, ...
    'saturation_shape', 4.0, ...
    'trigger_sharpness', 3.0, ...
    'streaming_penalty_strength', 0.75, ...
    'streaming_penalty_power', 1.5, ...
    'smooth_sigma_px', 0.0, ...
    'threshold', 1.0, ...
    'cavitation_dose_time', 0.04, ...
    'thermal_weight', 0.0, ...
    'penalty_weight', 0.80, ...
    'dose_growth_floor', 0.65, ...
    'dose_trigger_weight', 0.35, ...
    'dose_cloud_radius_px', 0, ...
    'dose_cloud_floor', 1.0, ...
    'dose_cloud_weight', 0.0, ...
    'dose_seed_floor', 1.0, ...
    'dose_fill_radius_px', 0, ...
    'dose_fill_weight', 0.0);
end
