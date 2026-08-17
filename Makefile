apply:
	terraform apply -auto-approve

destroy:
	terraform destroy -auto-approve

generate:
	terraform output -raw talosconfig > $(HOME)/talosconfig
	mkdir -p $(HOME)/.kube
	terraform output -raw kubeconfig > $(HOME)/.kube/config
	chmod 600 $(HOME)/talosconfig $(HOME)/.kube/config
