locals {
  cilium_values = {
    # Pod IPs come from the podCIDR that kube-controller-manager hands each node.
    ipam = {
      mode = "kubernetes"
    }

    # Talos deploys no kube-proxy when cni is cilium, so Cilium must take over
    # service routing. L2 announcements also require it.
    kubeProxyReplacement = true

    # KubePrism fronts the control plane on every node, so Cilium keeps talking
    # to the API server even while it is the thing providing cluster networking.
    k8sServiceHost = var.k8s_service_host
    k8sServicePort = var.k8s_service_port

    # Talos mounts cgroupv2 and bpffs itself; Cilium must not remount them.
    cgroup = {
      autoMount = {
        enabled = false
      }

      hostRoot = "/sys/fs/cgroup"
    }

    # Talos forbids workloads from loading kernel modules, so SYS_MODULE is
    # dropped from Cilium's default capability set.
    securityContext = {
      capabilities = {
        ciliumAgent = [
          "CHOWN",
          "KILL",
          "NET_ADMIN",
          "NET_RAW",
          "IPC_LOCK",
          "SYS_ADMIN",
          "SYS_RESOURCE",
          "DAC_OVERRIDE",
          "FOWNER",
          "SETGID",
          "SETUID",
        ]

        cleanCiliumState = [
          "NET_ADMIN",
          "SYS_ADMIN",
          "SYS_RESOURCE",
        ]
      }
    }

    # Answers ARP for LoadBalancer IPs so the pool is reachable on the LAN
    # without BGP.
    l2announcements = {
      enabled = true
    }

    # Leader election between announcing nodes is chatty against the API server.
    k8sClientRateLimit = {
      qps   = var.k8s_client_rate_limit.qps
      burst = var.k8s_client_rate_limit.burst
    }
  }
}

resource "helm_release" "cilium" {
  name      = "cilium"
  namespace = "kube-system"

  repository = "https://helm.cilium.io/"
  chart      = "cilium"
  version    = var.cilium_version

  wait    = true
  timeout = var.helm_timeout

  # Later entries win, so callers can override any of the defaults above.
  values = [
    yamlencode(local.cilium_values),
    yamlencode(var.cilium_extra_values),
  ]
}

# Ships as a chart rather than as plain manifests because the CRDs it depends on
# are registered by the Cilium operator, and so do not exist at plan time.
resource "helm_release" "cilium_lb_ipam" {
  depends_on = [
    helm_release.cilium
  ]

  name      = "cilium-lb-ipam"
  namespace = "kube-system"

  chart = "${path.module}/charts/cilium-lb-ipam"

  values = [
    yamlencode({
      pool = {
        name  = var.lb_ipam_pool_name
        start = var.lb_ipam_range.start
        stop  = var.lb_ipam_range.stop
      }

      l2Announcements = {
        interfaces             = var.l2_announcement_interfaces
        announceOnControlPlane = var.l2_announce_on_control_plane
      }
    })
  ]
}
