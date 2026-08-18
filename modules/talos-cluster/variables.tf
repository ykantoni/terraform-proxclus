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

variable "cni" {
  description = "Cluster CNI. cilium tells Talos to deploy neither Flannel nor kube-proxy, leaving both to Cilium."
  type        = string
  default     = "cilium"

  validation {
    condition     = contains(["flannel", "cilium"], var.cni)
    error_message = "cni must be either flannel or cilium."
  }
}

variable "kube_prism_port" {
  description = "Port the per-node KubePrism API server proxy listens on"
  type        = number
  default     = 7445
}

variable "config_patches" {
  description = "Extra machine configuration patches applied to every node, as YAML strings. Must be static: a value read from the cluster would make the cluster depend on its own addons."
  type        = list(string)
  default     = []
}

variable "controlplane_config_patches" {
  description = "Extra machine configuration patches applied to control-plane nodes only"
  type        = list(string)
  default     = []
}

variable "worker_config_patches" {
  description = "Extra machine configuration patches applied to worker nodes only"
  type        = list(string)
  default     = []
}

variable "wait_for_health" {
  description = "Health check the cluster so dependents only run once the nodes are up. Turn off to plan against a cluster that is down."
  type        = bool
  default     = true
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