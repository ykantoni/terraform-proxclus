resource "proxmox_virtual_environment_vm" "talos" {
  for_each = var.nodes

  name      = each.value.name
  vm_id     = each.value.vm_id
  node_name = var.proxmox_node

  description = "Talos ${each.value.role} managed by Terraform"

  tags = [
    "terraform",
    "talos",
    each.value.role
  ]

  machine = "q35"
  bios    = "ovmf"

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  network_device {
    bridge      = var.bridge
    model       = "virtio"
    mac_address = each.value.mac
  }

  disk {
    datastore_id = var.datastore_id
    interface    = "scsi0"
    size         = each.value.disk
    discard      = "on"
    ssd          = true
  }

  efi_disk {
    datastore_id = var.datastore_id
    type         = "4m"
  }

  cdrom {
    file_id = var.talos_iso
  }

  serial_device {
    device = "socket"
  }

  operating_system {
    type = "l26"
  }

  started = true
}
data "proxmox_virtual_environment_vms" "all" {}