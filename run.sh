#!/bin/bash
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

function launch_fuzzer() {
  # Launch fuzz server in the background
  rm -rf /tmp/fpga
  mkdir /tmp/fpga
  /src/rfuzz/build/${DUT}_server &

  # Launch fuzzer
  sleep 1
  rm -rf out
  if [[ -z ${DURATION_MINS-} ]]; then
    cargo run --release -- -c -o out ../build/${DUT}.toml
  else
    timeout --foreground --preserve-status ${DURATION_MINS}m \
      cargo run --release -- -c -o out ../build/${DUT}.toml
  fi
}

################################################################################
# Set default DUT
################################################################################
DUT="${DUT:-Sodor3Stage}"

################################################################################
# Cleanup prior builds
################################################################################
make clean

################################################################################
# Build fuzz server for target DUT
################################################################################
make FIR=${DUT}.fir DUT=$DUT bin

################################################################################
# Build fuzzer
################################################################################
cd fuzzer
cargo build --release

################################################################################
# Launch fuzz server & fuzzer
################################################################################
# TODO(ttrippel): should not have to run this twice to succeed.
launch_fuzzer || launch_fuzzer
check_exit_code

################################################################################
# Compute coverage results
################################################################################
cd $RFUZZ
./analysis/analysis.py fuzzer/out

################################################################################
# Save data to GCS/Shutdown VM
################################################################################
if [ $RUN_ON_GCP -eq 1 ]; then

  ##############################################################################
  # Get GCP configuration info
  ##############################################################################
  # Metadata Server URLS
  METADATA_URL="http://metadata.google.internal/computeMetadata/v1"
  PROJECT_ID_URL="$METADATA_URL/project/project-id"
  ZONE_URL="$METADATA_URL/instance/zone"
  INSTANCE_NAME_URL="$METADATA_URL/instance/name"
  AUTH_TOKEN_URL="$METADATA_URL/instance/service-accounts/default/token"

  # Get GCE VM instance info
  PROJECT_ID=$(curl -H "Metadata-Flavor: Google" $PROJECT_ID_URL)
  ZONE=$(curl -H "Metadata-Flavor: Google" $ZONE_URL)
  IFS_BACKUP=$IFS
  IFS=$'/'
  ZONE_SPLIT=($ZONE)
  ZONE="${ZONE_SPLIT[3]}"
  IFS=$IFS_BACKUP
  INSTANCE_NAME=$(curl -H "Metadata-Flavor: Google" $INSTANCE_NAME_URL)

  # Get GCE metadata authorization token
  TOKEN=$(curl -H "Metadata-Flavor: Google" $AUTH_TOKEN_URL | python3 -c \
    "import sys, json; print(json.load(sys.stdin)['access_token'])")

  ##############################################################################
  # Save results to GCS
  ##############################################################################
  GCS_API_URL="https://storage.googleapis.com/upload/storage/v1/b"
  find fuzzer/out -type f -exec curl -X POST --data-binary @{} \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: text" \
    "$GCS_API_URL/$GCS_DATA_BUCKET/o?uploadType=media&name=$INSTANCE_NAME/{}" \; \
    >/dev/null

  ##############################################################################
  # Delete GCE VM instance
  ##############################################################################
  GCE_API_URL="https://www.googleapis.com/compute/v1/projects"
  GCE_INSTANCE_URL="$GCE_API_URL/$PROJECT_ID/zones/$ZONE/instances/$INSTANCE_NAME"
  curl -XDELETE -H "Authorization: Bearer $TOKEN" $GCE_INSTANCE_URL
fi
exit 0
