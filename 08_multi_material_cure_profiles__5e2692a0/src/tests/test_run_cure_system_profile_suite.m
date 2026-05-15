function tests = test_run_cure_system_profile_suite
tests = functiontests(localfunctions);
end

function testSuiteComparesAllThreeProfiles(testCase)
report = run_cure_system_profile_suite();

verifyEqual(testCase, numel(report.records), 3);
verifyEqual(testCase, {report.records.system}, ...
    {'water_arrhenius', 'pdms_cavitation', 'sonoink_self_enhancing'});
verifyTrue(testCase, all(isfield(report.records, 'IoU')));
verifyTrue(testCase, isfield(report, 'simulations'));
end
