proxmox_endpoint = "https://192.168.1.15:8006/"
proxmox_node     = "jupiter"

datastore_id = "sdc-storage"
bridge       = "vmbr0"

talos_iso           = "local:iso/nocloud-amd64.iso"
talos_boot_from_iso = true
talos_schematic_id  = "042ebed3c8675b0647bcc3854cfbb54acdf815c900d5bb463e04d7f93c1845fa"

cluster_name  = "proxclus"
talos_version = "v1.13.8"

gateway = "192.168.1.1"

nameservers = [
  "192.168.1.1",
  "1.1.1.1"
]

nodes = {
  cp1 = {
    vm_id  = 9001
    name   = "cp1"
    ip     = "192.168.1.201"
    mac    = "BC:24:11:00:01:01"
    role   = "controlplane"
    cores  = 2
    memory = 6144
    disk   = 32
  }

  worker1 = {
    vm_id  = 9002
    name   = "w1"
    ip     = "192.168.1.202"
    mac    = "BC:24:11:00:01:02"
    role   = "worker"
    cores  = 4
    memory = 8192
    disk   = 32
    pcigpu = "RTX5060Ti"
  }

  worker2 = {
    vm_id  = 9003
    name   = "w2"
    ip     = "192.168.1.203"
    mac    = "BC:24:11:00:01:03"
    role   = "worker"
    cores  = 4
    memory = 8192
    disk   = 32
  }

  worker3 = {
    vm_id  = 9004
    name   = "w3"
    ip     = "192.168.1.204"
    mac    = "BC:24:11:00:01:04"
    role   = "worker"
    cores  = 4
    memory = 8192
    disk   = 32
  }
}