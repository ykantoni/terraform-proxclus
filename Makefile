apply:
	terraform apply -auto-approve

destroy:
	kubectl -n longhorn-system patch settings.longhorn.io deleting-confirmation-flag \
      --type=merge -p '{"value":"true"}'
	terraform destroy -auto-approve

t-create:
	/usr/bin/bash -c "pushd vm-templates && sudo ./nvidia-qemu-iscsi-2c.sh && popd"

t-destroy:
	sudo /usr/sbin/qm destroy 9000

fmt:
	terraform fmt -recursive

generate:
	terraform output -raw talosconfig > $(HOME)/talosconfig
	mkdir -p $(HOME)/.kube
	terraform output -raw kubeconfig > $(HOME)/.kube/config
	chmod 600 $(HOME)/talosconfig $(HOME)/.kube/config
