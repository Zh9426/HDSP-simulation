function tests = test_compare_phase_to_reference
tests = functiontests(localfunctions);
end

function testFindsGlobalOffsetCorrectedAgreement(testCase)
ref_phase = [0, pi/2; pi, -pi/2];
mask = true(2, 2);
global_offset = 0.73;
measured = exp(1i .* (ref_phase + global_offset));

result = compare_phase_to_reference(measured, ref_phase, mask, 0);

verifyGreaterThan(testCase, result.same_sign.coherence, 0.999);
verifyLessThan(testCase, result.same_sign.rms_rad, 1e-10);
verifyEqual(testCase, result.best_sign, "same");
end

function testDetectsOppositeSignConvention(testCase)
ref_phase = [0, pi/3; -pi/2, pi];
mask = true(2, 2);
global_offset = -0.41;
measured = exp(1i .* (-ref_phase + global_offset));

result = compare_phase_to_reference(measured, ref_phase, mask, 0);

verifyGreaterThan(testCase, result.opposite_sign.coherence, 0.999);
verifyLessThan(testCase, result.opposite_sign.rms_rad, 1e-10);
verifyEqual(testCase, result.best_sign, "opposite");
end

function testIgnoresLowAmplitudePixels(testCase)
ref_phase = [0, pi/2; pi, -pi/2];
mask = true(2, 2);
measured = exp(1i .* ref_phase);
measured(2, 2) = 1e-6 .* exp(1i * 2.2);

result = compare_phase_to_reference(measured, ref_phase, mask, 0.5);

verifyEqual(testCase, result.valid_pixels, 3);
verifyEqual(testCase, result.total_mask_pixels, 4);
verifyGreaterThan(testCase, result.same_sign.coherence, 0.999);
end
