output "cloudinit_file_ids" {
  description = "Map of node key -> Proxmox snippet file ID, for modules/proxmox-vm's initialization.user_data_file_id"

  value = {
    for key, file in proxmox_virtual_environment_file.cloudinit :
    key => file.id
  }
}

output "ssh_admin_user" {
  value = var.ssh_admin_user
}

output "ssh_private_key_pem" {
  description = "Private half of the Terraform-managed SSH keypair, for modules/rke2-cluster to reach nodes with"
  sensitive   = true
  value       = tls_private_key.ssh.private_key_openssh
}

output "bootstrap_ip" {
  description = "IP of the node modules/rke2-cluster should SSH to for readiness polling and kubeconfig retrieval"
  value       = local.bootstrap_node.ip
}
