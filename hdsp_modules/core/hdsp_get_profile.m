function profile = hdsp_get_profile(registry, profile_key)
key = char(profile_key);
if ~isfield(registry.profiles, key)
    names = string(fieldnames(registry.profiles));
    error('Unknown HDSP profile "%s". Available profiles: %s', key, strjoin(names, ', '));
end
profile = registry.profiles.(key);
profile.key = key;
end

