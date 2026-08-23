# Which Kubernetes Node object corresponds to each GPU-mapped IP has to be
# resolved at apply time: var.nodes (the root module's source of truth for
# pcigpu) knows each node's Proxmox name and static IP, but nothing pins the
# Kubernetes Node name to either of those — Talos derives it from the node's
# hostname, which this cluster never sets explicitly (see modules/talos-cluster).
# Matching on the InternalIP address Kubernetes itself reports sidesteps that
# guesswork entirely.
data "kubernetes_nodes" "all" {}

locals {
  node_internal_ips = {
    for node in data.kubernetes_nodes.all.nodes :
    node.metadata[0].name => try(
      [
        for address in node.status[0].addresses :
        address.address if address.type == "InternalIP"
      ][0],
      null
    )
  }

  gpu_node_names = [
    for name, ip in local.node_internal_ips :
    name if contains(var.gpu_node_ips, ip)
  ]
}

# Registers the "nvidia" containerd runtime the siderolabs/nvidia-container-toolkit
# extension already configured on the host (see modules/talos-cluster/patches)
# as a Kubernetes RuntimeClass, so GPU workloads can opt in with
# spec.runtimeClassName instead of it being the node's default runtime for
# every pod.
resource "kubernetes_runtime_class_v1" "nvidia" {
  metadata {
    name = var.runtime_class_name
  }

  handler = var.runtime_class_name
}

# The device plugin chart has no built-in way to target only GPU nodes
# (that's normally Node Feature Discovery's job); labelling the nodes this
# module already knows have a GPU and feeding the same label back in as the
# chart's nodeSelector gets the same result without pulling in NFD.
resource "kubernetes_labels" "gpu_node" {
  for_each = toset(local.gpu_node_names)

  api_version = "v1"
  kind        = "Node"

  metadata {
    name = each.value
  }

  labels = {
    (var.gpu_node_label) = "true"
  }

  force = true
}

resource "helm_release" "nvidia_device_plugin" {
  depends_on = [
    kubernetes_runtime_class_v1.nvidia,
    kubernetes_labels.gpu_node,
  ]

  name      = "nvidia-device-plugin"
  namespace = var.namespace

  repository = "https://nvidia.github.io/k8s-device-plugin"
  chart      = "nvidia-device-plugin"
  version    = var.nvidia_device_plugin_version

  wait    = true
  timeout = var.helm_timeout

  # Later entries win, so callers can override any of the defaults above.
  values = [
    yamlencode({
      runtimeClassName = var.runtime_class_name

      nodeSelector = {
        (var.gpu_node_label) = "true"
      }
    }),
    yamlencode(var.nvidia_device_plugin_extra_values),
  ]
}
