
module "proxmox_talos_vms" {
  source = "./modules/proxmox-talos-vm"

  proxmox_node = var.proxmox_node
  datastore_id = var.datastore_id
  bridge       = var.bridge

  nodes = var.nodes
}
module "talos_cluster" {
  source = "./modules/talos-cluster"

  cluster_name              = var.cluster_name
  talos_version             = var.talos_version
  talos_schematic_id_common = talos_image_factory_schematic.common.id
  talos_schematic_id_gpu    = talos_image_factory_schematic.gpu.id
  gateway                   = var.gateway
  nameservers               = var.nameservers
  controlplane_vip          = var.controlplane_vip
  external_ip               = var.external_ip
  cni                       = var.cni
  kube_prism_port           = var.kube_prism_port
  wait_for_health           = var.wait_for_health
  wait_for_api              = var.wait_for_api

  config_patches = var.enable_longhorn ? [
    file("${path.module}/modules/addons/longhorn/patches/longhorn-mounts.patch.yaml")
  ] : []

  nodes = module.proxmox_talos_vms.nodes
}

resource "local_sensitive_file" "kubeconfig" {
  filename = "${path.root}/.kube/config"
  content  = module.talos_cluster.kubeconfig

  file_permission      = "0600"
  directory_permission = "0700"
}
