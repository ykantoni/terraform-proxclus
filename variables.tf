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

variable "cluster_name" {
  description = "Kubernetes cluster name"
  type        = string
}

variable "ssh_admin_user" {
  description = "Username created on every node via cloud-init, with passwordless sudo and the Terraform-managed SSH key as its only auth method. modules/rke2-cluster uses this account to poll readiness and fetch the kubeconfig; nothing else needs interactive SSH access as a matter of course."
  type        = string
  default     = "rke2admin"
}

variable "template_vm_id_common" {
  description = "Proxmox template ID cloned by nodes without a pcigpu. Built by packer/ubuntu-common.pkr.hcl; see packer/README.md."
  type        = number
  default     = 9100
}

variable "template_vm_id_gpu" {
  description = "Proxmox template ID cloned by nodes with a pcigpu set. Built by packer/ubuntu-gpu.pkr.hcl; see packer/README.md."
  type        = number
  default     = 9101
}

variable "api_wait_timeout" {
  description = "Seconds to poll the bootstrap node over SSH for an active rke2-server before giving up, when wait_for_api is on"
  type        = number
  default     = 300
}

variable "api_wait_interval" {
  description = "Seconds between polls, when wait_for_api is on"
  type        = number
  default     = 5
}

variable "gateway" {
  description = "Default network gateway"
  type        = string
}

variable "nameservers" {
  description = "DNS servers"
  type        = list(string)
}

variable "controlplane_vip" {
  description = "Floating IP kube-vip advertises for the API server (ARP mode, run as an RKE2 auto-deployed manifest on the control-plane node). Kept as a stable endpoint distinct from any one node's own IP, the same property Talos's Layer2VIPConfig gave this cluster, ready for a second control-plane node later without reconfiguring every client."
  type        = string
  default     = "192.168.1.99"
}

variable "external_ip" {
  description = "Public IP address or hostname a router NATs through to controlplane_vip, so the cluster can be reached from outside the LAN. Added to the control-plane's RKE2 tls-san; the NAT rule itself is configured on the router, not by Terraform. Leave null (the default) to keep the cluster LAN-only."
  type        = string
  default     = "91.152.206.161"
}

variable "cni" {
  description = "Cluster CNI. cilium sets cni: none and disable-kube-proxy: true in every node's RKE2 config (see modules/rke2-config) and installs Cilium in their place."
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

variable "enable_hubble_ui" {
  description = "Install Hubble Relay + Hubble UI behind Cilium, giving a web dashboard of live CNI traffic (service map, policy verdicts, DNS, L7 flows). Touches no machine configuration and needs no reboot, so it defaults on. Ignored when cni != \"cilium\"."
  type        = bool
  default     = true
}

variable "hubble_ui_service_type" {
  description = "Kubernetes Service type Hubble UI's web UI is exposed as. LoadBalancer (the default) gets an address from Cilium's load_balancer_ip_range, since this cluster runs no ingress controller; see the root README's \"Networking\" section."
  type        = string
  default     = "LoadBalancer"
}

variable "wait_for_api" {
  description = "Poll the bootstrap node over SSH until rke2-server is active, then fetch its kubeconfig, before installing addons. Turn off to plan against a cluster that is down."
  type        = bool
  default     = true
}

variable "enable_longhorn" {
  description = "Install Longhorn as the cluster's default CSI provider for dynamic PV provisioning. Unlike under Talos, this needs no machine-config change or reboot to turn on: a normal Ubuntu kubelet already sees /var/lib/longhorn with no extra mount configuration."
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

variable "enable_metrics_server" {
  description = "Install metrics-server, so kubectl top and the HorizontalPodAutoscaler have resource metrics to read. Unlike enable_longhorn, this touches no machine configuration and needs no reboot, so it defaults on."
  type        = bool
  default     = true
}

variable "metrics_server_version" {
  description = "metrics-server Helm chart version"
  type        = string
  default     = "3.14.0"
}

variable "enable_prometheus" {
  description = "Install kube-prometheus-stack (Prometheus, Grafana, Alertmanager, node-exporter, kube-state-metrics) for cluster monitoring. Its PVCs default to the \"longhorn\" StorageClass (see modules/addons/prometheus's storage_class default), so this needs enable_longhorn = true too. Touches no machine configuration and needs no reboot on its own."
  type        = bool
  default     = false
}

variable "kube_prometheus_stack_version" {
  description = "kube-prometheus-stack Helm chart version"
  type        = string
  default     = "90.0.0"
}

variable "grafana_admin_password" {
  description = "Grafana admin login password. Defaults to the chart's own default (\"prom-operator\"); override before relying on enable_prometheus's default LoadBalancer exposure, which puts Grafana's login page on the LAN."
  type        = string
  default     = "prom-operator"
  sensitive   = true
}

variable "nvidia_device_plugin_version" {
  description = "nvidia-device-plugin Helm chart version. Only installed when at least one node in var.nodes sets pcigpu; see modules/addons/nvidia-device-plugin."
  type        = string
  default     = "0.20.0"
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
  description = "Cluster nodes"

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