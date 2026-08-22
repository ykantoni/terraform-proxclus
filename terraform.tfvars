proxmox_endpoint = "https://192.168.1.15:8006/"
proxmox_node     = "jupiter"

datastore_id = "sdc-storage"
bridge       = "vmbr0"

cluster_name     = "proxclus"
talos_version    = "v1.13.8"
controlplane_vip = "192.168.1.99"

cni            = "cilium"
cilium_version = "1.19.6"

enable_longhorn = true

# Off because cp1, worker2 and worker3 never reach Talos stage "running": the
# NVIDIA extensions in the shared image wait forever for a GPU those nodes do
# not have, so the "all nodes to finish boot sequence" check can never pass.
# Kubernetes itself is unaffected. Turn this back on once only GPU nodes carry
# the NVIDIA extensions.
wait_for_health = false

load_balancer_ip_range = {
  start = "192.168.1.60"
  stop  = "192.168.1.98"
}

gateway = "192.168.1.1"

nameservers = [
  "192.168.1.1",
  "1.1.1.1"
]

nodes = {
  cp1 = {
    vm_id  = 10000
    name   = "cp1"
    ip     = "192.168.1.201"
    mac    = "BC:24:11:00:01:01"
    role   = "controlplane"
    cores  = 2
    memory = 6144
    disk   = 32
  }

  worker1 = {
    vm_id  = 10001
    name   = "w1"
    ip     = "192.168.1.202"
    mac    = "BC:24:11:00:01:02"
    role   = "worker"
    cores  = 4
    memory = 12284
    disk   = 32
    pcigpu = "RTX5060Ti"
  }

  worker2 = {
    vm_id  = 10002
    name   = "w2"
    ip     = "192.168.1.203"
    mac    = "BC:24:11:00:01:03"
    role   = "worker"
    cores  = 4
    memory = 8192
    disk   = 32
  }

  worker3 = {
    vm_id  = 10003
    name   = "w3"
    ip     = "192.168.1.204"
    mac    = "BC:24:11:00:01:04"
    role   = "worker"
    cores  = 4
    memory = 8192
    disk   = 32
  }
}