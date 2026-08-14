terraform {
  required_version = ">= 1.8.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.111.1"
    }

    talos = {
      source = "siderolabs/talos"
    }
  }

  backend "local" {
    path = "/root/terraform/state/terraform.tfstate"
  }  
}