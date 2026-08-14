output "nodes" {
  description = "Provisioned Talos VM definitions"

  value = {
    for key, node in var.nodes :
    key => {
      vm_id = proxmox_virtual_environment_vm.talos[key].vm_id

      name = node.name
      ip   = node.ip
      cidr = node.cidr
      mac  = node.mac
      role = node.role
    }
  }
}
output "vm_ids" {
  value = {
    for key, vm in proxmox_virtual_environment_vm.talos :
    key => vm.vm_id
  }
}
output "proxmox_vms" {
  value = data.proxmox_virtual_environment_vms.all.vms
}

