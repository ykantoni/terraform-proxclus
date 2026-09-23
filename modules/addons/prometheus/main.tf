# Managed by the kubernetes provider rather than Helm, for the same reason as
# modules/addons/longhorn's namespace: Helm records a release's Secret in its
# target namespace before applying any of that release's own manifests, so a
# chart cannot create the namespace it installs into, and create_namespace=true
# creates a plain namespace outside any release's ownership, which a templated
# Namespace resource would then conflict with on install.
resource "kubernetes_namespace" "monitoring" {
  metadata {
    name = var.namespace

    labels = {
      # prometheus-node-exporter's DaemonSet (bundled with this chart) needs
      # hostNetwork, hostPID and hostPath mounts of /proc and /sys to read
      # host-level metrics, all of which the restricted Pod Security Standard
      # forbids.
      "pod-security.kubernetes.io/enforce" = "privileged"
      "pod-security.kubernetes.io/audit"   = "privileged"
      "pod-security.kubernetes.io/warn"    = "privileged"
    }
  }
}

locals {
  kube_prometheus_stack_values = {
    # Unlike kube-scheduler and kube-controller-manager (which Talos runs as
    # labelled static pods, so the chart's default Service-selector-based
    # Endpoints already populate correctly), etcd runs as a host-level
    # process with no matching pod, so its Endpoints stay permanently empty.
    # "If your etcd is not deployed as a pod, specify IPs it can be found
    # on" is the chart's own values.yaml comment for exactly this.
    kubeEtcd = {
      endpoints = var.controlplane_ips
    }

    prometheus = {
      prometheusSpec = {
        retention = var.prometheus_retention

        # nil (the chart's own default) restricts discovery to
        # ServiceMonitors/PodMonitors/PrometheusRules carrying this Helm
        # release's own label, which exists for multi-tenant clusters where
        # each Prometheus should only scrape what it's explicitly told to.
        # This is a single-tenant homelab cluster, so false makes Prometheus
        # pick up any ServiceMonitor/PodMonitor/PrometheusRule in any
        # namespace automatically, with no release label for other addons'
        # charts to remember to set.
        serviceMonitorSelectorNilUsesHelmValues = false
        podMonitorSelectorNilUsesHelmValues     = false
        ruleSelectorNilUsesHelmValues           = false

        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = var.storage_class
              accessModes      = ["ReadWriteOnce"]
              resources = {
                requests = {
                  storage = var.prometheus_storage_size
                }
              }
            }
          }
        }
      }

      service = {
        type = var.prometheus_service_type
      }
    }

    alertmanager = {
      alertmanagerSpec = {
        storage = {
          volumeClaimTemplate = {
            spec = {
              storageClassName = var.storage_class
              accessModes      = ["ReadWriteOnce"]
              resources = {
                requests = {
                  storage = var.alertmanager_storage_size
                }
              }
            }
          }
        }
      }
    }

    grafana = {
      enabled       = var.enable_grafana
      adminPassword = var.grafana_admin_password

      # The dashboards sidecar already scans every namespace by the chart's
      # own default; the datasources sidecar's default is the release
      # namespace only, so any addon (e.g. modules/addons/loki) that ships a
      # data source ConfigMap from its own namespace would otherwise go
      # unnoticed.
      sidecar = {
        datasources = {
          searchNamespace = "ALL"
        }
      }

      service = {
        type = var.grafana_service_type
      }

      # Grafana runs as a Deployment, not a StatefulSet, but its PVC is still
      # ReadWriteOnce. The chart's default RollingUpdate strategy tries to
      # start the replacement pod before killing the old one; with only one
      # replica and an RWO volume, the new pod can never attach it (Multi-
      # Attach error) and the rollout deadlocks forever. Recreate kills the
      # old pod first, so the new one can actually mount the volume.
      deploymentStrategy = {
        type = "Recreate"
      }

      # Grafana's container runs with readOnlyRootFilesystem: true. Its
      # background plugin-update pass (on by default in this chart's app
      # version) still tries to self-update bundled plugins under
      # /usr/share/grafana/data/plugins-bundled on every startup — including
      # ones this cluster actually needs, like prometheus and loki. It kills
      # the running plugin process first, then fails to write the
      # replacement ("read-only file system"), permanently breaking that
      # plugin for the pod's lifetime. A writable emptyDir at just this path
      # lets the update pass actually succeed, without loosening
      # readOnlyRootFilesystem anywhere else.
      extraEmptyDirMounts = [
        {
          name      = "plugins-bundled"
          mountPath = "/usr/share/grafana/data/plugins-bundled"
        }
      ]

      persistence = {
        enabled          = true
        storageClassName = var.storage_class
        size             = var.grafana_storage_size
      }
    }
  }
}

resource "helm_release" "kube_prometheus_stack" {
  depends_on = [
    kubernetes_namespace.monitoring,
  ]

  name      = "kube-prometheus-stack"
  namespace = var.namespace

  repository = "https://prometheus-community.github.io/helm-charts"
  chart      = "kube-prometheus-stack"
  version    = var.kube_prometheus_stack_version

  wait    = true
  timeout = var.helm_timeout

  # Later entries win, so callers can override any of the defaults above.
  values = [
    yamlencode(local.kube_prometheus_stack_values),
    yamlencode(var.kube_prometheus_stack_extra_values),
  ]
}
