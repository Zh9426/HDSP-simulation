function result = run_kwave_pressure_scan(phase_map, source_mask, target, cfg, label)
%RUN_KWAVE_PRESSURE_SCAN Simulate direct phase propagation and pick the best z plane.
if exist('kWaveGrid', 'file') ~= 2 || exist('kspaceFirstOrder3D', 'file') ~= 2
    error('k-Wave is not on the MATLAB path. Add k-Wave before running pressure validation.');
end

fprintf('\n[%s] k-Wave pressure scan...\n', label);

Nz = choose_kgrid_z_size(cfg);
kgrid = kWaveGrid(cfg.Nx, cfg.dx, cfg.Ny, cfg.dy, Nz, cfg.dz);
medium.sound_speed = cfg.c_water * ones(cfg.Nx, cfg.Ny, Nz, 'single');
medium.density = cfg.density_water * ones(cfg.Nx, cfg.Ny, Nz, 'single');

pml_size = 10;
source_z_idx = pml_size + 5;
scan_distances = cfg.z_target_dist + cfg.focus_scan_offsets_m;
target_plane_indices = source_z_idx + round(scan_distances / cfg.dz);
if any(target_plane_indices <= source_z_idx) || any(target_plane_indices >= Nz - pml_size)
    error('Focus scan planes exceed the k-Wave grid. Increase Nz or reduce scan offsets.');
end

cfl = 0.3;
t_end = 1.35 * Nz * cfg.dz / cfg.c_water;
kgrid.makeTime(cfg.c_water, cfl, t_end);

source.p_mask = zeros(cfg.Nx, cfg.Ny, Nz, 'single');
source.p_mask(:, :, source_z_idx) = single(source_mask);
phase_vec = reshape(phase_map(source_mask), [], 1);
t_vec = reshape(kgrid.t_array, 1, []);
omega = 2 * pi * cfg.f0;
source_signal = cfg.source_pressure_pa * sin(omega .* t_vec - phase_vec);
ramp_points = min(kgrid.Nt, max(1, round(2 / cfg.f0 / kgrid.dt)));
source_signal = source_signal .* [linspace(0, 1, ramp_points), ones(1, kgrid.Nt - ramp_points)];
source.p = single(source_signal);
source.p_mode = 'dirichlet';

sensor.mask = false(cfg.Nx, cfg.Ny, Nz);
for idx = 1:numel(target_plane_indices)
    sensor.mask(:, :, target_plane_indices(idx)) = true;
end
sensor.record = {'p'};
sensor.record_start_index = max(1, kgrid.Nt - round(4 / cfg.f0 / kgrid.dt));

input_args = {'PMLInside', true, 'PMLSize', pml_size, 'PlotPML', false, ...
    'PlotSim', false, 'DataCast', 'gpuArray-single'};
try
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
catch gpu_error
    fprintf('[%s] GPU path failed: %s\n', label, gpu_error.message);
    input_args = {'PMLInside', true, 'PMLSize', pml_size, 'PlotPML', false, 'PlotSim', false};
    sensor_data = kspaceFirstOrder3D(kgrid, medium, source, sensor, input_args{:});
end

p_raw = gather(sensor_data.p);
t_record = kgrid.t_array(sensor.record_start_index:kgrid.Nt);
demod_ref = exp(-1i * 2 * pi * cfg.f0 * reshape(t_record, [], 1));
p_complex_vec = (2 / numel(t_record)) * (p_raw * demod_ref);

amp_volume = zeros(cfg.Nx, cfg.Ny, Nz);
phase_volume = zeros(cfg.Nx, cfg.Ny, Nz);
amp_volume(sensor.mask) = abs(p_complex_vec);
phase_volume(sensor.mask) = angle(p_complex_vec);

plane_metrics = struct([]);
best_idx = 1;
best_peak = -inf;
for idx = 1:numel(target_plane_indices)
    plane = target_plane_indices(idx);
    amp_now = amp_volume(:, :, plane);
    metrics_now = calculate_pressure_metrics(amp_now, target.amp, target.mask, target.x, target.y);
    metrics_now.z_offset_m = cfg.focus_scan_offsets_m(idx);
    metrics_now.z_distance_m = scan_distances(idx);
    plane_metrics(idx) = metrics_now;
    if metrics_now.peak_target_pressure_pa > best_peak
        best_peak = metrics_now.peak_target_pressure_pa;
        best_idx = idx;
    end
end

best_plane = target_plane_indices(best_idx);
result.label = label;
result.amp = amp_volume(:, :, best_plane);
result.amp_norm = result.amp / (max(result.amp(:)) + eps);
result.phase = phase_volume(:, :, best_plane);
result.best_plane_index = best_plane;
result.best_z_offset_m = cfg.focus_scan_offsets_m(best_idx);
result.best_z_distance_m = scan_distances(best_idx);
result.plane_metrics = plane_metrics;
result.metrics = plane_metrics(best_idx);
end

function Nz = choose_kgrid_z_size(cfg)
required_depth = cfg.z_target_dist + max(abs(cfg.focus_scan_offsets_m)) + 5e-3;
Nz_min = ceil(required_depth / cfg.dz) + 24;
preferred = [128, 160, 192, 216, 256, 300, 384, 512];
Nz = preferred(find(preferred >= Nz_min, 1));
if isempty(Nz)
    Nz = 2 ^ nextpow2(Nz_min);
end
end
