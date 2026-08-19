output "cluster_name" {
  value = var.cluster_name
}

output "namespace" {
  value = var.namespace
}

output "superuser_secret" {
  description = "Secret CNPG generates holding the postgres superuser password. No superuser password is set or read by Terraform itself."
  value       = "${var.cluster_name}-superuser"
}

output "app_secret" {
  description = "Secret CNPG generates holding database_owner's password and a ready-to-use connection URI for database_name"
  value       = "${var.cluster_name}-app"
}
