packer {
  required_plugins {
    docker = {
      version = "= 1.1.5"
      source  = "github.com/hashicorp/docker"
    }
  }
}

variable "base_image" {
  type = string
}

variable "container_name" {
  type = string
}

variable "privileged" {
  type    = bool
  default = false
}

source "docker" "image" {
  image      = var.base_image
  pull       = false
  commit     = true
  privileged = var.privileged
  platform   = "linux/amd64"
  run_command = [
    "--detach", "--interactive",
    "--name", var.container_name,
    "--cgroupns=private",
    "--entrypoint=/sbin/init",
    "{{.Image}}"
  ]
  tmpfs = ["/run", "/run/lock"]
  changes = [
    "ENTRYPOINT []",
    "CMD [\"/sbin/init\"]",
    "ENV HELPER_SCRIPTS /imagegeneration/helpers",
    "ENV INSTALLER_SCRIPT_FOLDER /imagegeneration/installers",
    "ENV DEBIAN_FRONTEND noninteractive",
    "ENV ADC_SPIKE_DOCKER_STORAGE ${var.docker_storage}"
  ]
}
