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

variable "image_tag" {
  type = string
}

variable "output_directory" {
  type = string
}

variable "privileged" {
  type    = bool
  default = false
}

source "docker" "ubuntu2604" {
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
    "ENV DEBIAN_FRONTEND noninteractive"
  ]
}

build {
  sources = ["source.docker.ubuntu2604"]

  provisioner "shell" {
    remote_folder = "/opt/packer-provisioning"
    inline = [
      "mkdir -p /imagegeneration/installers",
      "test \"$(cat /proc/1/comm)\" = systemd || { echo 'systemd failed to start as PID 1; inspect cgroups and privileges' >&2; exit 1; }"
    ]
  }

  provisioner "file" {
    source      = "${path.root}/../scripts/helpers"
    destination = "/imagegeneration"
  }

  provisioner "file" {
    source      = "${path.root}/../scripts/tests"
    destination = "/imagegeneration"
  }

  provisioner "file" {
    source      = "${path.root}/../toolsets/toolset-2604.json"
    destination = "/imagegeneration/installers/toolset.json"
  }

  provisioner "file" {
    source      = "${path.root}/verify-spike.sh"
    destination = "/imagegeneration/verify-spike.sh"
  }

  provisioner "shell" {
    remote_folder = "/opt/packer-provisioning"
    inline = [
      "mkdir -p /imagegeneration/adc-spike",
      "mv /imagegeneration/verify-spike.sh /imagegeneration/adc-spike/verify-spike.sh",
      "chmod +x /imagegeneration/helpers/invoke-tests.sh",
      "ln -s /imagegeneration/helpers/invoke-tests.sh /usr/local/bin/invoke_tests"
    ]
  }

  provisioner "shell" {
    remote_folder = "/opt/packer-provisioning"
    environment_vars = [
      "HELPER_SCRIPTS=/imagegeneration/helpers",
      "INSTALLER_SCRIPT_FOLDER=/imagegeneration/installers",
      "DEBIAN_FRONTEND=noninteractive"
    ]
    scripts = [
      "${path.root}/../scripts/build/install-apt-vital.sh",
      "${path.root}/../scripts/build/install-powershell.sh"
    ]
  }

  provisioner "shell" {
    remote_folder = "/opt/packer-provisioning"
    environment_vars = [
      "HELPER_SCRIPTS=/imagegeneration/helpers",
      "INSTALLER_SCRIPT_FOLDER=/imagegeneration/installers"
    ]
    execute_command = "{{ .Vars }} pwsh -File {{ .Path }}"
    script          = "${path.root}/Install-SpikePester.ps1"
  }

  provisioner "shell" {
    remote_folder = "/opt/packer-provisioning"
    environment_vars = [
      "HELPER_SCRIPTS=/imagegeneration/helpers",
      "INSTALLER_SCRIPT_FOLDER=/imagegeneration/installers",
      "DEBIAN_FRONTEND=noninteractive"
    ]
    scripts = [
      "${path.root}/../scripts/build/install-docker.sh",
      "${path.root}/verify-spike.sh"
    ]
  }

  post-processor "docker-tag" {
    repository = "adc-ubuntu2604-spike"
    tags       = [var.image_tag]
  }

  post-processor "manifest" {
    output = "${var.output_directory}/manifest.json"
  }
}
