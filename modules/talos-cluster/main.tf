locals {
  controlplanes = {
    for key, node in var.nodes :
    key => node
    if node.role == "controlplane"
  }

  workers = {
    for key, node in var.nodes :
    key => node
    if node.role == "worker"
  }

  controlplane_ips = [
    for node in values(local.controlplanes) :
    node.ip
  ]

  bootstrap_node = values(local.controlplanes)[0]

  cluster_endpoint = "https://${var.controlplane_vip}:6443"

  controlplane_patches = concat(
    [
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "Layer2VIPConfig"
        name       = var.controlplane_vip
        link       = "eth0"
      })
    ],
    var.cni == "cilium" ? [
      yamlencode({
        cluster = {
          network = {
            cni = {
              name = "none"
            }
          }

          proxy = {
            disabled = true
          }
        }
      })
    ] : []
  )
}

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_client_configuration" "this" {
  cluster_name = var.cluster_name

  client_configuration = talos_machine_secrets.this.client_configuration

  endpoints = local.controlplane_ips

  nodes = [
    for node in values(var.nodes) :
    node.ip
  ]
}

data "talos_machine_configuration" "node" {

  for_each = var.nodes

  cluster_name     = var.cluster_name
  cluster_endpoint = local.cluster_endpoint

  machine_type = each.value.role == "controlplane" ? "controlplane" : "worker"

  machine_secrets = talos_machine_secrets.this.machine_secrets

  talos_version = var.talos_version

  config_patches = concat(
    [
      yamlencode({
        machine = {
          install = {
            disk = "/dev/sda"

            image = "factory.talos.dev/metal-installer/${var.talos_schematic_id}:${var.talos_version}"
          }

          features = {
            kubePrism = {
              enabled = true
              port    = var.kube_prism_port
            }
          }

          network = {

            interfaces = [
              {
                interface = "eth0"

                addresses = [
                  "${each.value.ip}/${each.value.cidr}"
                ]

                routes = [
                  {
                    network = "0.0.0.0/0"
                    gateway = var.gateway
                  }
                ]
              }
            ]

            nameservers = var.nameservers
          }
        }
      })
    ],
    var.config_patches,
    each.value.role == "controlplane" ? concat(local.controlplane_patches, var.controlplane_config_patches) : var.worker_config_patches
  )
}
resource "talos_machine_configuration_apply" "node" {
  for_each = var.nodes

  node     = each.value.ip
  endpoint = each.value.ip

  client_configuration = talos_machine_secrets.this.client_configuration

  machine_configuration_input = data.talos_machine_configuration.node[each.key].machine_configuration
  config_patches = concat(
    try(each.value.pcigpu, null) != null ? [file("${path.module}/patches/nvidia-modules.patch.yaml")] : []
  )
}

resource "talos_machine_bootstrap" "this" {
  depends_on = [
    talos_machine_configuration_apply.node
  ]

  node     = local.bootstrap_node.ip
  endpoint = local.bootstrap_node.ip

  client_configuration = talos_machine_secrets.this.client_configuration
}
resource "talos_cluster_kubeconfig" "this" {
  depends_on = [
    talos_machine_bootstrap.this
  ]

  node     = local.bootstrap_node.ip
  endpoint = local.bootstrap_node.ip

  client_configuration = talos_machine_secrets.this.client_configuration
}

# Bootstrapping only means Talos accepted the call. Anything that talks to
# Kubernetes has to wait for the nodes to actually come up, which is what this
# gates on.
data "talos_cluster_health" "this" {
  count = var.wait_for_health ? 1 : 0

  depends_on = [
    talos_machine_configuration_apply.node,
    talos_machine_bootstrap.this,
  ]

  client_configuration = talos_machine_secrets.this.client_configuration

  endpoints = local.controlplane_ips

  control_plane_nodes = local.controlplane_ips

  worker_nodes = [
    for node in values(local.workers) :
    node.ip
  ]

  # Keep the Kubernetes checks on: they are the only ones that prove the API
  # server answers requests, which is what Helm needs. Talos itself skips the
  # checks that cannot pass without a CNI — node readiness and coredns — once
  # the machine config says cni: none, and the kube-proxy check skips when the
  # DaemonSet is absent. Skipping them here would leave only Talos-level checks,
  # none of which touch Kubernetes at all.
  skip_kubernetes_checks = false
}

