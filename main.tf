
module "proxmox_talos_vms" {
  source = "./modules/proxmox-talos-vm"

  proxmox_node = var.proxmox_node
  datastore_id = var.datastore_id
  bridge       = var.bridge
  talos_iso    = var.talos_iso

  nodes = var.nodes
}
module "talos_cluster" {
  source = "./modules/talos-cluster"

  cluster_name  = var.cluster_name
  talos_version = var.talos_version

  gateway     = var.gateway
  nameservers = var.nameservers

  nodes = module.proxmox_talos_vms.nodes
}




