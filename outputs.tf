output "nodes" {
  value = module.proxmox_vm.nodes
}

output "controlplane_ips" {
  value = module.rke2_cluster.controlplane_ips
}

output "worker_ips" {
  value = module.rke2_cluster.worker_ips
}

output "kubeconfig" {
  sensitive = true
  value     = module.rke2_cluster.kubeconfig
}

output "ssh_admin_user" {
  value = module.rke2_config.ssh_admin_user
}

output "ssh_private_key" {
  description = "Terraform-managed SSH private key for ssh_admin_user, for manual access (e.g. `terraform output -raw ssh_private_key > ~/.ssh/rke2_admin` per Justfile's generate recipe)"
  sensitive   = true
  value       = module.rke2_config.ssh_private_key_pem
}

output "kubeconfig_path" {
  value = local_sensitive_file.kubeconfig.filename
}

output "load_balancer_ip_range" {
  value = one(module.cilium[*].load_balancer_ip_range)
}

output "grafana_service_type" {
  description = "Kubernetes Service type Grafana is exposed as, when enable_prometheus = true. When LoadBalancer, find the assigned address with: kubectl -n monitoring get svc kube-prometheus-stack-grafana"
  value       = one(module.prometheus[*].grafana_service_type)
}

output "prometheus_service_type" {
  description = "Kubernetes Service type Prometheus's web UI is exposed as, when enable_prometheus = true. When LoadBalancer, find the assigned address with: kubectl -n monitoring get svc kube-prometheus-stack-prometheus"
  value       = one(module.prometheus[*].prometheus_service_type)
}