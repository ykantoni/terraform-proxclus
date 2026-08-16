variable "proxmox_node" {
  type = string
}

variable "datastore_id" {
  type = string
}

variable "bridge" {
  type = string
}

variable "talos_iso" {
  type = string
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
  }))
}
