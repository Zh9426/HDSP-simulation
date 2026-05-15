function ctx = run_hdsp_module_pipeline(profile_key, overrides)
%RUN_HDSP_MODULE_PIPELINE Single public entrypoint for the modular HDSP kernel.

if nargin < 1 || strlength(string(profile_key)) == 0
    profile_key = "current_pdms_cavitation";
end
if nargin < 2
    overrides = struct();
end

module_root = fileparts(mfilename('fullpath'));
addpath(genpath(module_root));

registry = hdsp_module_registry();
profile = hdsp_get_profile(registry, string(profile_key));
profile = hdsp_merge_struct(profile, overrides);

ctx = hdsp_default_context(profile);
ctx = profile.parameters(ctx);
ctx = hdsp_validate_grid(ctx);
ctx = profile.target(ctx);
ctx = hdsp_validate_target(ctx);
ctx = profile.phase(ctx);
ctx = hdsp_validate_phase(ctx);
ctx = profile.phase_board(ctx);
ctx = hdsp_validate_board(ctx);
ctx = profile.simulation(ctx);
ctx = hdsp_validate_field(ctx);

if hdsp_get_bool(profile, 'enable_exit_diagnostic', false)
    ctx = profile.exit_diagnostic(ctx);
else
    ctx.exit_diagnostic = hdsp_disabled_stage('exit_diagnostic');
end

if hdsp_get_bool(profile, 'enable_cure', true)
    ctx = profile.cure(ctx);
else
    ctx.cure = hdsp_disabled_stage('cure');
end

ctx = profile.metrics(ctx);
ctx.completed = true;
end

