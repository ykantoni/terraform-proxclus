#!/usr/bin/env bash
set -euo pipefail

"$(dirname "$0")/build-template.sh" talos-1.13.8-nvidia-qemu-iscsi-2c gpu 9001
