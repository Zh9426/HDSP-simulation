function ideal_exit = make_idealized_exit_field(actual_exit_complex, aperture_mask, theory_amplitude)
arguments
    actual_exit_complex
    aperture_mask
    theory_amplitude (1, 1) double = 1.0
end

aperture_mask = logical(aperture_mask);
ideal_exit = zeros(size(actual_exit_complex), 'like', actual_exit_complex);
ideal_exit(aperture_mask) = theory_amplitude .* exp(1i .* angle(actual_exit_complex(aperture_mask)));
end
