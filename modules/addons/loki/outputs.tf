output "loki_version" {
  value = helm_release.loki.version
}

output "promtail_version" {
  value = helm_release.promtail.version
}

output "namespace" {
  value = var.namespace
}
