# Task runner for this cluster. Run `just --list` to see all recipes.
#
# Unlike Make, a recipe with no `#!shebang` runs as one shell script — every
# line shares state (cd, variables) — so none of these need Make's `.ONESHELL:`
# or a bash -c wrapper to string commands together.

# Apply the Terraform configuration.
apply:
    terraform apply -auto-approve

# Destroy everything Terraform manages: the cluster and its VMs.
destroy:
    kubectl -n longhorn-system patch settings.longhorn.io deleting-confirmation-flag \
      --type=merge -p '{"value":"true"}'
    terraform destroy -auto-approve

# Format all Terraform files in place.
fmt:
    terraform fmt -recursive

# Build the Proxmox VM template (vm_id 9000) every node clones from.
t-create:
    cd vm-templates && sudo ./nvidia-qemu-iscsi-2c.sh

pg-destroy:
    kubectl delete -f apps/postgres/postgres-primary-standby.yaml

pg-create:
    kubectl create -f apps/postgres/postgres-primary-standby.yaml      

# Destroy that template.
t-destroy:
    sudo /usr/sbin/qm destroy 9000

# Write talosconfig and kubeconfig from Terraform outputs.
generate:
    terraform output -raw talosconfig > "$HOME/talosconfig"
    mkdir -p "$HOME/.kube"
    terraform output -raw kubeconfig > "$HOME/.kube/config"
    chmod 600 "$HOME/talosconfig" "$HOME/.kube/config"
