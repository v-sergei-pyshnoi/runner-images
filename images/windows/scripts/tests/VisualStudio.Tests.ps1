Describe "Visual Studio" {
    Context "Basic" {
        It "Catalog.json" {
            $instanceFolder = Get-Item "C:\ProgramData\Microsoft\VisualStudio\Packages\_Instances\*" | Select-Object -First 1
            Join-Path $instanceFolder.FullName "catalog.json" | Should -Exist
        }

        It "Devenv.exe" {
            $vsInstallRoot = (Get-VisualStudioInstance).InstallationPath
            $devenvexePath = "${vsInstallRoot}\Common7\IDE\devenv.exe"
            $devenvexePath | Should -Exist
        }

        It "Insiders channel and version" -Skip:((Get-ToolsetContent).visualStudio.channel -ne "insiders") {
            $vsToolset = (Get-ToolsetContent).visualStudio
            $vswherePath = "${env:ProgramFiles(x86)}\Microsoft Visual Studio\Installer\vswhere.exe"
            $vswherePath | Should -Exist
            $instances = @(& $vswherePath -prerelease -products "Microsoft.VisualStudio.Product.$($vsToolset.edition)" -format json | ConvertFrom-Json)
            $LASTEXITCODE | Should -Be 0
            $instances.Count | Should -Be 1
            $instances[0].channelId | Should -Be "VisualStudio.$($vsToolset.subversion).Preview"
            $instances[0].isPrerelease | Should -BeTrue
            ([version]$instances[0].installationVersion).Major | Should -Be ([int]$vsToolset.subversion)
        }
    }

    Context "Visual Studio components" {
        $expectedComponents = Get-ToolsetContent | Select-Object -ExpandProperty visualStudio | Select-Object -ExpandProperty workloads
        $testCases = $expectedComponents | ForEach-Object { @{ComponentName = $_} }
        BeforeAll {
            $installedComponents = Get-VisualStudioComponents | Select-Object -ExpandProperty Package
        }

        It "<ComponentName>" -TestCases $testCases {
            $installedComponents | Should -Contain $ComponentName
        }
    }
}

Describe "Windows 10 SDK" -Skip:((Test-IsWin25-X64) -or (Test-IsWin11-Arm64)) {
    It "Verifies 17763 SDK is installed" {
        "${env:ProgramFiles(x86)}\Windows Kits\10\DesignTime\CommonConfiguration\Neutral\UAP\10.0.17763.0\UAP.props" | Should -Exist
    }
}

Describe "Windows 11 SDK" {
    It "Verifies 26100 SDK is installed" {
        "${env:ProgramFiles(x86)}\Windows Kits\10\DesignTime\CommonConfiguration\Neutral\UAP\10.0.26100.0\UAP.props" | Should -Exist
    }
}
