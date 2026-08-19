resource "kubernetes_namespace" "operator" {
  metadata {
    name = var.operator_namespace
  }
}

resource "kubernetes_namespace" "postgres" {
  metadata {
    name = var.namespace
  }
}

# Installs the CloudNativePG CRDs (Cluster, Pooler, Backup, ...) along with
# the operator Deployment. The operator watches every namespace by default,
# so one install here is enough regardless of which namespace the Cluster
# below ends up in.
resource "helm_release" "cnpg_operator" {
  depends_on = [
    kubernetes_namespace.operator
  ]

  name      = "cnpg"
  namespace = var.operator_namespace

  repository = "https://cloudnative-pg.github.io/charts"
  chart      = "cloudnative-pg"
  version    = var.operator_version

  wait    = true
  timeout = var.helm_timeout
}

locals {
  cluster_values = {
    name      = var.cluster_name
    instances = var.instances
    imageName = var.postgres_image

    storage = {
      size         = var.storage_size
      storageClass = var.storage_class
    }

    bootstrap = {
      initdb = {
        database = var.database_name
        owner    = var.database_owner
      }
    }
  }
}

# The Cluster resource ships as a tiny local chart rather than a
# kubernetes_manifest resource: kubernetes_manifest has to fetch the Cluster
# CRD's OpenAPI schema at plan time, which does not exist until
# helm_release.cnpg_operator has already applied — the classic "install a CRD
# and a CR of that kind in one apply" problem. A Helm release has no such
# plan-time schema lookup; it just applies the manifest at apply time, by
# which point the CRD is already registered because this release depends on
# the operator's. ../modules/addons/cilium uses the same trick for its
# CiliumLoadBalancerIPPool.
resource "helm_release" "postgres_cluster" {
  depends_on = [
    helm_release.cnpg_operator,
    kubernetes_namespace.postgres,
  ]

  name      = "${var.cluster_name}-cluster"
  namespace = var.namespace

  chart = "${path.module}/charts/postgres-cluster"

  wait    = true
  timeout = var.helm_timeout

  values = [
    yamlencode(local.cluster_values)
  ]
}
