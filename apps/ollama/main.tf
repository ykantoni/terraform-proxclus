resource "kubernetes_namespace" "ollama" {
  metadata {
    name = var.namespace
  }
}

# Same idea ../postgres-cnpg/README.md already flags as worth doing: the
# platform's own "longhorn" StorageClass replicates 3x, which this cluster's
# small VM disks (32Gi default root filesystem) can't fit a many-GB model
# cache into across 3 separate nodes at once — and even single-replica
# Longhorn still pays for an iSCSI target/engine pod on top of the same
# node's disk. Models are re-downloadable, so neither replication nor
# Longhorn's engine overhead buys anything here: a plain directory on the
# GPU node's own filesystem, statically provisioned as a "local" PV, is both
# simpler and lets ollama_storage_size use that disk directly.
resource "kubernetes_storage_class_v1" "ollama_models" {
  metadata {
    name = "ollama-local"
  }

  storage_provisioner = "kubernetes.io/no-provisioner"
  reclaim_policy      = "Retain"
  # "local" volumes bind only after a pod that needs them is scheduled — the
  # scheduler is what actually evaluates the PV's node_affinity below. With
  # Immediate binding (Longhorn's mode) the PVC could bind before the pod
  # exists, ignoring the node the volume is pinned to.
  volume_binding_mode    = "WaitForFirstConsumer"
  allow_volume_expansion = false
}

# Statically provisioned: "local" volumes have no dynamic provisioner, so
# this PV — and the directory it points at on the node — has to exist before
# the chart's PVC can bind to it. Create ollama_storage_path on that node
# (matching gpu_node_selector) first; on Talos that directory needs to be
# one the kubelet's mount namespace already exposes to pods (see
# modules/addons/longhorn/patches for the extraMounts pattern this cluster
# uses for the same problem), or an extraMounts patch for it added the same
# way.
resource "kubernetes_persistent_volume_v1" "ollama_models" {
  metadata {
    name = "ollama-models"
  }

  spec {
    capacity = {
      storage = var.ollama_storage_size
    }
    access_modes                     = ["ReadWriteOnce"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = kubernetes_storage_class_v1.ollama_models.metadata[0].name

    persistent_volume_source {
      local {
        path = var.ollama_storage_path
      }
    }

    # Pins this PV to whichever node gpu_node_selector's labels match — the
    # same node Ollama's pod itself targets — since a "local" volume's data
    # only exists on that one node's disk. A pod claiming this PV is
    # scheduled onto that node regardless of the pod's own nodeSelector, so
    # this holds even when gpu_enabled = false.
    node_affinity {
      required {
        node_selector_term {
          dynamic "match_expressions" {
            for_each = var.gpu_node_selector
            content {
              key      = match_expressions.key
              operator = "In"
              values   = [match_expressions.value]
            }
          }
        }
      }
    }
  }
}

locals {
  ollama_storage_class = var.ollama_storage_class != "" ? var.ollama_storage_class : kubernetes_storage_class_v1.ollama_models.metadata[0].name

  ollama_values = merge(
    {
      ollama = {
        gpu = {
          enabled = var.gpu_enabled
          type    = "nvidia"
          number  = var.gpu_count
        }

        models = {
          pull = var.models_to_pull
        }
      }

      persistentVolume = {
        enabled      = true
        size         = var.ollama_storage_size
        storageClass = local.ollama_storage_class
      }
    },
    # An empty runtimeClassName/nodeSelector is how the chart already spells
    # "no GPU targeting", so gpu_enabled=false needs nothing more than that.
    var.gpu_enabled ? {
      runtimeClassName = var.runtime_class_name
      nodeSelector     = var.gpu_node_selector
      } : {
      runtimeClassName = ""
      nodeSelector     = {}
    }
  )
}

resource "helm_release" "ollama" {
  depends_on = [
    kubernetes_namespace.ollama,
    kubernetes_persistent_volume_v1.ollama_models,
  ]

  name      = "ollama"
  namespace = var.namespace

  repository = "https://otwld.github.io/ollama-helm/"
  chart      = "ollama"
  version    = var.ollama_chart_version

  wait    = true
  timeout = var.helm_timeout

  # Later entries win, so callers can override any of the defaults above.
  values = [
    yamlencode(local.ollama_values),
    yamlencode(var.ollama_extra_values),
  ]
}

locals {
  # helm_release.ollama's release name equals the chart name ("ollama"), so
  # the chart's fullname helper collapses to just "ollama" instead of
  # "ollama-ollama" — that's the Service name Open WebUI is pointed at here.
  ollama_service_fqdn = "${helm_release.ollama.name}.${var.namespace}.svc.cluster.local"

  open_webui_values = {
    # Open WebUI bundles its own Ollama subchart by default; this stack
    # brings its own release instead (the one above, with GPU scheduling),
    # so the bundled one is disabled and pointed at that release's Service.
    ollama = {
      enabled = false
    }

    ollamaUrls = [
      "http://${local.ollama_service_fqdn}:11434"
    ]

    service = {
      type = var.webui_service_type
    }

    persistence = {
      enabled      = true
      size         = var.webui_storage_size
      storageClass = var.webui_storage_class
    }

    # A single Open WebUI replica needs no external state for websockets;
    # skipping Redis here avoids standing up a dependency this stack would
    # otherwise have to manage the lifecycle of for no benefit at replica=1.
    websocket = {
      manager = ""
      redis = {
        enabled = false
      }
    }
  }
}

resource "helm_release" "open_webui" {
  depends_on = [
    helm_release.ollama,
  ]

  name      = "open-webui"
  namespace = var.namespace

  repository = "https://helm.openwebui.com/"
  chart      = "open-webui"
  version    = var.open_webui_chart_version

  wait    = true
  timeout = var.helm_timeout

  # Later entries win, so callers can override any of the defaults above.
  values = [
    yamlencode(local.open_webui_values),
    yamlencode(var.open_webui_extra_values),
  ]
}
