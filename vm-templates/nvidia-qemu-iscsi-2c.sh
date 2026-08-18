set -euo pipefail

TALOS_VERSION=v1.13.8

# Same customization.yaml Terraform derives the installer schematic from, so the
# template image and the machine configuration can never reference different
# extension sets.
SCHEMATIC_ID=$(/usr/bin/curl -X POST -sf --data-binary @../customization.yaml https://factory.talos.dev/schematics | jq -r .id)
echo "schematic: ${SCHEMATIC_ID}"

/usr/bin/wget -O /tmp/nocloud-amd64.raw.xz "https://factory.talos.dev/image/${SCHEMATIC_ID}/${TALOS_VERSION}/nocloud-amd64.raw.xz"

/usr/bin/bash -c "pushd /tmp && /usr/bin/xz -d -k /tmp/nocloud-amd64.raw.xz && popd"

sudo /usr/sbin/qm create 9000 \
  --name talos-1.13.8-nvidia-qemu-iscsi-2c \
  --memory 4096 \
  --cores 2 \
  --cpu host \
  --machine q35 \
  --bios ovmf \
  --net0 virtio,bridge=vmbr0

sudo /usr/sbin/qm set 9000 --efidisk0 sdc-storage:1,efitype=4m,pre-enrolled-keys=0

sudo /usr/sbin/qm importdisk 9000 /tmp/nocloud-amd64.raw sdc-storage

sudo /usr/sbin/qm set 9000   --scsihw virtio-scsi-pci   --scsi0 sdc-storage:9000/vm-9000-disk-1.raw

sudo /usr/sbin/qm resize 9000 scsi0 32G

sudo /usr/sbin/qm set 9000 --boot order=scsi0
sudo /usr/sbin/qm set 9000 --serial0 socket
sudo /usr/sbin/qm set 9000 --vga std
sudo /usr/sbin/qm set 9000 --agent enabled=1

sudo /usr/sbin/qm template 9000

