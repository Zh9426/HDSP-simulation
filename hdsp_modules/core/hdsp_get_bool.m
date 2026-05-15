function value = hdsp_get_bool(s, field_name, default_value)
if isstruct(s) && isfield(s, field_name)
    value = logical(s.(field_name));
else
    value = default_value;
end
end

