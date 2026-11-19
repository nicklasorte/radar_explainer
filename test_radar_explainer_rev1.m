classdef test_radar_explainer_rev1 < matlab.unittest.TestCase
    %TEST_RADAR_EXPLAINER_REV1 Unit tests for radar_explainer_rev1.
    %   Run with: runtests("test_radar_explainer_rev1")

    properties (Access = private)
        baseline    % Results from one full run, shared by the read-only tests.
    end

    methods (TestClassSetup)
        function runOnce(testCase)
            testCase.baseline = radar_explainer_rev1(show_figures=false, save_figures=false, ...
                strict=false);
        end
    end

    methods (Test)
        function allTheoryChecksPass(testCase)
            testCase.verifyTrue(all(testCase.baseline.checks.passed));
        end

        function bothTargetsDetectedNearTruth(testCase)
            p = testCase.baseline.params;
            det = testCase.baseline.detections;
            for k = 1:numel(p.target_range_m)
                near = abs(det.range_m - p.target_range_m(k)) <= p.range_bin_m & ...
                    abs(det.speed_mps - p.target_speed_mps(k)) <= p.speed_bin_mps;
                testCase.verifyTrue(any(near), sprintf("Target %d not detected.", k));
            end
        end

        function noDetectionsAtZeroDoppler(testCase)
            % Stationary clutter must not appear as a detection.
            p = testCase.baseline.params;
            testCase.verifyGreaterThan( ...
                min(abs(testCase.baseline.detections.speed_mps)), 3 * p.speed_bin_mps);
        end

        function matchedFilterGainMatchesTheory(testCase)
            % Independent value: 10*log10(200) = 23.01 dB for a 200-sample pulse.
            gain = testCase.baseline.checks.measured(1);
            testCase.verifyEqual(gain, 10*log10(200), "AbsTol", 0.5);
        end

        function dopplerFftAddsGainOverMatchedFilter(testCase)
            ladder = testCase.baseline.snr_ladder;
            testCase.verifyGreaterThan(ladder.after_doppler_fft_db, ...
                ladder.after_matched_filter_db + 10);
        end

        function outputContract(testCase)
            r = testCase.baseline;
            p = r.params;
            testCase.verifySize(r.range_doppler, [p.num_samples, p.num_pulses]);
            testCase.verifySize(r.range_axis_m, [p.num_samples, 1]);
            testCase.verifySize(r.speed_axis_mps, [p.num_pulses, 1]);
            testCase.verifyClass(r.detections, "table");
        end

        function sameSeedReproduces(testCase)
            again = radar_explainer_rev1(show_figures=false, save_figures=false);
            testCase.verifyEqual(again.range_doppler, testCase.baseline.range_doppler);
        end

        function differentSeedChangesNoise(testCase)
            other = radar_explainer_rev1(show_figures=false, save_figures=false, seed=2);
            testCase.verifyNotEqual(other.range_doppler, testCase.baseline.range_doppler);
        end

        function savesFigures(testCase)
            folder = testCase.applyFixture( ...
                matlab.unittest.fixtures.TemporaryFolderFixture).Folder;
            radar_explainer_rev1(show_figures=false, output_folder=folder, run_checks=false);
            files = dir(fullfile(folder, "*.png"));
            testCase.verifyEqual(numel(files), 7);
        end

        function tooFewAdcBitsErrors(testCase)
            testCase.verifyError(@() radar_explainer_rev1(adc_bits=1, ...
                show_figures=false, save_figures=false), "MATLAB:validators:mustBeInRange");
        end

        function nonIntegerSeedErrors(testCase)
            testCase.verifyError(@() radar_explainer_rev1(seed=1.5, ...
                show_figures=false, save_figures=false), "MATLAB:validators:mustBeInteger");
        end
    end
end
