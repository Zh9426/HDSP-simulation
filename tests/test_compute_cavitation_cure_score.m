function tests = test_compute_cavitation_cure_score
tests = functiontests(localfunctions);
end

function testCavitationDoseDominatesCureDecision(testCase)
params = baseParams();
cavitation_dose = [1.2, 0.7; 1.1, 0.2];
thermal_dose = zeros(2, 2);
penalty = zeros(2, 2);

[cure_score, cured_mask, components] = compute_cavitation_cure_score( ...
    cavitation_dose, thermal_dose, penalty, params);

verifyEqual(testCase, cured_mask, logical([1, 0; 1, 0]));
verifyEqual(testCase, cure_score, cavitation_dose, 'AbsTol', 1e-12);
verifyEqual(testCase, components.cavitation_dose, cavitation_dose, 'AbsTol', 1e-12);
end

function testThermalDoseIsOnlyAuxiliary(testCase)
params = baseParams();
cavitation_dose = zeros(2, 2);
thermal_dose = ones(2, 2) * 3.0;
penalty = zeros(2, 2);

[cure_score, cured_mask, components] = compute_cavitation_cure_score( ...
    cavitation_dose, thermal_dose, penalty, params);

verifyFalse(testCase, any(cured_mask(:)));
verifyEqual(testCase, cure_score, ones(2, 2) * 0.6, 'AbsTol', 1e-12);
verifyEqual(testCase, components.thermal_contribution, ones(2, 2) * 0.6, 'AbsTol', 1e-12);
end

function testPenaltySuppressesOverdrivenRegions(testCase)
params = baseParams();
cavitation_dose = ones(2, 2) * 1.2;
thermal_dose = zeros(2, 2);
penalty = [0.0, 0.5; 1.0, 0.2];

[cure_score, cured_mask, components] = compute_cavitation_cure_score( ...
    cavitation_dose, thermal_dose, penalty, params);

verifyGreaterThan(testCase, cure_score(1, 1), cure_score(1, 2));
verifyGreaterThan(testCase, cure_score(1, 2), cure_score(2, 1));
verifyTrue(testCase, cured_mask(1, 1));
verifyFalse(testCase, cured_mask(2, 1));
verifyEqual(testCase, components.penalty_contribution, params.penalty_weight .* penalty, 'AbsTol', 1e-12);
end

function params = baseParams()
params = struct( ...
    'thermal_weight', 0.2, ...
    'penalty_weight', 0.7, ...
    'threshold', 1.0);
end
