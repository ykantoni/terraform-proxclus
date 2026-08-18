output "talos_nodes" {
  value = module.proxmox_talos_vms.nodes
}

output "controlplane_ips" {
  value = module.talos_cluster.controlplane_ips
}

output "worker_ips" {
  value = module.talos_cluster.worker_ips
}

output "kubeconfig" {
  sensitive = true
  value     = module.talos_cluster.kubeconfig
}

output "talosconfig" {
  sensitive = true
  value     = module.talos_cluster.talosconfig
}

output "kubeconfig_path" {
  value = local_sensitive_file.kubeconfig.filename
}

output "load_balancer_ip_range" {
  value = one(module.cilium[*].load_balancer_ip_range)
}

output "talos_schematic_id" {
  value = talos_image_factory_schematic.this.id
}