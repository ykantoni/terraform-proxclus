variable "kubeconfig_path" {
  description = "Path to a kubeconfig for the target cluster. A plain file on disk, not a reference into the platform's Terraform state or modules, which is what keeps this stack independent: it has a runtime dependency on the cluster being reachable, but no state or module dependency on how that cluster was built. Absolute by convention (see ../README.md) so this keeps working regardless of how deep apps/ nesting goes."
  type        = string
  default     = "/home/yurick/terraform/talos-proxmox/.kube/config"
}

variable "namespace" {
  description = "Namespace both Ollama and Open WebUI run in"
  type        = string
  default     = "ollama"
}

variable "ollama_chart_version" {
  description = "otwld/ollama-helm chart version. Check https://github.com/otwld/ollama-helm/releases for the latest before relying on this default."
  type        = string
  default     = "1.77.0"
}

variable "open_webui_chart_version" {
  description = "open-webui Helm chart version. Check https://github.com/open-webui/helm-charts/releases for the latest before relying on this default."
  type        = string
  default     = "16.0.0"
}

variable "gpu_enabled" {
  description = "Schedule Ollama onto a GPU node and request an nvidia.com/gpu resource. This is a *runtime* dependency, not a Terraform one (see ../README.md's \"Platform dependency\" section): the platform's ../../modules/addons/nvidia-device-plugin must already have labelled a node and created the RuntimeClass this stack points at, or the pod sits unschedulable. Set to false to run Ollama on CPU instead (slow, but works without a GPU node)."
  type        = bool
  default     = true
}

variable "gpu_node_selector" {
  description = "nodeSelector used to land Ollama's pod on a GPU node, when gpu_enabled. Must match the label ../../modules/addons/nvidia-device-plugin applies (its gpu_node_label, \"nvidia.com/gpu.present\" by default)."
  type        = map(string)
  default = {
    "nvidia.com/gpu.present" = "true"
  }
}

variable "runtime_class_name" {
  description = "RuntimeClass Ollama's pod requests, when gpu_enabled. Must match ../../modules/addons/nvidia-device-plugin's runtime_class_name (\"nvidia\" by default) — that module creates the RuntimeClass; this stack only references it by name."
  type        = string
  default     = "nvidia"
}

variable "gpu_count" {
  description = "Number of GPUs Ollama's pod requests, when gpu_enabled"
  type        = number
  default     = 1
}

variable "models_to_pull" {
  description = "Models Ollama pulls automatically on container startup (e.g. [\"llama3.1:8b\"]). Leave empty (the default) to pick models entirely from Open WebUI's own model manager after deploying — that's the primary way this stack is meant to be used, so nothing here needs to change to try a different model."
  type        = list(string)
  default     = []
}

variable "ollama_storage_size" {
  description = "Size of the PVC Ollama stores pulled models on. Keep this comfortably under a single node's free disk: this cluster's VM disks default to 32Gi total (var.nodes[*].disk in the root module) for the whole root filesystem, not just Longhorn, and ollama_storage_class replicates just once, so the entire requested size has to fit on whichever one node Longhorn schedules it to. Raise var.nodes[*].disk on the GPU node in the root module first if you need room for bigger models."
  type        = string
  default     = "15Gi"
}

variable "ollama_storage_class" {
  description = "StorageClass for Ollama's model PVC. Empty string (the default) uses this stack's own kubernetes_storage_class_v1.ollama_models (\"ollama-local\"), a no-provisioner StorageClass bound to kubernetes_persistent_volume_v1.ollama_models — a \"local\" PV pointed at ollama_storage_path on the GPU node itself. Pulled models are re-downloadable cache, not data worth replicating (or worth Longhorn's engine overhead on top of the same node's disk), so this bypasses Longhorn entirely instead of just cutting its replica count. Set to \"longhorn\" (or \"longhorn-single-replica\", if you recreate that class) to go back to Longhorn-backed storage."
  type        = string
  default     = ""
}

variable "ollama_storage_path" {
  description = "Absolute directory path on the GPU node's own filesystem (matching gpu_node_selector) backing kubernetes_persistent_volume_v1.ollama_models. \"local\" PVs are statically provisioned: this directory must already exist on that node, be writable, and persist across reboots before helm_release.ollama's PVC can bind — Terraform does not create it. On Talos that typically means it also needs to be a path the kubelet's mount namespace exposes to pods, via an extraMounts patch on that node's machine config (see modules/addons/longhorn/patches/longhorn-mounts.patch.yaml for the pattern this cluster already uses for the same problem)."
  type        = string
  default     = "/var/lib/ollama-models"
}

variable "ollama_service_type" {
  description = "Kubernetes Service type Ollama's own API (port 11434) is exposed as. LoadBalancer (the default) gets an address from Cilium's load_balancer_ip_range, since this cluster runs no ingress controller; see the root README's \"Networking\" section. Open WebUI reaches Ollama via ClusterIP DNS regardless of this setting (see local.ollama_service_fqdn), so this only matters for clients outside the cluster hitting Ollama's API directly."
  type        = string
  default     = "LoadBalancer"
}

variable "ollama_extra_values" {
  description = "Extra ollama-helm Helm values merged over the defaults"
  type        = any
  default     = {}
}

variable "webui_service_type" {
  description = "Kubernetes Service type Open WebUI is exposed as. LoadBalancer (the default) gets an address from Cilium's load_balancer_ip_range, since this cluster runs no ingress controller; see the root README's \"Networking\" section."
  type        = string
  default     = "LoadBalancer"
}

variable "webui_storage_size" {
  description = "Size of the PVC Open WebUI stores its own state on (chat history, accounts, uploaded files)"
  type        = string
  default     = "2Gi"
}

variable "webui_storage_class" {
  description = "StorageClass for Open WebUI's own PVC"
  type        = string
  default     = "longhorn"
}

variable "open_webui_extra_values" {
  description = "Extra open-webui Helm values merged over the defaults"
  type        = any
  default     = {}
}

variable "helm_timeout" {
  description = "Seconds to wait for each Helm release to become ready. Ollama's image is large and, if models_to_pull is non-empty, the container also blocks startup on the model download, so this may need raising for a slow link or a big model."
  type        = number
  default     = 300
}
