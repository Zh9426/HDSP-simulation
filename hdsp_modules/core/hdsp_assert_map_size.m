function hdsp_assert_map_size(value, params, label)
if isempty(value)
    error('Required map %s is empty', label);
end
if ~isequal(size(value), [params.Nx, params.Ny])
    error('Map %s has size %s, expected [%d %d]', label, mat2str(size(value)), params.Nx, params.Ny);
end
end

