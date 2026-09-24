#!/usr/bin/env bash
# Replaces the siderolabs/iscsi-tools and siderolabs/util-linux-tools Talos
# system extensions from the old customization-common.yaml/customization-
# gpu.yaml: Longhorn's engine needs open-iscsi (iscsid) and standard
# block-device tooling on every node regardless of whether this particular
# node ends up hosting Longhorn replicas.
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends open-iscsi nfs-common util-linux
systemctl enable --now iscsid
