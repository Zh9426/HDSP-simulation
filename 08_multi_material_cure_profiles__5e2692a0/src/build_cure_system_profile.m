function params = build_cure_system_profile(system_name, spatial_dx)
arguments
    system_name (1, :) char
    spatial_dx = []
end

switch lower(strtrim(system_name))
    case {'pdms_cavitation', 'pdms'}
        params = default_cure_model_params(spatial_dx);
        params.model_name = 'pdms_cavitation';
        params.material = 'pdms';
        params.acoustic_medium = 'pdms_like';
        params.cure_mechanism = 'cavitation_pdms';

    case {'water_arrhenius', 'water'}
        params = default_cure_model_params(spatial_dx);
        params.model_name = 'water_arrhenius';
        params.material = 'water_like_resin';
        params.acoustic_medium = 'water';
        params.cure_mechanism = 'arrhenius_thermal';
        params.compute_thermal_diagnostic = true;
        params.thermal_pressure_ref = 2.25e6;
        params.thermal_peak_deltaT = 30.0;
        params.thermal_exposure_ref = 0.60;
        params.thermal_diffusivity = 1.4e-7;
        params.thermal_blur_scale = 1.0;
        params.ambient_temp_C = 25.0;
        params.arrhenius_Ea_J_mol = 80e3;
        params.gel_time_ref_s = 2.0;
        params.gel_time_ref_temp_C = 80.0;
        params.self_enhancing_absorption = false;

    case {'sonoink_self_enhancing', 'sonoink'}
        params = default_cure_model_params(spatial_dx);
        params.model_name = 'sonoink_self_enhancing';
        params.material = 'pegda_pnipam_aps_sonoink';
        params.acoustic_medium = 'sonoink';
        params.cure_mechanism = 'self_enhancing_sonothermal';
        params.compute_thermal_diagnostic = true;
        params.thermal_pressure_ref = 2.25e6;
        params.thermal_peak_deltaT = 35.0;
        params.thermal_exposure_ref = 0.60;
        params.thermal_diffusivity = 1.0e-7;
        params.thermal_blur_scale = 1.0;
        params.ambient_temp_C = 25.0;
        params.transition_temp_C = 35.0;
        params.transition_width_C = 2.0;
        params.cure_temp_C = 67.0;
        params.absorption_gain_low = 1.0;
        params.absorption_gain_high = 2.5;
        params.absorption_iterations = 4;
        params.arrhenius_Ea_J_mol = 171e3;
        params.gel_time_ref_s = 1.9;
        params.gel_time_ref_temp_C = 80.0;
        params.self_enhancing_absorption = true;

    otherwise
        error('build_cure_system_profile:UnknownSystem', ...
            'Unknown cure system profile: %s', system_name);
end

if ~isempty(spatial_dx)
    params.spatial_dx = spatial_dx;
end
end
