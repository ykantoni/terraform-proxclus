# customization.yaml is the single source of truth for what goes into the Talos
# image: Terraform derives the installer schematic from it, and vm-templates
# builds the boot image from the same file. Factory IDs are a hash of the
# schematic, so the two cannot drift apart.
#
# Extensions only take effect on install or upgrade. Adding one to a running
# cluster needs talosctl upgrade --image, not just terraform apply.
resource "talos_image_factory_schematic" "this" {
  schematic = file("${path.root}/customization.yaml")
}
