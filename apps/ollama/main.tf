resource "kubernetes_namespace" "ollama" {
  metadata {
    name = var.namespace
  }
}

# Same idea ../postgres-cnpg/README.md already flags as worth doing: the
# platform's own "longhorn" StorageClass replicates 3x, which this cluster's
# small VM disks (32Gi default root filesystem) can't fit a many-GB model
# cache into across 3 separate nodes at once. Models are re-downloadable, so
# a single replica is enough redundancy for them, and needing only one node
# with room instead of three is what actually lets ollama_storage_size hold
# a real model on this hardware.
resource "kubernetes_storage_class_v1" "ollama_models" {
  metadata {
    name = "longhorn-single-replica"
  }

  storage_provisioner    = "driver.longhorn.io"
  reclaim_policy         = "Delete"
  volume_binding_mode    = "Immediate"
  allow_volume_expansion = true

  parameters = {
    numberOfReplicas    = "1"
    staleReplicaTimeout = "30"
    fromBackup          = ""
    fsType              = "ext4"
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
    kubernetes_namespace.ollama
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
