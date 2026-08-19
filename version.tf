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

    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }

    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
  }

  backend "local" {
    path = "/home/yurick/terraform/state/terraform.tfstate"
  }
}