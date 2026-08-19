# One module per addon. Addons that need machine-config changes keep them as
# static patch files and hand them to module.talos_cluster through its
# *_config_patches inputs; see modules/talos-cluster/README.md.

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
