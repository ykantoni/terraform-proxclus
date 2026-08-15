resource "proxmox_virtual_environment_vm" "talos" {
  for_each = var.nodes

  name            = each.value.name
  vm_id           = each.value.vm_id
  node_name       = var.proxmox_node
  description     = "Talos ${each.value.role} managed by Terraform"
  stop_on_destroy = true
  tags = [
    "terraform",
    "talos",
    each.value.role
  ]
  agent {
    enabled = true
    trim    = true
    type    = "virtio"
  }

  machine = "q35"
  bios    = "ovmf"

  acpi = false

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
    cache        = "writethrough"
    discard      = "on"
    ssd          = true
    backup       = false
    aio          = "io_uring"
  }

  efi_disk {
    datastore_id      = var.datastore_id
    type              = "4m"
    pre_enrolled_keys = false
    file_format       = "qcow2"
  }

  boot_order = var.boot_from_iso ? ["ide3", "scsi0"] : ["scsi0", "ide3"]

  cdrom {
    #    file_id   = var.boot_from_iso ? var.talos_iso : "none"
    file_id = var.talos_iso
  }

  serial_device {
    device = "socket"
  }

  vga {
    type = "std"
  }
  operating_system {
    type = "l26"
  }

  started = true
}
data "proxmox_virtual_environment_vms" "all" {}