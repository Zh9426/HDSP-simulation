function tests = test_build_cure_system_profile
tests = functiontests(localfunctions);
end

function testReturnsThreeNamedSystems(testCase)
dx = 1.0e-4;
water = build_cure_system_profile('water_arrhenius', dx);
pdms = build_cure_system_profile('pdms_cavitation', dx);
sonoink = build_cure_system_profile('sonoink_self_enhancing', dx);

verifyEqual(testCase, water.material, 'water_like_resin');
verifyEqual(testCase, water.cure_mechanism, 'arrhenius_thermal');
verifyEqual(testCase, pdms.material, 'pdms');
verifyEqual(testCase, pdms.cure_mechanism, 'cavitation_pdms');
verifyEqual(testCase, sonoink.material, 'pegda_pnipam_aps_sonoink');
verifyEqual(testCase, sonoink.cure_mechanism, 'self_enhancing_sonothermal');
verifyEqual(testCase, sonoink.spatial_dx, dx);
end

function testSonoinkProfileContainsPaperAnchors(testCase)
params = build_cure_system_profile('sonoink_self_enhancing', 1.0e-4);

verifyEqual(testCase, params.transition_temp_C, 35.0, 'AbsTol', 1e-12);
verifyEqual(testCase, params.cure_temp_C, 67.0, 'AbsTol', 1e-12);
verifyEqual(testCase, params.arrhenius_Ea_J_mol, 171e3, 'AbsTol', 1e-9);
verifyEqual(testCase, params.gel_time_ref_s, 1.9, 'AbsTol', 1e-12);
verifyEqual(testCase, params.gel_time_ref_temp_C, 80.0, 'AbsTol', 1e-12);
verifyGreaterThan(testCase, params.absorption_gain_high, params.absorption_gain_low);
end

function testUnknownSystemFailsClearly(testCase)
verifyError(testCase, @() build_cure_system_profile('unknown_system'), ...
    'build_cure_system_profile:UnknownSystem');
end
