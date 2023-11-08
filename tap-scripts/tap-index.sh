#!/bin/bash
# Copyright 2022 VMware, Inc.
# SPDX-License-Identifier: BSD-2-Clause
source var.conf

chmod +x tap-view.sh
chmod +x tap-run.sh
chmod +x tap-build.sh
chmod +x tanzu-cli-setup.sh
chmod +x tap-demo-app-deploy.sh
chmod +x tap-iterate.sh
chmod +x tap-iterate.sh

chmod +x var-input-validatation.sh

#./var-input-validatation.sh
echo "Step 1 => installing tanzu cli !!!"
./tanzu-cli-setup.sh
echo "Step 2 => Setup TAP View Cluster"
./tap-view.sh
echo "Step 3 => Setup TAP Run Cluster"
./tap-run.sh
echo "Step 4 => Setup TAP Build Cluster"
./tap-build.sh
echo "Step 5 => Setup TAP Iterate Cluster"
./tap-iterate.sh
echo "Step 6 => Create DNS records in Route53"
./route53-record.sh

echo "Step 7 => Deploy sample app"
./tap-demo-app-deploy.sh