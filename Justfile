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

# Build both Proxmox VM templates: the plain one (vm_id 9100) common nodes
# clone from, and the GPU one (vm_id 9101) GPU-tagged nodes clone from. Run
# vm-templates/import-ubuntu-cloud-image.sh once first (see packer/README.md).
t-create:
    /usr/bin/bash -c "pushd packer && packer init . && packer build ubuntu-common.pkr.hcl && packer build ubuntu-gpu.pkr.hcl && popd"

# Destroy the Postgres cluster.
pg-destroy:
    kubectl delete -f apps/postgres/postgres-primary-standby.yaml --ignore-not-found

# Create the Postgres cluster.
pg-create:
    kubectl apply -f apps/postgres/postgres-primary-standby.yaml

# Destroy both templates.
t-destroy:
    sudo /usr/sbin/qm destroy 9100
    sudo /usr/sbin/qm destroy 9101

# Write kubeconfig and an SSH key for ssh_admin_user from Terraform outputs.
generate:
    mkdir -p "$HOME/.kube"
    terraform output -raw kubeconfig > "$HOME/.kube/config"
    terraform output -raw ssh_private_key > "$HOME/.ssh/rke2_admin"
    chmod 600 "$HOME/.kube/config" "$HOME/.ssh/rke2_admin"
