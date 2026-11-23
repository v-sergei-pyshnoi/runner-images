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

source "docker" "image" {
  image      = var.base_image
  pull       = false
  commit     = true
  privileged = true
  platform   = "linux/amd64"
  run_command = [
    "--detach", "--interactive",
    "--name", var.container_name,
    "--cgroupns=private",
    "--entrypoint=/bin/sh",
    "{{.Image}}", "-c",
    "while [ ! -e /run/start-systemd ]; do sleep 1; done; exec /sbin/init"
  ]
  tmpfs = ["/run", "/run/lock"]
  changes = [
    "ENTRYPOINT []",
    "CMD [\"/sbin/init\"]",
    "ENV HELPER_SCRIPTS /imagegeneration/helpers",
    "ENV INSTALLER_SCRIPT_FOLDER /imagegeneration/installers",
    "ENV DEBIAN_FRONTEND noninteractive"
  ]
}
