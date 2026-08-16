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

  cluster_endpoint = "https://${local.bootstrap_node.ip}:6443"
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

  config_patches = [
    yamlencode({
      machine = {
        install = {
          disk = "/dev/sda"

          image = "factory.talos.dev/metal-installer/${var.talos_schematic_id}:${var.talos_version}"
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
  ]
}
resource "talos_machine_configuration_apply" "node" {
  for_each = var.nodes

  node     = each.value.ip
  endpoint = each.value.ip

  client_configuration = talos_machine_secrets.this.client_configuration

  machine_configuration_input = data.talos_machine_configuration.node[each.key].machine_configuration
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

