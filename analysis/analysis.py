#!/usr/bin/env python3
# -*- coding: utf-8 -*-

# Copyright 2018, University of California, Berkeley
# author: Kevin Laeufer <laeufer@cs.berkeley.edu>

import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile

import matplotlib.pyplot as plt
import numpy as np
# import riscv
from format import (CoverageFormat, Input, InputFormat, load_results,
                    make_mutation_graph)

from e2e import CoverageCalcuator


def shell():
    from IPython import embed
    embed()


def color_str_red(s):
    """Color string RED for writing to STDIN."""
    return "\033[1m\033[91m{}\033[00m".format(s)


def color_str_yellow(s):
    """Color string YELLOW for writing to STDIN."""
    return "\033[93m{}\033[00m".format(s)


def run_cmd(cmd, error_str):
    """Run the provided command (list of strings) in a separate process."""
    try:
        rr = subprocess.run(cmd, stdout=subprocess.PIPE, check=True)
    except subprocess.CalledProcessError:
        print(color_str_red(error_str), file=sys.stderr)
        sys.exit(1)
    return rr


def extract_vlt_coverage(test_id, cov_stdout, cov_csv):
    first_line_list = cov_stdout.split("\n")[0].split()
    lines_covered = int(first_line_list[2].split('/')[0].lstrip('('))
    total_lines = int(first_line_list[2].split('/')[1].rstrip(')'))
    cov_percentage = float(first_line_list[3].rstrip('%'))
    print("{},{},{},{:.2f}".format(test_id, lines_covered, total_lines,
                                   cov_percentage),
          file=cov_csv)


def analyse_out(inp_dir):
    name = os.path.basename(inp_dir)

    print("processing {} ...".format(name))
    config, entries, dut, latest = load_results(inp_dir)

    end2end = CoverageCalcuator(dut)
    fuzzer_cov = CoverageFormat(config)
    fmt = InputFormat(config)
    # inputs = [Input(ee, fmt, fuzzer_cov, end2end) for ee in entries]

    # --------------------------------------------------------------------------
    # Verilator HDL line coverage extraction --> for Usenix'21
    # --------------------------------------------------------------------------
    inputs = []
    prior_merged_cov_data = None

    # Open CSV files to save Verilator coverage
    line_cov_csv = open("{}/vlt_cov.csv".format(inp_dir), "w")
    cum_line_cov_csv = open("{}/vlt_cum_cov.csv".format(inp_dir), "w")

    # Write CSV file headers for VLT coverage
    COV_CSV_HEADER = "Test-ID,Lines-Covered,Total-Lines,Line-Coverage-(%)"
    print(COV_CSV_HEADER, file=line_cov_csv)
    print(COV_CSV_HEADER, file=cum_line_cov_csv)

    for ee in entries:
        test_id = ee['entry']['id']
        test_cov_data = "{}/coverage_{}.dat".format(inp_dir, test_id)
        merged_cov_data = "{}/merged_coverage_{}.dat".format(inp_dir, test_id)

        # Extract coverage for current test
        with tempfile.TemporaryDirectory() as tmp_annotations_dir:
            inputs.append(Input(ee, fmt, fuzzer_cov, end2end))
            shutil.move("{}/coverage.dat".format(inp_dir), test_cov_data)
            rr = run_cmd([
                "verilator_coverage", "--annotate", tmp_annotations_dir,
                test_cov_data
            ], "ERROR: generating annotated HDL line coverage.")
            extract_vlt_coverage(test_id, rr.stdout.decode("utf-8"),
                                 line_cov_csv)

        # Combine coverage with previous tests (cumulative coverage)
        with tempfile.TemporaryDirectory() as tmp_annotations_dir:
            if prior_merged_cov_data is None:
                run_cmd([
                    "verilator_coverage", "-write", merged_cov_data,
                    test_cov_data
                ], "ERROR: writing initial merged coverage data.")
            else:
                run_cmd([
                    "verilator_coverage", "-write", merged_cov_data,
                    prior_merged_cov_data, test_cov_data
                ], "ERROR: writing merged coverage data.")
            rr = run_cmd([
                "verilator_coverage", "--annotate", tmp_annotations_dir,
                merged_cov_data
            ], "ERROR: generating (merged) annotated HDL line coverage.")
            extract_vlt_coverage(test_id, rr.stdout.decode("utf-8"),
                                 cum_line_cov_csv)

        # Set prior merged coverage data filename
        prior_merged_cov_data = merged_cov_data

    # Close coverage CSV files
    line_cov_csv.close()
    cum_line_cov_csv.close()
    sys.exit(0)
    # --------------------------------------------------------------------------

    # if "sodor" in os.path.basename(inp_dir):
    # riscv.print_instructions(inputs)

    make_mutation_graph("{}/{}_mutations.png".format(inp_dir, name), inputs)

    disco_times = [
        ii.discovered_after for ii in inputs if not ii.e2e_cov['invalid']
    ]
    cov = [ii.e2e_cov['total'] for ii in inputs if not ii.e2e_cov['invalid']]
    if latest is not None:
        disco_times.append(latest)
        cov.append(cov[-1])

    print("# not covered: {}".format(len(inputs[-1].e2e_cov['not_covered'])))
    print(inputs[-1].e2e_cov['not_covered'])
    print("invalid: {}/{}".format(sum(ii.e2e_cov['invalid'] for ii in inputs),
                                  len(inputs)))
    # print([ii.cycles for ii in inputs])

    return (disco_times, cov, name)


