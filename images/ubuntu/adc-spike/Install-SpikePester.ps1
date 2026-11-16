################################################################################
##  File:  Install-SpikePester.ps1
##  Desc:  Install only the toolset-pinned Pester module for the Docker spike
################################################################################

$ErrorActionPreference = "Stop"
$ProgressPreference = "SilentlyContinue"

Import-Module "$env:HELPER_SCRIPTS/Common.Helpers.psm1" -DisableNameChecking

$pester = (Get-ToolsetContent).powershellModules | Where-Object { $_.name -eq "Pester" }
if (-not $pester -or $pester.versions.Count -ne 1) {
    throw "The spike requires exactly one pinned Pester version in the toolset."
}

Set-PSRepository -Name PSGallery -InstallationPolicy Trusted
Install-Module -Name Pester -RequiredVersion $pester.versions[0] -Scope AllUsers -Force
Import-Module Pester -RequiredVersion $pester.versions[0]
