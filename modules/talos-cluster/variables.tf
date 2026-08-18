variable "cluster_name" {
  type = string
}

variable "talos_version" {
  type = string
}

variable "gateway" {
  type = string
}

variable "nameservers" {
  type = list(string)
}

variable "talos_schematic_id" {
  description = "Talos Image Factory schematic ID"
  type        = string
}

variable "controlplane_vip" {
  type    = string
  default = "192.168.1.99"
}

variable "nodes" {
  type = map(object({
    vm_id  = number
    name   = string
    ip     = string
    cidr   = number
    mac    = string
    role   = string
    pcigpu = string
  }))
}