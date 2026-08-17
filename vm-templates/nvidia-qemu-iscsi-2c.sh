/usr/bin/curl -X POST -s  --data-binary @customization.yaml   https://factory.talos.dev/schematics | jq .

/usr/bin/wget -O /tmp https://factory.talos.dev/image/8f585b1e244c9e2a33a8abe0f7d6a7fef0710d8d40b05442eb1b651f9679f13d/v1.13.8/nocloud-amd64.raw.xz

pushd /tmp && /usr/bin/xz -d -k /tmp/nocloud-amd64.raw.xz && popd

/usr/sbin/qm create 9000 \
  --name talos-1.13.8-nvidia-qemu-iscsi-2c \
  --memory 4096 \
  --cores 2 \
  --cpu host \
  --machine q35 \
  --bios ovmf \
  --net0 virtio,bridge=vmbr0

/usr/sbin/qm set 9000 --efidisk0 sdc-storage:1,efitype=4m,pre-enrolled-keys=0

/usr/sbin/qm importdisk 9000 /tmp/nocloud-amd64.raw sdc-storage

/usr/sbin/qm set 9000   --scsihw virtio-scsi-pci   --scsi0 sdc-storage:9000/vm-9000-disk-1.raw

/usr/sbin/qm set 9000 --boot order=scsi0
/usr/sbin/qm set 9000 --serial0 socket
/usr/sbin/qm set 9000 --vga serial0
/usr/sbin/qm set 9000 --agent enabled=1

/usr/sbin/qm template 9000

