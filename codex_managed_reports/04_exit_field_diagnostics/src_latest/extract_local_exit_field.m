function local_exit = extract_local_exit_field(field_volume, local_z_indices, aperture_mask)
%EXTRACT_LOCAL_EXIT_FIELD Sample a complex field volume at pixel-specific z indices.
if nargin < 3 || isempty(aperture_mask)
    aperture_mask = true(size(local_z_indices));
end

if ~isequal(size(local_z_indices), size(aperture_mask))
    error('extract_local_exit_field:SizeMismatch', 'local_z_indices and aperture_mask must have the same size.');
end
if size(field_volume, 1) ~= size(local_z_indices, 1) || size(field_volume, 2) ~= size(local_z_indices, 2)
    error('extract_local_exit_field:SizeMismatch', 'field_volume x-y size must match local_z_indices.');
end

nz = size(field_volume, 3);
active_z = local_z_indices(aperture_mask);
if any(active_z(:) < 1) || any(active_z(:) > nz) || any(active_z(:) ~= round(active_z(:)))
    error('extract_local_exit_field:OutOfRange', 'local z indices must be integer indices within field_volume.');
end

local_exit = complex(zeros(size(local_z_indices)));
[row_idx, col_idx] = find(aperture_mask);
linear_idx = sub2ind(size(field_volume), row_idx, col_idx, local_z_indices(aperture_mask));
local_exit(aperture_mask) = field_volume(linear_idx);
end
