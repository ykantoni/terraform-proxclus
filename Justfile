# Task runner for this cluster. Run `just --list` to see all recipes.
#
# Unlike Make, a recipe with no `#!shebang` runs as one shell script — every
# line shares state (cd, variables) — so none of these need Make's `.ONESHELL:`
# or a bash -c wrapper to string commands together.

plan:
    terraform plan

# Apply the Terraform configuration.
apply:
    terraform apply -auto-approve

# Destroy everything Terraform manages: the cluster and its VMs.
# The patch only runs if the apiserver is reachable: if the cluster's
# already gone (e.g. this is a re-run after a prior destroy succeeded),
# there's nothing left for Longhorn's setting to guard anyway.
destroy:
    if kubectl cluster-info --request-timeout=5s >/dev/null 2>&1; then \
      kubectl -n longhorn-system patch settings.longhorn.io deleting-confirmation-flag \
        --type=merge -p '{"value":"true"}'; \
    fi
    terraform destroy -auto-approve

# Format all Terraform files in place.
fmt:
    terraform fmt -recursive

# Build both Proxmox VM templates: the plain one (vm_id 9000) common nodes
# clone from, and the NVIDIA one (vm_id 9001) GPU-tagged nodes clone from.
t-create:
    /usr/bin/bash -c "pushd vm-templates && sudo ./qemu-iscsi-2c.sh && sudo ./nvidia-qemu-iscsi-2c.sh && popd"

# Destroy the Postgres cluster.
pg-destroy:
    kubectl delete -f apps/postgres/postgres-primary-standby.yaml --ignore-not-found

# Create the Postgres cluster.
pg-create:
    kubectl apply -f apps/postgres/postgres-primary-standby.yaml

# Destroy both templates.
t-destroy:
    sudo /usr/sbin/qm destroy 9000
    sudo /usr/sbin/qm destroy 9001

# Write talosconfig and kubeconfig from Terraform outputs.
generate:
    terraform output -raw talosconfig > "$HOME/talosconfig"
    mkdir -p "$HOME/.kube"
    terraform output -raw kubeconfig > "$HOME/.kube/config"
    chmod 600 "$HOME/talosconfig" "$HOME/.kube/config"
