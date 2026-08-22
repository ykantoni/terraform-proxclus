# customization-common.yaml and customization-gpu.yaml are the single source
# of truth for what goes into the Talos image: Terraform derives an installer
# schematic from each, and vm-templates builds the matching boot image (9000
# and 9001) from the same files. Factory IDs are a hash of the schematic, so
# a template and the machine configuration that installs it can never drift
# apart.
#
# Extensions only take effect on install or upgrade. Adding one to a running
# cluster needs talosctl upgrade --image, not just terraform apply.
resource "talos_image_factory_schematic" "common" {
  schematic = file("${path.root}/customization-common.yaml")
}

resource "talos_image_factory_schematic" "gpu" {
  schematic = file("${path.root}/customization-gpu.yaml")
}
