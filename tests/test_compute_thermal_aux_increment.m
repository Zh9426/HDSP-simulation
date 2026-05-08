function tests = test_compute_thermal_aux_increment
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
addMainlinePath();
end

function testExposureUsesFullThermalWeight(testCase)
params = baseParams();
bulk_temp_rise = [0, 10; 20, 30];
dt = 0.01;

increment = compute_thermal_aux_increment(bulk_temp_rise, dt, true, params);

verifyEqual(testCase, increment, [0, 0.025; 0.05, 0.075], 'AbsTol', 1e-12);
end

function testCoolingUsesReducedThermalWeight(testCase)
params = baseParams();
bulk_temp_rise = [0, 10; 20, 30];
dt = 0.01;

increment = compute_thermal_aux_increment(bulk_temp_rise, dt, false, params);

verifyEqual(testCase, increment, [0, 0.00375; 0.0075, 0.01125], 'AbsTol', 1e-12);
end

function testNegativeTemperatureRiseDoesNotAccumulate(testCase)
params = baseParams();
bulk_temp_rise = [-10, 0; 5, 10];
dt = 0.01;

increment = compute_thermal_aux_increment(bulk_temp_rise, dt, true, params);

verifyEqual(testCase, increment, [0, 0; 0.0125, 0.025], 'AbsTol', 1e-12);
end

function testCavitationGateLimitsThermalAuxiliaryDose(testCase)
params = baseParams();
params.thermal_cavitation_gate_floor = 0.0;
params.thermal_cavitation_gate_power = 1.0;
bulk_temp_rise = ones(2, 2) * 20;
gate = [0, 0.25; 0.5, 1.0];
dt = 0.01;

increment = compute_thermal_aux_increment(bulk_temp_rise, dt, true, params, gate);

verifyEqual(testCase, increment, [0, 0.0125; 0.025, 0.05], 'AbsTol', 1e-12);
end

function params = baseParams()
params = struct( ...
    'thermal_delta_ref', 20.0, ...
    'thermal_dose_time', 0.20, ...
    'cooling_thermal_weight', 0.15, ...
    'thermal_cavitation_gate_floor', 1.0, ...
    'thermal_cavitation_gate_power', 1.0);
end

function addMainlinePath()
repo_root = fileparts(fileparts(mfilename('fullpath')));
addpath(fullfile(repo_root, 'codex_managed_reports', '01_mainline_full_pipeline', 'src_stable'));
end
