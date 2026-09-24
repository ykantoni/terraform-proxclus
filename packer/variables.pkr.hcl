packer {
  required_plugins {
    proxmox = {
      version = ">= 1.2.0"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

variable "proxmox_url" {
  type    = string
  default = env("PROXMOX_URL") # e.g. https://192.168.1.15:8006/api2/json
}

variable "proxmox_username" {
  type    = string
  default = env("PROXMOX_USERNAME")
}

variable "proxmox_token" {
  type      = string
  default   = env("PROXMOX_TOKEN")
  sensitive = true
}

variable "proxmox_node" {
  type    = string
  default = "jupiter"
}

variable "datastore_id" {
  type    = string
  default = "sdc-storage"
}

variable "seed_template_vm_id" {
  description = "vm-templates/import-ubuntu-cloud-image.sh's output template"
  type        = number
  default     = 9099
}

variable "template_vm_id_common" {
  type    = number
  default = 9100
}

variable "template_vm_id_gpu" {
  type    = number
  default = 9101
}

variable "packer_ssh_private_key_file" {
  description = "Private key matching the public key baked into the seed template's own cloud-init (vm-templates/import-ubuntu-cloud-image.sh) -- unrelated to modules/rke2-config's Terraform-managed key, which only ever goes onto clones of the *finished* templates this file builds."
  type        = string
}
