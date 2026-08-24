output "namespace" {
  value = var.namespace
}

output "ollama_internal_endpoint" {
  description = "In-cluster address of the Ollama API (ClusterIP; not exposed outside the cluster)"
  value       = "${local.ollama_service_fqdn}:11434"
}

output "webui_service_type" {
  description = "Kubernetes Service type Open WebUI is exposed as. When LoadBalancer, find the assigned address with: kubectl -n <namespace> get svc open-webui"
  value       = var.webui_service_type
}
