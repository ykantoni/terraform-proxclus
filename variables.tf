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

variable "controlplane_vip" {
  type    = string
  default = "192.168.1.99"
}

variable "cni" {
  description = "Cluster CNI. cilium keeps Talos from deploying Flannel and kube-proxy and installs Cilium in their place."
  type        = string
  default     = "cilium"

  validation {
    condition     = contains(["flannel", "cilium"], var.cni)
    error_message = "cni must be either flannel or cilium."
  }
}

variable "cilium_version" {
  description = "Cilium Helm chart version"
  type        = string
  default     = "1.19.6"
}

variable "kube_prism_port" {
  description = "Port the per-node KubePrism API server proxy listens on"
  type        = number
  default     = 7445
}

variable "wait_for_health" {
  description = "Health check the cluster before installing addons. Turn off to plan against a cluster that is down."
  type        = bool
  default     = true
}

variable "wait_for_api" {
  description = "Poll the Kubernetes API at controlplane_vip until it answers before installing addons. Narrower than wait_for_health: it only proves the API server is reachable, so it stays useful even when wait_for_health is off."
  type        = bool
  default     = true
}

variable "enable_longhorn" {
  description = "Install Longhorn as the cluster's default CSI provider for dynamic PV provisioning. Also adds the /var/lib/longhorn kubelet mount to every node's machine configuration; turning this on reboots every node."
  type        = bool
  default     = false
}

variable "longhorn_version" {
  description = "Longhorn Helm chart version"
  type        = string
  default     = "1.8.1"
}

variable "longhorn_replica_count" {
  description = "Default number of replicas Longhorn keeps for each volume"
  type        = number
  default     = 3
}

variable "load_balancer_ip_range" {
  description = "Inclusive address range Cilium hands to LoadBalancer services. Must be free on the node subnet."

  type = object({
    start = string
    stop  = string
  })

  validation {
    condition = alltrue([
      can(cidrhost("${var.load_balancer_ip_range.start}/32", 0)),
      can(cidrhost("${var.load_balancer_ip_range.stop}/32", 0)),
    ])

    error_message = "load_balancer_ip_range start and stop must both be IPv4 addresses."
  }
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

    pcigpu = optional(string, null)
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