function out = hdsp_merge_struct(base, overrides)
out = base;
if ~isstruct(overrides)
    return;
end
names = fieldnames(overrides);
for i = 1:numel(names)
    out.(names{i}) = overrides.(names{i});
end
end

