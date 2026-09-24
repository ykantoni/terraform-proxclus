variable "proxmox_node" {
  type = string
}

variable "datastore_id" {
  type = string
}

variable "bridge" {
  type = string
}

variable "gateway" {
  description = "Default network gateway, applied to every node via Proxmox cloud-init (initialization.ip_config)"
  type        = string
}

variable "nameservers" {
  description = "DNS servers, applied to every node via Proxmox cloud-init (initialization.dns)"
  type        = list(string)
}

variable "template_vm_id_common" {
  description = "Proxmox template ID cloned by nodes without a pcigpu, built by packer/ubuntu-common.pkr.hcl"
  type        = number
}

variable "template_vm_id_gpu" {
  description = "Proxmox template ID cloned by nodes with a pcigpu set, built by packer/ubuntu-gpu.pkr.hcl"
  type        = number
}

variable "cloudinit_file_ids" {
  description = "Map of node key -> Proxmox snippet file ID for that node's cloud-init user-data, from module.rke2_config. Keyed the same way as var.nodes, deliberately not sourced from any VM-derived value, so this module can be planned independently of whether the VMs already exist."
  type        = map(string)
}

variable "nodes" {
  type = map(object({
    vm_id = number
    name  = string
    ip    = string
    cidr  = optional(number, 24)
    mac   = string
    role  = string

    cores  = optional(number, 4)
    memory = optional(number, 4096)
    disk   = optional(number, 32)
    pcigpu = optional(string, null)
  }))
}
