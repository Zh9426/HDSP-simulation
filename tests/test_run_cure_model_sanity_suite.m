function tests = test_run_cure_model_sanity_suite
tests = functiontests(localfunctions);
end

function testSanitySuiteIncludesSystemProfileReport(testCase)
report = run_cure_model_sanity_suite();

verifyTrue(testCase, isfield(report, 'system_report'));
verifyEqual(testCase, numel(report.system_report.records), 3);
verifyEqual(testCase, {report.system_report.records.system}, ...
    {'water_arrhenius', 'pdms_cavitation', 'sonoink_self_enhancing'});
end
