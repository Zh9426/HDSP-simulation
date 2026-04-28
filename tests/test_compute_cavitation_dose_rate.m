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

function params = baseParams()
params = struct( ...
    'dose_growth_floor', 0.60, ...
    'dose_trigger_weight', 0.40);
end
