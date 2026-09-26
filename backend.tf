terraform {
  backend "local" {
    path = "/var/lib/terraform/talos-proxmox/terraform.tfstate"
    # path = "/home/yurick/terraform/state/terraform.tfstate"
  }
}