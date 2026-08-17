apply:
	terraform apply -auto-approve

destroy:
	terraform destroy -auto-approve

t-create:
	/usr/bin/bash -c "pushd vm-templates && sudo ./nvidia-qemu-iscsi-2c.sh && popd"

t-destroy:
	sudo /usr/sbin/qm destroy 9000

generate:
	terraform output -raw talosconfig > $(HOME)/talosconfig
	mkdir -p $(HOME)/.kube
	terraform output -raw kubeconfig > $(HOME)/.kube/config
	chmod 600 $(HOME)/talosconfig $(HOME)/.kube/config
