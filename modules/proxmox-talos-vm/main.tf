resource "proxmox_virtual_environment_vm" "talos" {
  for_each = var.nodes

  name                = each.value.name
  vm_id               = each.value.vm_id
  node_name           = var.proxmox_node
  reboot_after_update = false
  stop_on_destroy     = true
  timeout_shutdown_vm = 60
  timeout_stop_vm     = 60

  tags = [
    "terraform",
    "talos",
    each.value.role
  ]
  clone {
    # 9000 is the plain template (vm-templates/qemu-iscsi-2c.sh); 9001 carries
    # the NVIDIA system extensions (vm-templates/nvidia-qemu-iscsi-2c.sh) and
    # is only for nodes with a GPU passed through.
    vm_id = try(each.value.pcigpu, null) != null ? 9001 : 9000
    full  = true
  }

  cpu {
    cores = each.value.cores
    type  = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    interface    = "scsi0"
    datastore_id = var.datastore_id
    size         = each.value.disk

    cache   = "writethrough"
    discard = "on"
    ssd     = true
  }

  network_device {
    bridge      = var.bridge
    model       = "virtio"
    mac_address = each.value.mac
  }

  dynamic "hostpci" {
    for_each = try(each.value.pcigpu, null) != null ? [each.value.pcigpu] : []

    content {
      device  = "hostpci0"
      mapping = hostpci.value
      pcie    = true
    }
  }

  agent {
    enabled = true
  }

  boot_order = ["scsi0"]

  serial_device {
    device = "socket"
  }
}

data "proxmox_virtual_environment_vms" "all" {}