# One module per addon.

locals {
  # pcigpu is already the cluster's single source of truth for "this node has
  # a GPU" — it drives the template selection (gpu vs common) in
  # modules/proxmox-vm and the NVIDIA provisioning in packer/. Deriving the
  # device plugin's presence from the same field, instead of a second
  # independent enable flag, means there is nothing to keep in sync: map a
  # GPU to a node here and the plugin follows automatically.
  gpu_node_ips = [
    for node in var.nodes : node.ip
    if try(node.pcigpu, null) != null
  ]
}

module "cilium" {
  source = "./modules/addons/cilium"

  count = var.cni == "cilium" ? 1 : 0

  cilium_version         = var.cilium_version
  k8s_service_host       = var.controlplane_vip
  lb_ipam_range          = var.load_balancer_ip_range
  enable_hubble_ui       = var.enable_hubble_ui
  hubble_ui_service_type = var.hubble_ui_service_type

  depends_on = [
    module.rke2_cluster,
    local_sensitive_file.kubeconfig,
  ]
}

module "longhorn" {
  source = "./modules/addons/longhorn"

  count = var.enable_longhorn ? 1 : 0

  longhorn_version = var.longhorn_version
  replica_count    = var.longhorn_replica_count

  # module.rke2_cluster's own readiness gate only proves the API server
  # answers (see modules/rke2-cluster/README.md's "no Kubernetes-level
  # health check" section) — it says nothing about pod networking, which
  # RKE2 never brings up itself when cni is cilium (cni: none in every
  # node's config). Longhorn's manager DaemonSet needs pod networking to
  # come up at all, so it must also wait on module.cilium's helm_release,
  # which is the thing that actually proves the CNI is ready. Referencing
  # the bare module here (no index) is still valid when cni is flannel and
  # module.cilium has zero instances; RKE2's own bundled Canal covers CNI
  # readiness in that case instead.
  depends_on = [
    module.rke2_cluster,
    module.cilium,
    local_sensitive_file.kubeconfig,
  ]
}

module "metrics_server" {
  source = "./modules/addons/metrics-server"

  count = var.enable_metrics_server ? 1 : 0

  metrics_server_version = var.metrics_server_version

  # Same reasoning as module.longhorn: needs pod networking up, which
  # module.rke2_cluster's own readiness gate does not guarantee, so it also
  # waits on module.cilium's helm_release when cni is cilium.
  depends_on = [
    module.rke2_cluster,
    module.cilium,
    local_sensitive_file.kubeconfig,
  ]
}

module "prometheus" {
  source = "./modules/addons/prometheus"

  count = var.enable_prometheus ? 1 : 0

  kube_prometheus_stack_version = var.kube_prometheus_stack_version
  grafana_admin_password        = var.grafana_admin_password

  # Same CNI reasoning as module.longhorn and module.metrics_server. Also
  # waits on module.longhorn directly: this module's PVCs (storage_class
  # defaults to "longhorn") need Longhorn's CSI controller actually running
  # to provision, not just its own helm_release having eventually turned
  # Ready under this module's separate wait=true.
  depends_on = [
    module.rke2_cluster,
    module.cilium,
    module.longhorn,
    local_sensitive_file.kubeconfig,
  ]
}

module "nvidia_device_plugin" {
  source = "./modules/addons/nvidia-device-plugin"

  count = length(local.gpu_node_ips) > 0 ? 1 : 0

  gpu_node_ips                 = local.gpu_node_ips
  nvidia_device_plugin_version = var.nvidia_device_plugin_version

  # Same reasoning as module.longhorn: needs pod networking up, which
  # module.rke2_cluster's own readiness gate does not guarantee, so it also
  # waits on module.cilium's helm_release when cni is cilium.
  depends_on = [
    module.rke2_cluster,
    module.cilium,
    local_sensitive_file.kubeconfig,
  ]
}
