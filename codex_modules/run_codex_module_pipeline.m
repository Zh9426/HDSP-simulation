function run_codex_module_pipeline(profile_name)
%RUN_CODEX_MODULE_PIPELINE Run a registered HDSP module profile.
%
% Examples:
%   run_codex_module_pipeline list
%   run_codex_module_pipeline KWAVE_full_pipeline_current
%   run_codex_module_pipeline IASA_python_1_focus_check

if nargin < 1 || isempty(profile_name)
    profile_name = 'KWAVE_full_pipeline_current';
end
if isstring(profile_name)
    profile_name = char(profile_name);
end

root_dir = fileparts(mfilename('fullpath'));
registry = codex_module_registry(root_dir);

if strcmpi(profile_name, 'list')
    print_profiles(registry);
    return;
end

if ~isfield(registry.profiles, profile_name)
    error('Unknown profile "%s". Run run_codex_module_pipeline list to inspect available profiles.', profile_name);
end

profile = registry.profiles.(profile_name);
validate_profile(profile);

old_path = path;
old_dir = pwd;
cleanup = onCleanup(@() restore_environment(old_path, old_dir));

for idx = 1:numel(profile.module_paths)
    addpath(genpath(profile.module_paths{idx}));
end

entry_dir = fileparts(profile.entry_file);
switch upper(profile.language)
    case 'MATLAB'
        cd(entry_dir);
        run(profile.entry_file);
    case 'PYTHON'
        command = sprintf('python "%s"', profile.entry_file);
        status = system(command);
        if status ~= 0
            error('Python profile "%s" failed with status %d.', profile.name, status);
        end
    otherwise
        error('Unsupported profile language "%s".', profile.language);
end

end

function print_profiles(registry)
names = fieldnames(registry.profiles);
fprintf('Available codex module profiles:\n');
for idx = 1:numel(names)
    profile = registry.profiles.(names{idx});
    fprintf('  %-36s %s\n', profile.name, profile.description);
end
end

function validate_profile(profile)
if ~exist(profile.entry_file, 'file')
    error('Profile entry file does not exist: %s', profile.entry_file);
end
for idx = 1:numel(profile.module_paths)
    if ~exist(profile.module_paths{idx}, 'dir')
        error('Profile module path does not exist: %s', profile.module_paths{idx});
    end
end
end

function restore_environment(old_path, old_dir)
path(old_path);
if exist(old_dir, 'dir')
    cd(old_dir);
end
end