CI_mult = [
    12.7062, 4.3027, 3.1824, 2.7764, 2.5706, 2.4469, 2.3646, 2.3060, 2.2622,
    2.2281, 2.2010, 2.1788, 2.1604, 2.1448, 2.131, 2.120, 2.110, 2.101, 2.093,
    2.086, 2.080, 2.074, 2.069
]
color_cycle = [
    color['color'] for color in list(plt.rcParams['axes.prop_cycle'])
]


def analyse_multi(inp_dirs):
    if len(inp_dirs) < 1:
        print("ERROR: inp_dirs in {}".format(inp_dirs))
        sys.exit(1)

    times = []
    percentages = []
    all_times = []
    for subdir in inp_dirs:
        disco_times, cov, name = analyse_out(subdir)
        times.append(disco_times)
        all_times += disco_times
        percentages.append(cov)

    all_percentages = np.zeros((len(inp_dirs), len(all_times)))
    all_times_sorted = sorted(all_times)
    for ii in range(len(inp_dirs)):
        #print(len(all_times_sorted), len(times[ii]), len(percentages[ii]))
        #print(all_times_sorted, times[ii], percentages[ii])
        all_percentages[ii] = np.interp(all_times_sorted, times[ii],
                                        percentages[ii])

    means = np.mean(all_percentages, axis=0)
    stds = np.std(all_percentages, axis=0)
    stds = stds / np.sqrt(len(all_percentages))
    stds = stds * CI_mult[len(all_percentages) - 2]
    return (all_times_sorted, means, stds, determine_name(inp_dirs))


def determine_name(dirs):
    names = [os.path.basename(s) for s in dirs]
    if len(names) == 1:
        name = names[0]
    else:
        names = ['.'.join(n.split('.')[1:]) for n in names]
        assert all(n == names[0] for n in names)
        name = os.path.basename(os.path.dirname(dirs[0]))
    if name.endswith('.out'):
        return name[:-len('.out')]
    return name


if __name__ == '__main__':
    parser = argparse.ArgumentParser(
        description='analysis script for the fuzzing results')
    parser.add_argument('DIR',
                        help='fuzzer output directory to be analyzed',
                        nargs='+')
    args = parser.parse_args()

    coverage_data = []

    for inp_dir in args.DIR:
        conf_json = os.path.join(inp_dir, "config.json")
        subdirs = glob.glob(os.path.join(inp_dir, '*.out'))
        if os.path.isfile(conf_json):
            assert len(subdirs) == 0
            subdirs = [inp_dir]
        coverage_data.append(analyse_multi(subdirs))

    # print(coverage_data)

    # style
    fontname = None
    fontsize = 20
    legend_fontsize = 15
    old_style = False

    for ii, (disco_times, cov, stds, name) in enumerate(coverage_data):
        if name.endswith('random'):
            name = 'random'
        else:
            name = 'RFUZZ'
        plt.plot(disco_times, cov, label=name)
        # plt.fill_between(disco_times, cov - stds, cov + stds,
        # facecolor=color_cycle[ii], alpha=0.2,
        # linestyle='dashed', edgecolor=color_cycle[ii])
    plt.legend(loc='best', fontsize=legend_fontsize)
    plt.ylabel("T/F Coverage", fontname=fontname, fontsize=fontsize)
    plt.xlabel("Time (s)", fontname=fontname, fontsize=fontsize)
    if not old_style:
        plt.ylim(ymax=1.0, ymin=0.0)
        # hide lines on top and right side
        plt.gca().spines['right'].set_visible(False)
        plt.gca().spines['top'].set_visible(False)
    plt.savefig("{}/cov_vs_time.png".format(inp_dir), format="PNG")
