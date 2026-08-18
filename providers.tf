provider "proxmox" {
  endpoint = var.proxmox_endpoint
  insecure = true
}

provider "talos" {
}

# Referencing the resource rather than the literal path keeps provider
# configuration ordered after the kubeconfig is written.
provider "helm" {
  kubernetes = {
    config_path = local_sensitive_file.kubeconfig.filename
  }
}
