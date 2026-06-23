function tests = test_make_idealized_exit_field
tests = functiontests(localfunctions);
end

function testUsesUniformApertureAmplitudeAndActualPhase(testCase)
actual_phase = [0, pi / 2; pi, -pi / 2];
actual_exit = [2, 3; 4, 5] .* exp(1i * actual_phase);
aperture_mask = [true, true; true, false];

ideal_exit = make_idealized_exit_field(actual_exit, aperture_mask, 7);

verifyEqual(testCase, abs(ideal_exit(aperture_mask)), 7 * ones(3, 1), 'AbsTol', 1e-12);
verifyEqual(testCase, ideal_exit(~aperture_mask), 0, 'AbsTol', 1e-12);
verifyEqual(testCase, angle(ideal_exit(aperture_mask)), actual_phase(aperture_mask), 'AbsTol', 1e-12);
end

function testDefaultsToUnitApertureAmplitude(testCase)
actual_exit = [1 + 1i, -2i; -3, 0.5];
aperture_mask = [true, false; true, true];

ideal_exit = make_idealized_exit_field(actual_exit, aperture_mask);

verifyEqual(testCase, abs(ideal_exit(aperture_mask)), ones(3, 1), 'AbsTol', 1e-12);
verifyEqual(testCase, ideal_exit(~aperture_mask), 0, 'AbsTol', 1e-12);
end
