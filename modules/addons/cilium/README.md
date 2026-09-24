# Cluster Addons Module

Installs the cluster addons that RKE2 deliberately leaves out once
`cni: none`/`disable-kube-proxy: true` are set (see `modules/rke2-config`).

## Responsibilities

This module manages:

- Cilium, as both CNI and kube-proxy replacement
- a `CiliumLoadBalancerIPPool` for LoadBalancer services
- a `CiliumL2AnnouncementPolicy` that advertises those addresses over ARP

It expects a bootstrapped cluster whose RKE2 config already sets `cni: none`
and `disable-kube-proxy: true`, and it expects the `helm` provider to be
configured by the caller.

## RKE2/kube-vip specifics

The Helm values deviate from Cilium's defaults in a few ways:

- `ipam.mode: kubernetes`, so pod addresses come from the node podCIDR
- `cgroup.autoMount.enabled: false`, because Ubuntu (systemd) already mounts
  cgroupv2 itself, same as Talos did
- `SYS_MODULE` dropped from the agent capabilities — not strictly required
  under RKE2/Ubuntu the way it was under Talos, but harmless to keep, since
  nothing here needs Cilium to load kernel modules at runtime (that happens
  once, in `packer/`)
- `k8sServiceHost`/`k8sServicePort` point at the kube-vip-advertised
  control-plane VIP (`6443`) rather than a Service IP Cilium would have to
  route itself — the RKE2-world replacement for Talos's node-local KubePrism
  proxy. kube-vip is a `hostNetwork` pod using ARP, so it's reachable even
  while Cilium is still the thing bringing pod networking up.

## Load balancer addressing

`lb_ipam_range` must be free on the same subnet as the nodes. Announcement is
ARP based, so an address outside the node subnet cannot be reached; it is not
routed anywhere. Nothing else may hand out those addresses either, so keep the
range outside any DHCP scope and away from the control-plane VIP.

By default only non-control-plane nodes answer ARP, since a node that claims an
address without hosting a backend still attracts the traffic.

Services pick up an address automatically. To request a specific one, set
`spec.loadBalancerIP` or the `io.cilium/lb-ipam-ips` annotation.

## Hubble

`enable_hubble_ui = true` (the default) turns on Hubble Relay and Hubble UI,
giving a web dashboard of the CNI's live traffic: the service map, L3/L4/L7
flows, DNS, and policy verdicts. Flow visibility itself (`hubble.enabled`) is
already on by default in the chart; Relay aggregates every agent's flow feed,
and the UI is the dashboard that talks to Relay.

`hubble_ui_service_type` (default `LoadBalancer`) controls how the UI is
exposed, the same as `lb_ipam_range` covers the rest of the cluster's
LoadBalancer services — see the root README's "Networking" section.

## Inputs

- `lb_ipam_range` — object with `start` and `stop` (required)
- `cilium_version`
- `k8s_service_host`, `k8s_service_port`
- `lb_ipam_pool_name`
- `l2_announcement_interfaces`
- `l2_announce_on_control_plane`
- `k8s_client_rate_limit`
- `enable_hubble_ui`
- `hubble_ui_service_type`
- `cilium_extra_values`
- `helm_timeout`

## Outputs

- `cilium_version`
- `load_balancer_ip_range`

## Notes

`CiliumLoadBalancerIPPool` is served at `cilium.io/v2`, while
`CiliumL2AnnouncementPolicy` is still `cilium.io/v2alpha1` as of Cilium 1.19.
Both CRDs are registered by the Cilium operator rather than by the chart, which
is why the pool ships as a nested chart applied after the Cilium release instead
of as a Terraform-managed manifest.
