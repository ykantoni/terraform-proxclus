resource "proxmox_virtual_environment_vm" "node" {
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
    "rke2",
    each.value.role
  ]

  clone {
    # var.template_vm_id_common is the plain hardened-Ubuntu+RKE2 template;
    # var.template_vm_id_gpu additionally carries the NVIDIA driver and
    # container toolkit, pre-baked by packer/ubuntu-gpu.pkr.hcl, and is only
    # for nodes with a GPU passed through.
    vm_id = try(each.value.pcigpu, null) != null ? var.template_vm_id_gpu : var.template_vm_id_common
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

  # Unlike modules/proxmox-talos-vm (Talos configures its own networking
  # from machine config, not cloud-init), this module's VMs are Ubuntu, so
  # static networking and the RKE2/hostname user-data both ride on Proxmox's
  # native cloud-init integration. ip_config/dns are handled here, at the
  # VM-resource level, because they're intrinsically per-VM Proxmox
  # settings; the user-data content itself (RKE2 config, kube-vip manifest,
  # SSH key) is rendered and uploaded as a snippet by modules/rke2-config,
  # and only referenced here by ID.
  initialization {
    datastore_id = var.datastore_id

    ip_config {
      ipv4 {
        address = "${each.value.ip}/${each.value.cidr}"
        gateway = var.gateway
      }
    }

    dns {
      servers = var.nameservers
    }

    user_data_file_id = var.cloudinit_file_ids[each.key]
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
