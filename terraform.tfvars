proxmox_endpoint = "https://192.168.1.15:8006/"
proxmox_node     = "jupiter"

datastore_id = "sdc-storage"
bridge       = "vmbr0"

talos_iso = "local:iso/nocloud-amd64.iso"

cluster_name  = "proxclus"
talos_version = "v1.11.0"

gateway = "192.168.1.1"

nameservers = [
  "192.168.1.1",
  "1.1.1.1"
]

nodes = {
  cp1 = {
    vm_id = 9001
    name  = "cp1"
    ip    = "192.168.1.101"
    mac   = "BC:24:11:00:01:01"
    role  = "controlplane"

    cores  = 4
    memory = 4096
    disk   = 32
  }

  worker1 = {
    vm_id = 9002
    name  = "w1"
    ip    = "192.168.1.102"
    mac   = "BC:24:11:00:01:02"
    role  = "worker"
  }

  worker2 = {
    vm_id = 9003
    name  = "w2"
    ip    = "192.168.1.103"
    mac   = "BC:24:11:00:01:03"
    role  = "worker"
  }

  worker3 = {
    vm_id = 9004
    name  = "w3"
    ip    = "192.168.1.104"
    mac   = "BC:24:11:00:01:04"
    role  = "worker"
  }
}