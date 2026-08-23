variable "gpu_node_ips" {
  description = "IPs of nodes that have a GPU mapped (pcigpu set), from the root module's var.nodes. Used to find each node's Kubernetes Node object and label it, so the device plugin's DaemonSet only schedules onto nodes that actually have a GPU."
  type        = list(string)

  validation {
    condition     = length(var.gpu_node_ips) > 0
    error_message = "gpu_node_ips must not be empty; the caller should give this module a count of 0 instead of instantiating it with no GPU nodes."
  }
}

variable "nvidia_device_plugin_version" {
  description = "nvidia-device-plugin Helm chart version"
  type        = string
  default     = "0.20.0"
}

variable "namespace" {
  description = "Namespace the device plugin's DaemonSet is installed into"
  type        = string
  default     = "kube-system"
}

variable "runtime_class_name" {
  description = "Name of the Kubernetes RuntimeClass created for GPU workloads, and the containerd runtime handler it points at. Must match the runtime name the siderolabs/nvidia-container-toolkit-production system extension registers with containerd, which is \"nvidia\"."
  type        = string
  default     = "nvidia"
}

variable "gpu_node_label" {
  description = "Label key applied to each Kubernetes Node in gpu_node_ips, and used as the device plugin DaemonSet's nodeSelector so it never schedules onto a node without a GPU (where nvidia-smi/NVML and the \"nvidia\" containerd runtime don't exist, and the pod would otherwise sit stuck)."
  type        = string
  default     = "nvidia.com/gpu.present"
}

variable "nvidia_device_plugin_extra_values" {
  description = "Extra nvidia-device-plugin Helm values merged over the defaults"
  type        = any
  default     = {}
}

variable "helm_timeout" {
  description = "Seconds to wait for the nvidia-device-plugin release to become ready"
  type        = number
  default     = 300
}
