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

################################################################################
# GCP configurations to load:
################################################################################
GCP_PROJECT_ID="vivid-kite-287614"
GCP_CONTAINER_RESTART_POLICY="never"
GCS_DATA_BUCKET="${GCP_PROJECT_ID}-rfuzz-data"
GCP_ZONE="us-central1-a"
GCP_MACHINE_TYPE="n1-standard-2"
GCP_BOOT_DISK_SIZE="50GB"
GCP_SCOPES="default,compute-rw,storage-rw"

################################################################################
# Set parameters
################################################################################
NUM_INSTANCES=1
DURATION_MINS=1
DUTS="FFTSmall"
DOCKER_IMAGE="gcr.io/$GCP_PROJECT_ID/rfuzz/env"

################################################################################
# Define Colors
################################################################################
GREEN='\033[0;32m'
NC='\033[0m'
LINE_SEP='---------------------------------------------------------------------'

################################################################################
# Build Docker images
################################################################################
echo -e "${GREEN}${LINE_SEP}${NC}"
echo -e "${GREEN}Building Docker image and pushing to registry ...${NC}"
docker build -t $DOCKER_IMAGE .
docker push ${DOCKER_IMAGE}:latest
echo -e "${GREEN}Done.${NC}"

################################################################################
# Launch VM on GCE
################################################################################
for DUT in $DUTS; do
  echo -e "${GREEN}${LINE_SEP}${NC}"
  echo -e "${GREEN}Launching VMs to fuzz $DUT ...${NC}"
  for INSTANCE_NUM in $(seq 0 $(expr $NUM_INSTANCES - 1)); do
    echo -e "${GREEN}${LINE_SEP}${NC}"
    echo -e "${GREEN}Launching VM instance #${INSTANCE_NUM} ...${NC}"
    # Delete existing data in GCS
    # Launch VM
    gcloud compute instances create-with-container \
      "rfuzz-$(echo "$DUT" | awk '{print tolower($0)}')-${INSTANCE_NUM}" \
      --project=${GCP_PROJECT_ID} \
      --container-image "${DOCKER_IMAGE}:latest" \
      --container-stdin \
      --container-tty \
      --container-privileged \
      --container-restart-policy $GCP_CONTAINER_RESTART_POLICY \
      --zone=$GCP_ZONE \
      --machine-type=$GCP_MACHINE_TYPE \
      --boot-disk-size=$GCP_BOOT_DISK_SIZE \
      --scopes=$GCP_SCOPES \
      --container-env DUT=$DUT \
      --container-env DURATION_MINS=$DURATION_MINS \
      --container-env GCS_DATA_BUCKET=$GCS_DATA_BUCKET \
      --container-env RUN_ON_GCP=1 \
      --container-command=/bin/bash
    echo -e "${GREEN}VM launched!${NC}"
  done
  echo -e "${GREEN}Done.${NC}"
done
