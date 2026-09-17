# Managed by the kubernetes provider rather than Helm, for the same reason as
# modules/addons/prometheus's and modules/addons/longhorn's namespaces: Helm
# records a release's Secret in its target namespace before applying any of
# that release's own manifests, so a chart cannot create the namespace it
# installs into.
resource "kubernetes_namespace" "logging" {
  metadata {
    name = var.namespace

    labels = {
      # Promtail's DaemonSet reads host-level container logs by running
      # hostPath mounts of /var/log/pods and /var/lib/docker/containers, both
      # forbidden under the restricted Pod Security Standard. Same shape of
      # problem as modules/addons/prometheus's node-exporter, solved the same
      # way: label the whole namespace privileged rather than trying to scope
      # it to just Promtail's pods.
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

locals {
  loki_values = {
    loki = {
      auth_enabled = false

      # Single tenant, single replica: there is nothing to replicate to.
      commonConfig = {
        replication_factor = 1
      }

      # No object storage in a homelab; chunks and the index live on the PVC
      # singleBinary.persistence provisions below.
      storage = {
        type = "filesystem"
      }

      schemaConfig = {
        configs = [
          {
            from         = "2024-01-01"
            store        = "tsdb"
            object_store = "filesystem"
            schema       = "v13"
            index = {
              prefix = "index_"
              period = "24h"
            }
          }
        ]
      }

      # TSDB retention is enforced by the compactor, not by tableManager
      # (that's the older chunk-store mechanism this schema doesn't use).
      compactor = {
        retention_enabled    = true
        delete_request_store = "filesystem"
      }

      limits_config = {
        retention_period = var.loki_retention_period
      }
    }

    # SimpleScalable (the chart default) splits Loki into separate
    # read/write/backend deployments behind a gateway, sized for real
    # multi-node query load. A homelab's log volume doesn't need that.
    deploymentMode = "SingleBinary"

    singleBinary = {
      replicas = 1

      persistence = {
        enabled      = true
        size         = var.loki_storage_size
        storageClass = var.storage_class
      }
    }

    # Distributed-mode component replicas; irrelevant under SingleBinary,
    # forced to 0 so the chart doesn't also render them.
    read = {
      replicas = 0
    }

    write = {
      replicas = 0
    }

    backend = {
      replicas = 0
    }

    # No object storage backend (storage.type is filesystem), so there is
    # nothing for minio to sit in front of.
    minio = {
      enabled = false
    }

    # The nginx gateway exists to fan a single entrypoint out across
    # distributed-mode's several read/write/backend services. SingleBinary
    # already exposes one service for both pushing and querying, so
    # Promtail and Grafana talk to it directly.
    gateway = {
      enabled = false
    }

    # The canary and its test Job push through the gateway to verify it;
    # skip both since the gateway is disabled.
    test = {
      enabled = false
    }

    lokiCanary = {
      enabled = false
    }

    # Memcached-backed chunk/result caching exists for distributed-mode's
    # query load; skip it for a single-binary, single-tenant install.
    chunksCache = {
      enabled = false
    }

    resultsCache = {
      enabled = false
    }

    monitoring = {
      # Deprecated, relies on the Grafana Agent Operator this cluster
      # doesn't run.
      selfMonitoring = {
        enabled = false
      }

      lokiCanary = {
        enabled = false
      }

      # Only takes effect once the ServiceMonitor CRD exists (installed by
      # module.prometheus's kube-prometheus-stack); harmless otherwise since
      # Helm just fails to render that one template.
      serviceMonitor = {
        enabled = true
      }
    }
  }

  promtail_values = {
    config = {
      # The chart's own default points at a "loki-gateway" Service that
      # doesn't exist with gateway.enabled = false; point it at Loki's own
      # Service (named "loki" for a release also named "loki") instead.
      clients = [
        {
          url = "http://loki.${var.namespace}.svc.cluster.local:3100/loki/api/v1/push"
        }
      ]
    }

    # Same caveat as loki_values.monitoring.serviceMonitor above.
    serviceMonitor = {
      enabled = true
    }
  }
}

resource "helm_release" "loki" {
  depends_on = [
    kubernetes_namespace.logging,
  ]

  name      = "loki"
  namespace = var.namespace

  repository = "https://grafana.github.io/helm-charts"
  chart      = "loki"
  version    = var.loki_version

  # Loki's PVC can take a while to actually attach (Longhorn replica
  # scheduling isn't instant), so a wait timeout here is plausible on a
  # tight cluster. Plain `helm install` refuses to reuse a release name left
  # behind in "failed" status by a timed-out create; upgrade_install runs
  # `helm upgrade --install` instead, which can proceed past that.
  upgrade_install = true

  wait    = true
  timeout = var.helm_timeout

  # Later entries win, so callers can override any of the defaults above.
  values = [
    yamlencode(local.loki_values),
    yamlencode(var.loki_extra_values),
  ]
}

resource "helm_release" "promtail" {
  depends_on = [
    helm_release.loki,
  ]

  name      = "promtail"
  namespace = var.namespace

  repository = "https://grafana.github.io/helm-charts"
  chart      = "promtail"
  version    = var.promtail_version

  # See helm_release.loki's upgrade_install comment above.
  upgrade_install = true

  wait    = true
  timeout = var.helm_timeout

  values = [
    yamlencode(local.promtail_values),
    yamlencode(var.promtail_extra_values),
  ]
}

# kube-prometheus-stack's Grafana runs a k8s-sidecar (grafana-sc-datasources)
# that watches every namespace for ConfigMaps labelled grafana_datasource and
# provisions them automatically, so wiring Loki in needs nothing inside
# modules/addons/prometheus. Harmless with enable_prometheus = false: the
# ConfigMap just sits unused until a Grafana with that sidecar exists.
resource "kubernetes_config_map" "grafana_datasource" {
  count = var.enable_grafana_datasource ? 1 : 0

  metadata {
    name      = "loki-grafana-datasource"
    namespace = var.namespace

    labels = {
      grafana_datasource = "1"
    }
  }

  data = {
    "loki-datasource.yaml" = yamlencode({
      apiVersion = 1
      datasources = [
        {
          name   = "Loki"
          type   = "loki"
          access = "proxy"
          url    = "http://loki.${var.namespace}.svc.cluster.local:3100"
          jsonData = {
            maxLines = 1000
          }
        }
      ]
    })
  }
}
