#!/usr/bin/env bash
# GPU image only (packer/ubuntu-gpu.pkr.hcl). Replaces the
# siderolabs/nvidia-open-gpu-kernel-modules-production and
# siderolabs/nvidia-container-toolkit-production Talos system extensions:
# driver + container toolkit installed via apt, then nvidia-ctk registers the
# "nvidia" containerd runtime handler in RKE2's containerd config template so
# it's live as soon as rke2-agent/rke2-server starts on this node (see
# modules/addons/nvidia-device-plugin, which expects that handler to already
# exist by the name in its runtime_class_name variable, default "nvidia").
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive

apt-get update
apt-get install -y --no-install-recommends nvidia-driver-open nvidia-container-toolkit

# RKE2 templates its bundled containerd's config from this file at
# containerd start, rather than reading /etc/containerd/config.toml
# directly (that's the plain-containerd path, not RKE2's) -- nvidia-ctk
# needs to be told that explicitly.
mkdir -p /var/lib/rancher/rke2/agent/etc/containerd
nvidia-ctk runtime configure \
  --runtime=containerd \
  --config=/var/lib/rancher/rke2/agent/etc/containerd/config.toml.tmpl

echo "nvidia-driver-open and nvidia-container-toolkit installed; verify with nvidia-smi after first boot on real hardware -- Packer's build VM has no GPU passed through, so nvidia-smi will not work during this provisioning step itself."
