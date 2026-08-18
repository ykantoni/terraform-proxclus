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
