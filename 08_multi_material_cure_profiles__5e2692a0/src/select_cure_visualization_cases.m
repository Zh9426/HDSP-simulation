function indices = select_cure_visualization_cases(records, preferred_names)
arguments
    records struct
    preferred_names string = ["ideal_binary", "blurred_edge", ...
        "speckle_nonuniform", "target_edge_rolloff", ...
        "off_target_hotspot", "target_overdrive"]
end

record_names = string({records.name});
indices = [];
for name = preferred_names
    idx = find(record_names == name, 1);
    if ~isempty(idx)
        indices(end + 1) = idx; %#ok<AGROW>
    end
end

if isempty(indices)
    [~, idx] = min([records.IoU]);
    indices = idx;
end
end
