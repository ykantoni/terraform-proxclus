variable "proxmox_endpoint" {
  description = "Proxmox VE API endpoint"
  type        = string
}

variable "proxmox_node" {
  description = "Proxmox node on which the VMs are created"
  type        = string
}

variable "datastore_id" {
  description = "Proxmox datastore for Talos VM disks"
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Proxmox network bridge"
  type        = string
  default     = "vmbr0"
}

variable "talos_iso" {
  description = "Existing Talos ISO in Proxmox"
  type        = string
}

variable "cluster_name" {
  description = "Talos/Kubernetes cluster name"
  type        = string
}

variable "talos_version" {
  description = "Talos Linux version used for generated machine configuration"
  type        = string
}

variable "gateway" {
  description = "Default network gateway"
  type        = string
}

variable "nameservers" {
  description = "DNS servers"
  type        = list(string)
}

variable "talos_boot_from_iso" {
  type    = bool
  default = false
}

variable "talos_schematic_id" {
  description = "Talos Image Factory schematic ID"
  type        = string
}

variable "nodes" {
  description = "Talos cluster nodes"

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
  }))

  validation {
    condition = alltrue([
      for node in values(var.nodes) :
      contains(["controlplane", "worker"], node.role)
    ])

    error_message = "role must be either controlplane or worker."
  }
}