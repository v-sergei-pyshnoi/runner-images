locals {
  ubuntu26_remote_folder = var.cloud_provider == "docker" ? "/opt/packer-provisioning" : "/tmp"
  ubuntu26_shell_command = var.cloud_provider == "docker" ? "{{ .Vars }} bash -e -c 'source ${var.helper_script_folder}/etc-environment.sh; reload_etc_environment; export SUDO_USER=${var.install_user}; bash -e {{ .Path }}'" : "sudo sh -c '{{ .Vars }} {{ .Path }}'"
  ubuntu26_pwsh_command  = var.cloud_provider == "docker" ? "{{ .Vars }} bash -e -c 'source ${var.helper_script_folder}/etc-environment.sh; reload_etc_environment; export SUDO_USER=${var.install_user}; pwsh -File {{ .Path }}'" : "sudo sh -c '{{ .Vars }} pwsh -f {{ .Path }}'"
}

build {
  sources = var.cloud_provider == "docker" ? ["source.docker.image"] : var.cloud_provider == "aws" ? ["source.amazon-ebs.image"] : ["source.azure-arm.image"]
  name    = "ubuntu-26_04"

  provisioner "shell" {
    remote_folder   = local.ubuntu26_remote_folder
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline = var.cloud_provider == "docker" ? [
      "test \"$(cat /proc/1/comm)\" = systemd",
      "mkdir -p ${var.image_folder} /etc/cloud/templates",
      "chmod 777 ${var.image_folder}",
      "useradd --create-home --shell /bin/bash ${var.install_user}",
      "echo '${var.install_user} ALL=(ALL) NOPASSWD: ALL' > /etc/sudoers.d/adc-image-builder",
      "chmod 440 /etc/sudoers.d/adc-image-builder",
      "touch /etc/environment",
      "if ! grep -q '^PATH=' /etc/environment; then printf 'PATH=%s\\n' \"$PATH\" >> /etc/environment; fi",
      "apt-get update --error-on=any"
    ] : ["mkdir ${var.image_folder}", "chmod 777 ${var.image_folder}"]
  }

  provisioner "file" {
    destination = "${var.helper_script_folder}"
    source      = "${path.root}/../scripts/helpers"
  }

  provisioner "shell" {
    except          = ["docker.image"]
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    script          = "${path.root}/../scripts/build/configure-apt-mock.sh"
  }

  provisioner "shell" {
    remote_folder    = local.ubuntu26_remote_folder
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "DEBIAN_FRONTEND=noninteractive", "APT_SNAPSHOT_TIMESTAMP=${var.apt_snapshot_timestamp}"]
    execute_command  = local.ubuntu26_shell_command
    scripts = [
      "${path.root}/../scripts/build/install-ms-repos.sh",
      "${path.root}/../scripts/build/configure-apt-sources.sh",
      "${path.root}/../scripts/build/configure-apt.sh"
    ]
  }

  provisioner "shell" {
    remote_folder   = local.ubuntu26_remote_folder
    execute_command = local.ubuntu26_shell_command
    script          = "${path.root}/../scripts/build/configure-limits.sh"
  }

  provisioner "file" {
    destination = "${var.installer_script_folder}"
    source      = "${path.root}/../scripts/build"
  }

  provisioner "file" {
    destination = "${var.image_folder}"
    sources = [
      "${path.root}/../assets/post-gen",
      "${path.root}/../scripts/tests",
      "${path.root}/../scripts/docs-gen"
    ]
  }

  provisioner "file" {
    destination = "${var.image_folder}/docs-gen/"
    source      = "${path.root}/../../../helpers/software-report-base"
  }

  provisioner "file" {
    destination = "${var.installer_script_folder}/toolset.json"
    source      = "${path.root}/../toolsets/toolset-2604.json"
  }

  provisioner "shell" {
    remote_folder   = local.ubuntu26_remote_folder
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline = [
      "mv ${var.image_folder}/docs-gen ${var.image_folder}/SoftwareReport",
      "mv ${var.image_folder}/post-gen ${var.image_folder}/post-generation"
    ]
  }

  provisioner "shell" {
    remote_folder    = local.ubuntu26_remote_folder
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "IMAGE_VERSION=${var.image_version}", "IMAGEDATA_FILE=${var.imagedata_file}"]
    execute_command  = local.ubuntu26_shell_command
    scripts          = ["${path.root}/../scripts/build/configure-image-data.sh"]
  }

  provisioner "shell" {
    remote_folder    = local.ubuntu26_remote_folder
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "IMAGE_OS=${var.image_os}", "HELPER_SCRIPTS=${var.helper_script_folder}", "IMAGE_BUILD_TARGET=${var.cloud_provider}"]
    execute_command  = local.ubuntu26_shell_command
    scripts          = ["${path.root}/../scripts/build/configure-environment.sh"]
  }

  provisioner "shell" {
    remote_folder    = local.ubuntu26_remote_folder
    environment_vars = ["DEBIAN_FRONTEND=noninteractive", "HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = local.ubuntu26_shell_command
    scripts          = ["${path.root}/../scripts/build/install-apt-vital.sh"]
  }

  provisioner "shell" {
    remote_folder    = local.ubuntu26_remote_folder
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = local.ubuntu26_shell_command
    scripts          = ["${path.root}/../scripts/build/install-powershell.sh"]
  }

  provisioner "shell" {
    remote_folder    = local.ubuntu26_remote_folder
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = local.ubuntu26_pwsh_command
    scripts          = ["${path.root}/../scripts/build/Install-PowerShellModules.ps1", "${path.root}/../scripts/build/Install-PowerShellAzModules.ps1"]
  }

  provisioner "shell" {
    remote_folder    = local.ubuntu26_remote_folder
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "DEBIAN_FRONTEND=noninteractive"]
    execute_command  = local.ubuntu26_shell_command
    scripts = [
      "${path.root}/../scripts/build/install-actions-cache.sh",
      "${path.root}/../scripts/build/install-apt-common.sh",
      "${path.root}/../scripts/build/install-azcopy.sh",
      "${path.root}/../scripts/build/install-azure-cli.sh",
      "${path.root}/../scripts/build/install-azure-devops-cli.sh",
      "${path.root}/../scripts/build/install-bicep.sh",
      "${path.root}/../scripts/build/install-apache.sh",
      "${path.root}/../scripts/build/install-aws-tools.sh",
      "${path.root}/../scripts/build/install-clang.sh",
      "${path.root}/../scripts/build/install-swift.sh",
      "${path.root}/../scripts/build/install-cmake.sh",
      "${path.root}/../scripts/build/install-codeql-bundle.sh",
      "${path.root}/../scripts/build/install-awf.sh",
      "${path.root}/../scripts/build/install-container-tools.sh",
      "${path.root}/../scripts/build/install-dotnetcore-sdk.sh",
      "${path.root}/../scripts/build/install-microsoft-edge.sh",
      "${path.root}/../scripts/build/install-gcc-compilers.sh",
      "${path.root}/../scripts/build/install-firefox.sh",
      "${path.root}/../scripts/build/install-gfortran.sh",
      "${path.root}/../scripts/build/install-git.sh",
      "${path.root}/../scripts/build/install-git-lfs.sh",
      "${path.root}/../scripts/build/install-github-cli.sh",
      "${path.root}/../scripts/build/install-google-chrome.sh",
      "${path.root}/../scripts/build/install-google-cloud-cli.sh",
      "${path.root}/../scripts/build/install-haskell.sh",
      "${path.root}/../scripts/build/install-java-tools.sh",
      "${path.root}/../scripts/build/install-kubernetes-tools.sh",
      "${path.root}/../scripts/build/install-kotlin.sh",
      "${path.root}/../scripts/build/install-mysql.sh",
      "${path.root}/../scripts/build/install-nginx.sh",
      "${path.root}/../scripts/build/install-nvm.sh",
      "${path.root}/../scripts/build/install-nodejs.sh",
      "${path.root}/../scripts/build/install-copilot-cli.sh",
      "${path.root}/../scripts/build/install-bazel.sh",
      "${path.root}/../scripts/build/install-php.sh",
      "${path.root}/../scripts/build/install-postgresql.sh",
      "${path.root}/../scripts/build/install-ruby.sh",
      "${path.root}/../scripts/build/install-rust.sh",
      "${path.root}/../scripts/build/install-selenium.sh",
      "${path.root}/../scripts/build/install-packer.sh",
      "${path.root}/../scripts/build/install-vcpkg.sh",
      "${path.root}/../scripts/build/configure-dpkg.sh",
      "${path.root}/../scripts/build/install-yq.sh",
      "${path.root}/../scripts/build/install-android-sdk.sh",
      "${path.root}/../scripts/build/install-pypy.sh",
      "${path.root}/../scripts/build/install-python.sh",
      "${path.root}/../scripts/build/install-zstd.sh",
      "${path.root}/../scripts/build/install-ninja.sh"
    ]
  }

  provisioner "shell" {
    only             = ["docker.image"]
    remote_folder    = local.ubuntu26_remote_folder
    environment_vars = ["ADC_SPIKE_DOCKER_STORAGE=${var.docker_storage}"]
    script           = "${path.root}/../adc-spike/configure-docker-storage.sh"
  }

  provisioner "shell" {
    remote_folder    = local.ubuntu26_remote_folder
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "SKIP_DOCKER_IMAGE_PRELOAD=${var.skip_docker_image_preload}"]
    execute_command  = local.ubuntu26_shell_command
    scripts          = ["${path.root}/../scripts/build/install-docker.sh"]
  }

  provisioner "shell" {
    remote_folder    = local.ubuntu26_remote_folder
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = local.ubuntu26_pwsh_command
    scripts          = ["${path.root}/../scripts/build/Install-Toolset.ps1", "${path.root}/../scripts/build/Configure-Toolset.ps1"]
  }

  provisioner "shell" {
    remote_folder    = local.ubuntu26_remote_folder
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = local.ubuntu26_shell_command
    scripts          = ["${path.root}/../scripts/build/install-pipx-packages.sh"]
  }

  provisioner "shell" {
    remote_folder    = local.ubuntu26_remote_folder
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}", "DEBIAN_FRONTEND=noninteractive", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = var.cloud_provider == "docker" ? "sudo --user ${var.install_user} --set-home sh -c '{{ .Vars }} NONINTERACTIVE=1 bash -e -s' < {{ .Path }}" : "/bin/sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/install-homebrew.sh"]
  }

  provisioner "shell" {
    remote_folder    = local.ubuntu26_remote_folder
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = local.ubuntu26_shell_command
    scripts          = ["${path.root}/../scripts/build/configure-snap.sh"]
  }

  provisioner "shell" {
    remote_folder   = local.ubuntu26_remote_folder
    execute_command = local.ubuntu26_shell_command
    script          = "${path.root}/../scripts/build/list-dpkg.sh"
  }

  provisioner "shell" {
    except            = ["docker.image"]
    execute_command   = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    expect_disconnect = true
    inline            = ["echo 'Reboot VM'", "sudo reboot"]
  }

  provisioner "shell" {
    except              = ["docker.image"]
    execute_command     = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    pause_before        = "5m0s"
    scripts             = ["${path.root}/../scripts/build/cleanup.sh"]
    start_retry_timeout = "10m"
  }

  provisioner "shell" {
    remote_folder    = local.ubuntu26_remote_folder
    environment_vars = ["IMAGE_VERSION=${var.image_version}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}"]
    execute_command  = var.cloud_provider == "docker" ? local.ubuntu26_shell_command : "chmod +x {{ .Path }}; {{ .Vars }} {{ .Path }}"
    inline = concat(
      ["pwsh -File ${var.image_folder}/SoftwareReport/Generate-SoftwareReport.ps1 -OutputDirectory ${var.image_folder}"],
      var.cloud_provider == "docker" ? [] : ["pwsh -File ${var.image_folder}/tests/RunAll-Tests.ps1 -OutputDirectory ${var.image_folder}"]
    )
  }

  provisioner "file" {
    destination = "${path.root}/../Ubuntu2604-Readme.md"
    direction   = "download"
    source      = "${var.image_folder}/software-report.md"
  }

  provisioner "file" {
    destination = "${path.root}/../software-report.json"
    direction   = "download"
    source      = "${var.image_folder}/software-report.json"
  }

  provisioner "shell" {
    remote_folder    = local.ubuntu26_remote_folder
    environment_vars = ["HELPER_SCRIPT_FOLDER=${var.helper_script_folder}", "INSTALLER_SCRIPT_FOLDER=${var.installer_script_folder}", "IMAGE_FOLDER=${var.image_folder}"]
    execute_command  = local.ubuntu26_shell_command
    scripts          = ["${path.root}/../scripts/build/configure-system.sh"]
  }

  provisioner "shell" {
    except           = ["docker.image"]
    environment_vars = ["HELPER_SCRIPTS=${var.helper_script_folder}"]
    execute_command  = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    scripts          = ["${path.root}/../scripts/build/post-build-validation.sh"]
  }

  provisioner "shell" {
    except          = ["docker.image"]
    execute_command = "sudo sh -c '{{ .Vars }} {{ .Path }}'"
    inline          = ["sleep 30", "if [ -x /usr/sbin/waagent ] && [ -f /etc/waagent.conf ]; then /usr/sbin/waagent -force -deprovision+user; fi && export HISTSIZE=0 && sync"]
  }

  provisioner "file" {
    only        = ["docker.image"]
    source      = "${path.root}/../adc-spike/verify-spike.sh"
    destination = "${var.image_folder}/verify-spike.sh"
  }

  provisioner "shell" {
    only          = ["docker.image"]
    remote_folder = local.ubuntu26_remote_folder
    inline = [
      "mkdir -p ${var.image_folder}/adc-spike",
      "mv ${var.image_folder}/verify-spike.sh ${var.image_folder}/adc-spike/verify-spike.sh",
      "printf '%s\\n' '${var.docker_storage}' > ${var.image_folder}/adc-spike/docker-storage",
      "bash ${var.image_folder}/adc-spike/verify-spike.sh build",
      "apt-get clean",
      "rm /etc/sudoers.d/adc-image-builder"
    ]
  }

  provisioner "shell" {
    only          = ["docker.image"]
    remote_folder = local.ubuntu26_remote_folder
    script        = "${path.root}/../adc-spike/prepare-image.sh"
  }

  post-processor "manifest" {
    only   = ["docker.image"]
    output = "${path.root}/packer-manifest.json"
  }
}
