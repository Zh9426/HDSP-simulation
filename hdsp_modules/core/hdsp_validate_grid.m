function ctx = hdsp_validate_grid(ctx)
p = ctx.params;
required = {'Nx', 'Ny', 'Lx', 'Ly', 'dx', 'f0', 'c_water', 'lambda_water', 'z_target_dist'};
for i = 1:numel(required)
    if ~isfield(p, required{i}) || isempty(p.(required{i}))
        error('Parameter module did not define ctx.params.%s', required{i});
    end
end
if p.Nx ~= p.Ny
    error('This first modular kernel requires square grids: Nx=%d, Ny=%d', p.Nx, p.Ny);
end
end

