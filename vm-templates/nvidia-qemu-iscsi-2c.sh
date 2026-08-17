/usr/bin/curl -X POST -s  --data-binary @customization.yaml   https://factory.talos.dev/schematics | jq .

/usr/bin/wget -O /tmp/nocloud-amd64.raw.xz https://factory.talos.dev/image/7e800890378b7f11847cc407e61c6559027d9d569e7e67df3643ef018e10c523/v1.13.8/nocloud-amd64.raw.xz

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

sudo /usr/sbin/qm set 9000 --boot order=scsi0
sudo /usr/sbin/qm set 9000 --serial0 socket
sudo /usr/sbin/qm set 9000 --vga serial0
sudo /usr/sbin/qm set 9000 --agent enabled=1

sudo /usr/sbin/qm template 9000

