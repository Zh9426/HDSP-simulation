function phase_wrapped = wrap_phase(phase_in)
%WRAP_PHASE Return phase in the [0, 2*pi) interval.
phase_wrapped = mod(phase_in, 2 * pi);
end
