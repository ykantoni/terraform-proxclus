variable "namespace" {
  description = "Namespace Loki and Promtail are installed into. Gets pod-security.kubernetes.io/enforce=privileged, since Promtail's DaemonSet needs hostPath mounts of /var/log/pods and /var/lib/docker/containers to read container logs."
  type        = string
  default     = "logging"
}

variable "storage_class" {
  description = "StorageClass Loki's PVC uses. The default (\"longhorn\") requires enable_longhorn = true; without it there is no StorageClass by that name and the PVC stays Pending, which times out this module's helm_release under wait=true."
  type        = string
  default     = "longhorn"
}

variable "loki_version" {
  description = "Loki Helm chart version. Check https://github.com/grafana/loki/releases (or `helm search repo grafana/loki --versions`) for the latest before relying on this default."
  type        = string
  default     = "7.3.0"
}

variable "loki_storage_size" {
  description = "Size of Loki's PVC, holding chunks and the TSDB index on the local filesystem"
  type        = string
  default     = "20Gi"
}

variable "loki_retention_period" {
  description = "How long Loki keeps logs before the compactor deletes them. Accepts Prometheus-style durations (e.g. \"31d\", \"744h\")."
  type        = string
  default     = "31d"
}

variable "promtail_version" {
  description = "Promtail Helm chart version. Check https://github.com/grafana/helm-charts/releases (or `helm search repo grafana/promtail --versions`) for the latest before relying on this default."
  type        = string
  default     = "6.17.1"
}

variable "enable_grafana_datasource" {
  description = "Create a ConfigMap labelled grafana_datasource=1 wiring Loki into Grafana automatically, via the k8s-sidecar kube-prometheus-stack's Grafana already runs. Harmless with enable_prometheus = false: it just sits unused until a Grafana with that sidecar exists."
  type        = bool
  default     = true
}

variable "loki_extra_values" {
  description = "Extra Loki Helm values merged over the defaults"
  type        = any
  default     = {}
}

variable "promtail_extra_values" {
  description = "Extra Promtail Helm values merged over the defaults"
  type        = any
  default     = {}
}

variable "helm_timeout" {
  description = "Seconds to wait for the Loki and Promtail releases to become ready"
  type        = number
  default     = 600
}
