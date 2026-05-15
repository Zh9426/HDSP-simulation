function [records, simulations] = evaluate_cure_validation_cases(cases, exposure_time, params, target_mask)
arguments
    cases struct
    exposure_time (1, 1) double {mustBeNonnegative}
    params struct
    target_mask
end

target_mask = logical(target_mask);
records = repmat(empty_record(), 1, numel(cases));
simulations = cell(1, numel(cases));

for idx = 1:numel(cases)
    sim = simulate_cure_from_pressure_map( ...
        cases(idx).pressure_map, exposure_time, params, target_mask);
    simulations{idx} = sim;
    records(idx) = record_from_simulation(cases(idx), exposure_time, sim, target_mask);
end
end

function record = empty_record()
record = struct( ...
    'name', '', ...
    'description', '', ...
    'exposure_time', 0, ...
    'IoU', 0, ...
    'Dice', 0, ...
    'coverage', 0, ...
    'over_cure', 0, ...
    'under_cure', 0, ...
    'pressure_target_mean_MPa', 0, ...
    'pressure_background_max_MPa', 0, ...
    'cavitation_dose_roi_mean', 0, ...
    'thermal_dose_roi_mean', 0, ...
    'thermal_dose_background_mean', 0, ...
    'quality_risk_roi_mean', 0, ...
    'quality_risk_background_mean', 0, ...
    'quality_risk_peak', 0);
end

function record = record_from_simulation(case_def, exposure_time, sim, target_mask)
record = empty_record();
record.name = case_def.name;
record.description = case_def.description;
record.exposure_time = exposure_time;
record.IoU = sim.metrics.IoU;
record.Dice = sim.metrics.Dice;
record.coverage = sim.metrics.cured_coverage;
record.over_cure = sim.metrics.over_cure_ratio;
record.under_cure = sim.metrics.under_cure_ratio;
record.pressure_target_mean_MPa = mean(case_def.pressure_map(target_mask)) / 1e6;
record.pressure_background_max_MPa = max(case_def.pressure_map(~target_mask)) / 1e6;
record.cavitation_dose_roi_mean = mean(sim.score_components.cavitation_dose(target_mask));
record.thermal_dose_roi_mean = mean(sim.score_components.thermal_dose(target_mask));
record.thermal_dose_background_mean = mean(sim.score_components.thermal_dose(~target_mask));
record.quality_risk_roi_mean = mean(sim.score_components.quality_risk(target_mask));
record.quality_risk_background_mean = mean(sim.score_components.quality_risk(~target_mask));
record.quality_risk_peak = max(sim.score_components.quality_risk(:));
end
