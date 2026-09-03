# One module per addon. Addons that need machine-config changes keep them as
# static patch files and hand them to module.talos_cluster through its
# *_config_patches inputs; see modules/talos-cluster/README.md.

locals {
  # pcigpu is already the cluster's single source of truth for "this node has
  # a GPU" — it drives the schematic (gpu vs common) and the nvidia-modules
  # kernel patch in modules/talos-cluster. Deriving the device plugin's
  # presence from the same field, instead of a second independent enable
  # flag, means there is nothing to keep in sync: map a GPU to a node here
  # and the plugin follows automatically.
  gpu_node_ips = [
    for node in var.nodes : node.ip
    if try(node.pcigpu, null) != null
  ]
}

module "cilium" {
  source = "./modules/addons/cilium"

  count = var.cni == "cilium" ? 1 : 0

  cilium_version   = var.cilium_version
  k8s_service_port = var.kube_prism_port
  lb_ipam_range    = var.load_balancer_ip_range

  depends_on = [
    module.talos_cluster,
    local_sensitive_file.kubeconfig,
  ]
}

module "longhorn" {
  source = "./modules/addons/longhorn"

  count = var.enable_longhorn ? 1 : 0

  longhorn_version = var.longhorn_version
  replica_count    = var.longhorn_replica_count

  # module.talos_cluster's health check skips node-readiness and coredns once
  # cni is cilium, since Talos itself never brings up a CNI in that mode. So
  # depending on it only proves Talos booted, not that pods can get an IP.
  # Longhorn's manager DaemonSet needs pod networking to come up at all, so it
  # must also wait on module.cilium's helm_release, which is the thing that
  # actually proves the CNI is ready. Referencing the bare module here (no
  # index) is still valid when cni is flannel and module.cilium has zero
  # instances; module.talos_cluster's own health check covers CNI readiness
  # in that case instead, since Talos runs Flannel itself.
  depends_on = [
    module.talos_cluster,
    module.cilium,
    local_sensitive_file.kubeconfig,
  ]
}

module "metrics_server" {
  source = "./modules/addons/metrics-server"

  count = var.enable_metrics_server ? 1 : 0

  metrics_server_version = var.metrics_server_version

  # Same reasoning as module.longhorn: needs pod networking up, which
  # module.talos_cluster's own health check only guarantees when cni is
  # flannel, so it also waits on module.cilium's helm_release when cni is
  # cilium.
  depends_on = [
    module.talos_cluster,
    module.cilium,
    local_sensitive_file.kubeconfig,
  ]
}

module "nvidia_device_plugin" {
  source = "./modules/addons/nvidia-device-plugin"

  count = length(local.gpu_node_ips) > 0 ? 1 : 0

  gpu_node_ips                 = local.gpu_node_ips
  nvidia_device_plugin_version = var.nvidia_device_plugin_version

  # Same reasoning as module.longhorn: needs pod networking up, which
  # module.talos_cluster's own health check only guarantees when cni is
  # flannel, so it also waits on module.cilium's helm_release when cni is
  # cilium.
  depends_on = [
    module.talos_cluster,
    module.cilium,
    local_sensitive_file.kubeconfig,
  ]
}
