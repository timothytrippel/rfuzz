#!/usr/bin/python3
# BSD 3-Clause License
#
# Copyright (c) 2021, Timothy Trippel <trippel@umich.edu>
# All rights reserved.
#
# Redistribution and use in source and binary forms, with or without
# modification, are permitted provided that the following conditions are met:
#
# 1. Redistributions of source code must retain the above copyright notice,
#    this list of conditions and the following disclaimer.
#
# 2. Redistributions in binary form must reproduce the above copyright notice,
#    this list of conditions and the following disclaimer in the documentation
#    and/or other materials provided with the distribution.
#
# 3. Neither the name of the copyright holder nor the names of its
#    contributors may be used to endorse or promote products derived from
#    this software without specific prior written permisson.
#
# THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS"
# AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
# IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE
# ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE
# LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR
# CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF
# SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS
# INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
# CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
# ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
# POSSIBILITY OF SUCH DAMAGE.
"""Helper module to interact with GCS.

Description:
This module implements a method to pull all data from a GCS bucket.
"""

import glob
import multiprocessing
import os
import subprocess
import sys


def pull_data_from_gcs(search_prefix=None):
    """Pulls down fuzzer data from GCS to local machine."""
    # Create worker pool
    pool = multiprocessing.Pool(None)

    # Check if local DST path exists first, if not, create it
    parent_dst = os.path.join(os.getcwd(), "gcp-data")
    if not os.path.exists(parent_dst):
        os.makedirs(parent_dst)

    # Get list of fuzzing data directories stored in GCS fuzzing-data bucket
    gcs_bucket_path = _get_gcs_bucket_path()
    ls_cmd = ["gsutil", "ls", gcs_bucket_path]
    proc = subprocess.Popen(ls_cmd,
                            stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT,
                            close_fds=True)
    while True:
        line = proc.stdout.readline()
        if not line:
            break
        src = line.decode("utf-8").rstrip("/\n")
        dst = os.path.join(parent_dst, os.path.basename(src))
        # if True:
        if (search_prefix is None
                or search_prefix in src) and not _data_exists_locally(dst):
            print("Pulling down fuzzing data from %s ..." % src)
            if not os.path.exists(dst):
                os.makedirs(dst)
            # Download Verilator coverage
            cmd = [
                "gsutil", "cp",
                "%s/vlt_cum_cov.csv" % src,
                "%s/vlt_cum_cov.csv" % dst
            ]
            _run_gsutil_cmd(cmd)
            # Download other fuzzing data (e.g. timestamps of input creation)
            ls_cmd = ["gsutil", "ls", src]
            subproc = subprocess.Popen(
                ["gsutil", "ls", "%s" % src],
                stdin=subprocess.PIPE,
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                close_fds=True)
            cp_cmds = []
            for filepath in subproc.stdout:
                filename = str(
                    os.path.basename(filepath.decode("utf-8").rstrip()))
                if filename.endswith(".json"):
                    cp_cmds.append([
                        "gsutil", "cp",
                        "%s/%s" % (src, filename),
                        "%s/%s" % (dst, filename)
                    ])
            cp_results = pool.map_async(_run_gsutil_cmd, cp_cmds)
            cp_results.wait()


def _run_gsutil_cmd(gs_util_cmd):
    _run_cmd(gs_util_cmd,
             "ERROR: cannot copy data from GCS.",
             silent=True,
             fail_silent=True)


def _run_cmd(cmd, error_str, silent=False, fail_silent=False):
    """Run the provided command (list of strings) in a separate process."""
    try:
        if not silent:
            print("Running command:")
            print(subprocess.list2cmdline(cmd))
            subprocess.check_call(cmd)
        else:
            subprocess.check_call(cmd, stdout=subprocess.DEVNULL)
    except subprocess.CalledProcessError:
        if not fail_silent:
            print(error_str, file=sys.stderr)
            sys.exit(1)


def _get_gcs_bucket_path():
    return "gs://%s-%s" % ("vivid-kite-287614", "rfuzz-data")


def _data_exists_locally(exp_data_path):
    """Check if local experiment data already exists."""
    if glob.glob(exp_data_path):
        return True
    return False


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] == "":
        pull_data_from_gcs()
    else:
        pull_data_from_gcs(search_prefix=sys.argv[1])
