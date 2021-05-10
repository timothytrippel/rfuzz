#!/bin/bash -eu
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

function check_exit_code() {
  if (($? != 0 && $? != 124)); then
    exit 1
  fi
}

# Set default DUT
DUT="${DUT:-Sodor3Stage}"

# Build fuzz server for target DUT
make bin

# Build fuzzer
cd fuzzer
cargo build --release

# Launch fuzz server in the background
rm -rf /tmp/fpga
mkdir /tmp/fpga
/src/rfuzz/build/${DUT}_server &

# Launch fuzzer
rm -rf out
if [[ -z ${DURATION_MINS-} ]]; then
  cargo run --release -- -c -o out ../build/${DUT}.toml
else
  timeout --foreground --preserve-status ${DURATION_MINS}m \
    cargo run --release -- -c -o out ../build/${DUT}.toml
fi
check_exit_code
