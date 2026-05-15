classdef test_modular_pipeline_smoke < matlab.unittest.TestCase
    methods (Test)
        function earlyProfileRunsWithCureDisabled(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            addpath(genpath(root));
            ctx = run_hdsp_module_pipeline("kou_early_IASA");
            testCase.verifyTrue(ctx.completed);
            testCase.verifyFalse(ctx.cure.enabled);
            testCase.verifySize(ctx.target.amp, [ctx.params.Nx, ctx.params.Ny]);
            testCase.verifySize(ctx.phase.phase_map, [ctx.params.Nx, ctx.params.Ny]);
            testCase.verifySize(ctx.board.actual_phase, [ctx.params.Nx, ctx.params.Ny]);
            testCase.verifySize(ctx.field.focus_amp, [ctx.params.Nx, ctx.params.Ny]);
            testCase.verifyTrue(isfield(ctx.metrics, 'nmse'));
        end

        function optionalStagesCanBeDisabled(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            addpath(genpath(root));
            ctx = run_hdsp_module_pipeline("current_pdms_cavitation", ...
                struct("enable_exit_diagnostic", false, "enable_cure", false));
            testCase.verifyTrue(ctx.completed);
            testCase.verifyFalse(ctx.exit_diagnostic.enabled);
            testCase.verifyFalse(ctx.cure.enabled);
            testCase.verifyTrue(isnan(ctx.metrics.cure_iou));
        end

        function arrheniusProfileProducesCureMetrics(testCase)
            root = fileparts(fileparts(mfilename('fullpath')));
            addpath(genpath(root));
            ctx = run_hdsp_module_pipeline("a_letter_arrhenius");
            testCase.verifyTrue(ctx.completed);
            testCase.verifyTrue(ctx.cure.enabled);
            testCase.verifyGreaterThanOrEqual(ctx.metrics.cure_iou, 0);
            testCase.verifyLessThanOrEqual(ctx.metrics.cure_iou, 1);
        end
    end
end

