function params = default_cure_model_params(spatial_dx)
if nargin < 1
    spatial_dx = [];
end

params = struct();
params.pressure_on = 1.72e6;
params.pressure_full = 1.98e6;
params.pressure_stream = 2.35e6;
params.pressure_damage = 2.80e6;
params.saturation_shape = 4.0;
params.trigger_sharpness = 3.0;
params.streaming_penalty_strength = 0.75;
params.streaming_penalty_power = 1.5;
params.smooth_sigma_px = 0.0;

params.threshold = 1.0;
params.cavitation_dose_time = 0.04;
params.thermal_weight = 0.15;
params.penalty_weight = 0.80;

params.thermal_pressure_ref = 2.25e6;
params.thermal_peak_deltaT = 8.0;
params.thermal_delta_ref = 20.0;
params.thermal_dose_time = 0.12;
params.thermal_diffusivity = 1.0e-7;
params.thermal_blur_scale = 1.0;

params.dose_growth_floor = 0.65;
params.dose_trigger_weight = 0.35;
params.dose_cloud_radius_px = 0;
params.dose_cloud_floor = 1.0;
params.dose_cloud_weight = 0.0;
params.dose_seed_floor = 1.0;
params.dose_fill_radius_px = 0;
params.dose_fill_weight = 0.0;

if ~isempty(spatial_dx)
    params.spatial_dx = spatial_dx;
end
end
