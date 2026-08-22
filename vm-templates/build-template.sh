#!/usr/bin/env bash
set -euo pipefail

# Shared builder behind qemu-iscsi-2c.sh and nvidia-qemu-iscsi-2c.sh. Those
# scripts just pick a name and an image type; everything else lives here so
# there is one place that knows how a template gets built.
#
# Usage: build-template.sh <vm-name> <common|gpu> [vmid]

usage() {
  echo "Usage: $0 <vm-name> <common|gpu> [vmid]" >&2
}

if [[ $# -lt 2 ]]; then
  usage
  exit 1
fi

VM_NAME="$1"
IMAGE_TYPE="$2"
VMID="${3:-9000}"

case "${IMAGE_TYPE}" in
  common|gpu) ;;
  *)
    echo "Unknown image type '${IMAGE_TYPE}': expected 'common' or 'gpu'" >&2
    usage
    exit 1
    ;;
esac

TALOS_VERSION=v1.13.8

# Resolve relative to this script, not the caller's cwd, so it works whether
# invoked as ./nvidia-qemu-iscsi-2c.sh from vm-templates/ or as
# vm-templates/nvidia-qemu-iscsi-2c.sh from anywhere else.
SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
CUSTOMIZATION_FILE="${SCRIPT_DIR}/../customization-${IMAGE_TYPE}.yaml"
RAW_IMAGE="/tmp/nocloud-${IMAGE_TYPE}-amd64.raw"

# Same customization-*.yaml Terraform derives the installer schematic from, so the
# template image and the machine configuration can never reference different
# extension sets.
SCHEMATIC_ID=$(/usr/bin/curl -X POST -sf --data-binary @"${CUSTOMIZATION_FILE}" https://factory.talos.dev/schematics | jq -r .id)
echo "schematic: ${SCHEMATIC_ID}"

# Drop any stale download from a previous run before fetching a fresh one:
# a prior interrupted run can leave one of these owned or locked in a way
# that a plain overwrite can't get past, even as root.
sudo rm -f "${RAW_IMAGE}.xz" "${RAW_IMAGE}"

sudo /usr/bin/wget -O "${RAW_IMAGE}.xz" "https://factory.talos.dev/image/${SCHEMATIC_ID}/${TALOS_VERSION}/nocloud-amd64.raw.xz"

# xz always decompresses alongside the source name, so land it under a
# type-specific name in case common and gpu builds run back to back.
sudo /usr/bin/xz -d -k -f "${RAW_IMAGE}.xz"

sudo /usr/sbin/qm create "${VMID}" \
  --name "${VM_NAME}" \
  --memory 4096 \
  --cores 2 \
  --cpu host \
  --machine q35 \
  --bios ovmf \
  --net0 virtio,bridge=vmbr0

sudo /usr/sbin/qm set "${VMID}" --efidisk0 sdc-storage:1,efitype=4m,pre-enrolled-keys=0

sudo /usr/sbin/qm importdisk "${VMID}" "${RAW_IMAGE}" sdc-storage

sudo /usr/sbin/qm set "${VMID}" --scsihw virtio-scsi-pci --scsi0 "sdc-storage:${VMID}/vm-${VMID}-disk-1.raw"

sudo /usr/sbin/qm resize "${VMID}" scsi0 32G

sudo /usr/sbin/qm set "${VMID}" --boot order=scsi0
sudo /usr/sbin/qm set "${VMID}" --serial0 socket
sudo /usr/sbin/qm set "${VMID}" --vga std
sudo /usr/sbin/qm set "${VMID}" --agent enabled=1

sudo /usr/sbin/qm template "${VMID}"
