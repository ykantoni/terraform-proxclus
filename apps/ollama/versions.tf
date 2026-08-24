terraform {
  required_version = ">= 1.8.0"

  required_providers {
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.1"
    }

    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.35"
    }
  }

  # Deliberately its own state file, separate from ../terraform.tfstate: this
  # stack has an independent apply/destroy lifecycle from the cluster it
  # deploys onto. See README's "Independence" section.
  backend "local" {
    path = "/home/yurick/terraform/state/ollama.tfstate"
  }
}
