################################################################################
##  File:  Invoke-Cleanup.ps1
##  Desc:  Cleanup WinSxS, temp, cache and compress directories in batches of two
################################################################################

Write-Host "Cleanup WinSxS"
dism.exe /online /Cleanup-Image /StartComponentCleanup /ResetBase
if ($LASTEXITCODE -ne 0) {
    throw "Failed to cleanup WinSxS"
}

Write-Host "Clean up various directories"
@(
    "$env:SystemDrive\Recovery",
    "$env:SystemRoot\logs",
    "$env:SystemRoot\winsxs\manifestcache",
    "$env:SystemRoot\Temp",
    "$env:SystemDrive\Users\$env:INSTALL_USER\AppData\Local\Temp",
    "$env:TEMP",
    "$env:AZURE_CONFIG_DIR\logs",
    "$env:AZURE_CONFIG_DIR\commands",
    "$env:AZURE_CONFIG_DIR\telemetry"
) | ForEach-Object {
    if (Test-Path $_) {
        Write-Host "Removing $_"
        cmd /c "takeown /d Y /R /f $_ 2>&1" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to take ownership of $_"
        }
        cmd /c "icacls $_ /grant:r administrators:f /t /c /q 2>&1" | Out-Null
        if ($LASTEXITCODE -ne 0) {
            throw "Failed to grant administrators full control of $_"
        }
        Remove-Item $_ -Recurse -Force -ErrorAction SilentlyContinue | Out-Null
    }
}

# Remove AllUsersAllHosts profile
Remove-Item $profile.AllUsersAllHosts -Force -ErrorAction SilentlyContinue | Out-Null

# Clean yarn and npm cache
cmd /c "yarn cache clean 2>&1" | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to clean yarn cache"
}

cmd /c "npm cache clean --force 2>&1" | Out-Null
if ($LASTEXITCODE -ne 0) {
    throw "Failed to clean npm cache"
}

if (Test-IsWin25-X64) {
    $directoriesToCompact = @(
        "C:\Program Files (x86)\Android",
        "C:\Program Files\dotnet",
        "$env:SystemRoot\assembly",
        "$env:SystemRoot\WinSxS"
    )
    Write-Host "Starting Image slimming process"
    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $maxParallelProcesses = 2
    for ($offset = 0; $offset -lt $directoriesToCompact.Count; $offset += $maxParallelProcesses) {
        $compressionJobs = @()
        $failedDirectories = @()
        try {
            $batchEnd = [Math]::Min($offset + $maxParallelProcesses, $directoriesToCompact.Count)
            for ($index = $offset; $index -lt $batchEnd; $index++) {
                $directory = $directoriesToCompact[$index]
                $job = [PSCustomObject]@{
                    Directory = $directory
                    OutputLog = $null
                    ErrorLog = $null
                    Process = $null
                }
                $compressionJobs += $job
                $job.OutputLog = [System.IO.Path]::GetTempFileName()
                $job.ErrorLog = [System.IO.Path]::GetTempFileName()
                Write-Host "Compressing '$directory' directory"
                $job.Process = Start-Process -FilePath "$env:SystemRoot\System32\compact.exe" `
                    -ArgumentList "/s:`"$directory`" /c /a /i /EXE:LZX *" `
                    -RedirectStandardOutput $job.OutputLog -RedirectStandardError $job.ErrorLog `
                    -PassThru -ErrorAction Stop
                # Retain the process handle so ExitCode remains available after completion.
                $null = $job.Process.Handle
            }

            foreach ($job in $compressionJobs) {
                $job.Process.WaitForExit()
                Write-Host "Compression result for '$($job.Directory)'"
                if ($job.Process.ExitCode -ne 0) {
                    Get-Content -Path $job.OutputLog -ErrorAction Stop
                    $failedDirectories += "'$($job.Directory)' (exit code $($job.Process.ExitCode))"
                } else {
                    Get-Content -Path $job.OutputLog -Tail 3 -ErrorAction Stop
                }
                Get-Content -Path $job.ErrorLog -ErrorAction Stop
            }
        } finally {
            foreach ($job in $compressionJobs) {
                if ($null -ne $job.Process) {
                    $job.Process.WaitForExit()
                    $job.Process.Dispose()
                }
            }
            foreach ($job in $compressionJobs) {
                foreach ($log in @($job.OutputLog, $job.ErrorLog)) {
                    if ($null -ne $log) {
                        Remove-Item -Path $log -Force -ErrorAction Stop
                    }
                }
            }
        }
        if ($failedDirectories.Count -gt 0) {
            throw "Failed to compress directories: $($failedDirectories -join ', ')"
        }
    }
    $stopwatch.Stop()
    $time = "{0}:{1:00}" -f [Math]::Floor($stopwatch.Elapsed.TotalMinutes), $stopwatch.Elapsed.Seconds
    Write-Host "The process took a total of $time (in minutes:seconds)"
}
