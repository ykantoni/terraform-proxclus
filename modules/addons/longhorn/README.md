# Longhorn Addon Module

Installs Longhorn as the cluster's default CSI provider, so PVCs provision
dynamically without naming a `storageClassName`.

## Responsibilities

This module manages:

- the `longhorn-system` namespace, labelled
  `pod-security.kubernetes.io/enforce=privileged`
- the Longhorn Helm release, with its `longhorn` StorageClass set as the
  cluster default

It expects a bootstrapped cluster and the `helm` provider to be configured by
the caller. It touches no VM/node provisioning: a normal Ubuntu kubelet
already sees any host path with no machine-config-equivalent step needed
(unlike Talos, which needed a kubelet `extraMounts` patch to expose
`/var/lib/longhorn` at all — see git history for that mechanism, dropped once
this cluster moved off Talos).

## What Longhorn needs from the node

- `open-iscsi` and `util-linux`/`nfs-common`, installed and `iscsid` enabled,
  so the block-device tooling Longhorn's engine shells out to exists on the
  host — baked into every node's image in `packer/`, the RKE2-world
  replacement for Talos's `siderolabs/iscsi-tools`/`siderolabs/util-linux-tools`
  system extensions
- the `longhorn-system` namespace's pod-security label, since Longhorn's
  engine and CSI plugin pods need privileged access to host block devices
  that the restricted Pod Security Standard forbids — this module's own
  responsibility, unchanged

The namespace is a `kubernetes_namespace` resource, not part of the Helm
release, because neither Helm-native option works here: Helm records a
release's Secret in its target namespace before applying that release's own
manifests, so a chart cannot create the namespace it installs into, and
`helm_release.longhorn`'s `create_namespace` flag creates a plain namespace
outside any release's ownership, which a `Namespace` object templated into the
chart would then collide with on install (an ownership-metadata conflict).
Managing it directly with the `kubernetes` provider sidesteps both and lets it
carry the pod-security label from the start.

## Inputs

- `longhorn_version`
- `namespace`
- `data_path`
- `replica_count`
- `longhorn_extra_values`
- `helm_timeout`

## Outputs

- `longhorn_version`
- `namespace`

## Notes

`data_path` just needs to be a writable directory on the node's disk;
Longhorn creates it if it doesn't already exist. No reboot or node-image
change is needed to turn this addon on or change the path, unlike under
Talos, where enabling it the first time rebooted every node to apply the now
-removed machine-config patch.
