variable "kubeconfig_path" {
  description = "Path to a kubeconfig for the target cluster. A plain file on disk, not a reference into the platform's Terraform state or modules, which is what keeps this stack independent: it has a runtime dependency on the cluster being reachable, but no state or module dependency on how that cluster was built. Absolute by convention (see ../README.md) so this keeps working regardless of how deep apps/ nesting goes."
  type        = string
  default     = "/home/yurick/terraform/talos-proxmox/.kube/config"
}

variable "operator_namespace" {
  description = "Namespace the CloudNativePG operator itself runs in"
  type        = string
  default     = "cnpg-system"
}

variable "operator_version" {
  description = "cloudnative-pg Helm chart version. Check https://github.com/cloudnative-pg/charts/releases for the latest before relying on this default."
  type        = string
  default     = "0.23.2"
}

variable "namespace" {
  description = "Namespace the Postgres Cluster (primary + standbys) runs in"
  type        = string
  default     = "postgres"
}

variable "cluster_name" {
  description = "Name of the CNPG Cluster resource, and the prefix CNPG uses for the Secrets it generates"
  type        = string
  default     = "postgres"
}

variable "postgres_image" {
  description = "Postgres container image every instance runs. Check https://github.com/cloudnative-pg/postgres-containers/releases for the latest before relying on this default."
  type        = string
  default     = "ghcr.io/cloudnative-pg/postgresql:17.2"
}

variable "instances" {
  description = "Total Postgres instances: 1 primary plus (instances - 1) streaming-replication standbys, automatically kept in sync by the operator"
  type        = number
  default     = 2

  validation {
    condition     = var.instances >= 2
    error_message = "instances must be at least 2 for there to be a standby."
  }
}

variable "storage_size" {
  description = "Size of each instance's own PVC"
  type        = string
  default     = "10Gi"
}

variable "storage_class" {
  description = "StorageClass each instance's PVC uses. The default (\"longhorn\") gives every instance's data 3x Longhorn-level replication on top of Postgres's own streaming replication between instances; see README's \"Storage\" section for why that double redundancy may be worth trimming."
  type        = string
  default     = "longhorn"
}

variable "database_name" {
  description = "Application database CNPG creates via initdb on the primary"
  type        = string
  default     = "app"
}

variable "database_owner" {
  description = "Owner role CNPG creates for database_name. CNPG generates a password for it and publishes both in the <cluster_name>-app Secret; nothing here handles credentials directly."
  type        = string
  default     = "app"
}

variable "helm_timeout" {
  description = "Seconds to wait for each Helm release to become ready"
  type        = number
  default     = 300
}
