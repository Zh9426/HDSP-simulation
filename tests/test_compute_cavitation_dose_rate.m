function tests = test_compute_cavitation_dose_rate
tests = functiontests(localfunctions);
end

function testGrowthCarriesNearThresholdDose(testCase)
params = baseParams();
trigger = [0.05, 0.20; 0.60, 1.00];
growth = [0.40, 0.55; 0.80, 1.00];

dose_rate = compute_cavitation_dose_rate(trigger, growth, params);

verifyGreaterThan(testCase, dose_rate(1, 1), trigger(1, 1));
verifyGreaterThan(testCase, dose_rate(1, 2), trigger(1, 2));
verifyEqual(testCase, dose_rate(2, 2), 1.0, 'AbsTol', 1e-12);
end

function testZeroGrowthPreventsDose(testCase)
params = baseParams();
trigger = ones(2, 2);
growth = zeros(2, 2);

dose_rate = compute_cavitation_dose_rate(trigger, growth, params);

verifyEqual(testCase, dose_rate, zeros(2, 2), 'AbsTol', 1e-12);
end

function testDoseRateIsClamped(testCase)
params = baseParams();
trigger = ones(2, 2) * 2;
growth = ones(2, 2) * 1.5;

dose_rate = compute_cavitation_dose_rate(trigger, growth, params);

verifyEqual(testCase, dose_rate, ones(2, 2), 'AbsTol', 1e-12);
end

function testCoherentCloudOutranksIsolatedPeak(testCase)
params = baseParams();
params.dose_cloud_radius_px = 1;
params.dose_cloud_floor = 0.10;
params.dose_cloud_power = 1.0;

trigger_isolated = zeros(5, 5);
growth_isolated = zeros(5, 5);
trigger_isolated(3, 3) = 1.0;
growth_isolated(3, 3) = 1.0;

trigger_cloud = zeros(5, 5);
growth_cloud = zeros(5, 5);
trigger_cloud(2:4, 2:4) = 1.0;
growth_cloud(2:4, 2:4) = 1.0;

isolated_rate = compute_cavitation_dose_rate(trigger_isolated, growth_isolated, params);
cloud_rate = compute_cavitation_dose_rate(trigger_cloud, growth_cloud, params);

verifyGreaterThan(testCase, cloud_rate(3, 3), isolated_rate(3, 3) * 2.0);
verifyLessThan(testCase, isolated_rate(3, 3), 0.30);
end

function testCloudReplenishesWeakInteriorPoint(testCase)
params = baseParams();
params.dose_cloud_radius_px = 1;
params.dose_cloud_floor = 0.35;
params.dose_fill_radius_px = 1;
params.dose_fill_weight = 0.75;
params.dose_fill_growth_ref = 0.20;

trigger = zeros(5, 5);
growth = zeros(5, 5);
trigger(2:4, 2:4) = 0.9;
growth(2:4, 2:4) = 0.9;
trigger(3, 3) = 0.2;
growth(3, 3) = 0.2;

params_without_fill = params;
params_without_fill.dose_fill_weight = 0.0;
rate_without_fill = compute_cavitation_dose_rate(trigger, growth, params_without_fill);
rate_with_fill = compute_cavitation_dose_rate(trigger, growth, params);

verifyGreaterThan(testCase, rate_with_fill(3, 3), rate_without_fill(3, 3) * 2.0);
verifyLessThanOrEqual(testCase, max(rate_with_fill(:)), 1.0);
end

function params = baseParams()
params = struct( ...
    'dose_growth_floor', 0.60, ...
    'dose_trigger_weight', 0.40, ...
    'dose_cloud_radius_px', 0, ...
    'dose_cloud_floor', 1.0, ...
    'dose_cloud_power', 1.0, ...
    'dose_fill_radius_px', 0, ...
    'dose_fill_weight', 0.0, ...
    'dose_fill_growth_ref', 0.20, ...
    'dose_fill_power', 1.0);
end
