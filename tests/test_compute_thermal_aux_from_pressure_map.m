function tests = test_compute_thermal_aux_from_pressure_map
tests = functiontests(localfunctions);
end

function testThermalDoseSpreadsBeyondHotRegion(testCase)
params = baseParams();
p_amp = ones(64, 64) * 1.2e6;
p_amp(25:40, 25:40) = 2.25e6;

thermal_dose = compute_thermal_aux_from_pressure_map(p_amp, 0.20, params, 1.0e-4);

verifyGreaterThan(testCase, thermal_dose(24, 32), 0.0);
verifyGreaterThan(testCase, mean(thermal_dose(25:40, 25:40), 'all'), ...
    mean(thermal_dose(1:10, 1:10), 'all'));
end

function testLongerExposureIncreasesThermalDose(testCase)
params = baseParams();
p_amp = ones(32, 32) * 2.25e6;

short_dose = compute_thermal_aux_from_pressure_map(p_amp, 0.05, params, 1.0e-4);
long_dose = compute_thermal_aux_from_pressure_map(p_amp, 0.20, params, 1.0e-4);

verifyGreaterThan(testCase, mean(long_dose(:)), mean(short_dose(:)));
end

function params = baseParams()
params = struct( ...
    'thermal_pressure_ref', 2.25e6, ...
    'thermal_peak_deltaT', 8.0, ...
    'thermal_delta_ref', 20.0, ...
    'thermal_dose_time', 0.12, ...
    'thermal_diffusivity', 1.0e-7, ...
    'thermal_blur_scale', 1.0);
end
