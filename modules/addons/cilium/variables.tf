variable "cilium_version" {
  description = "Cilium Helm chart version"
  type        = string
  default     = "1.19.6"
}

variable "k8s_service_host" {
  description = "Address Cilium uses to reach the Kubernetes API. localhost targets KubePrism on the node."
  type        = string
  default     = "localhost"
}

variable "k8s_service_port" {
  description = "Port Cilium uses to reach the Kubernetes API"
  type        = number
  default     = 7445
}

variable "lb_ipam_pool_name" {
  description = "Name of the CiliumLoadBalancerIPPool and its matching L2 announcement policy"
  type        = string
  default     = "default"
}

variable "lb_ipam_range" {
  description = "Inclusive address range Cilium LB IPAM assigns to LoadBalancer services"

  type = object({
    start = string
    stop  = string
  })

  validation {
    condition = alltrue([
      can(cidrhost("${var.lb_ipam_range.start}/32", 0)),
      can(cidrhost("${var.lb_ipam_range.stop}/32", 0)),
    ])

    error_message = "lb_ipam_range start and stop must both be IPv4 addresses."
  }
}

variable "l2_announcement_interfaces" {
  description = "Regular expressions matching the node interfaces that answer ARP for LoadBalancer IPs"
  type        = list(string)
  default     = ["^eth[0-9]+"]
}

variable "l2_announce_on_control_plane" {
  description = "Let control-plane nodes answer ARP as well. Off by default so traffic only lands on nodes that run workloads."
  type        = bool
  default     = false
}

variable "k8s_client_rate_limit" {
  description = "API server client rate limit for the Cilium agent, raised to absorb L2 announcement leader election"

  type = object({
    qps   = number
    burst = number
  })

  default = {
    qps   = 50
    burst = 100
  }
}

variable "cilium_extra_values" {
  description = "Extra Cilium Helm values merged over the defaults, for example to enable Hubble"
  type        = any
  default     = {}
}

variable "helm_timeout" {
  description = "Seconds to wait for the Cilium release to become ready"
  type        = number
  default     = 900
}
