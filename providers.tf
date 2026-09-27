provider "proxmox" {
  insecure = true
}

# Reads the kubeconfig that local_sensitive_file.kubeconfig (main.tf) writes to
# the same path. The file is read when the provider is configured, so on a
# fresh build it must already exist (a prior apply, or `just generate`) before
# the addons can be applied.
provider "helm" {
  kubernetes = {
    config_path = pathexpand("~/.kube/config")
  }
}

# Used only for the handful of raw Kubernetes objects (namespace labels, and
# the like) that don't belong inside a Helm release, per-addon. Configured the
# same way as the helm provider, from the same kubeconfig.
provider "kubernetes" {
  config_path = pathexpand("~/.kube/config")
}
