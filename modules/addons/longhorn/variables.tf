variable "longhorn_version" {
  description = "Longhorn Helm chart version"
  type        = string
  default     = "1.8.1"
}

variable "namespace" {
  description = "Namespace Longhorn is installed into. Gets pod-security.kubernetes.io/enforce=privileged, since Longhorn's engine and CSI plugin need privileged access to host block devices."
  type        = string
  default     = "longhorn-system"
}

variable "data_path" {
  description = "Path on each node's disk where Longhorn stores replica data. Must match the /var/lib/longhorn kubelet bind mount in modules/addons/longhorn/patches, which is static YAML and does not read this variable."
  type        = string
  default     = "/var/lib/longhorn"
}

variable "replica_count" {
  description = "Default number of replicas Longhorn keeps for each volume, and the default StorageClass's replica count"
  type        = number
  default     = 3
}

variable "storage_over_provisioning_percentage" {
  description = "How far Longhorn can reserve space for volumes beyond a disk's raw capacity, since replicas are thin-provisioned and most workloads use far less than their requested size. 100 (the chart's own default) reserves each volume's full requested size against every disk's raw capacity with zero slack, so nominal reservations alone can exhaust a small cluster's scheduling budget long before any disk is actually full — worse, on nodes this small, once Longhorn's own storage-reserved-percentage-for-default-disk carve-out (30% of each disk, off limits regardless of this setting) is subtracted first. Real free space is still protected independently by storage-minimal-available-percentage."
  type        = number
  default     = 300
}

variable "longhorn_extra_values" {
  description = "Extra Longhorn Helm values merged over the defaults"
  type        = any
  default     = {}
}

variable "helm_timeout" {
  description = "Seconds to wait for the Longhorn release to become ready"
  type        = number
  default     = 600
}
