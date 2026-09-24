terraform {
  required_providers {
    proxmox = {
      source = "bpg/proxmox"
    }

    random = {
      source = "hashicorp/random"
    }

    tls = {
      source = "hashicorp/tls"
    }
  }
}
