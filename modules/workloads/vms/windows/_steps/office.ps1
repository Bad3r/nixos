# The Office suite lists itself under Apps as "Microsoft 365 ..." or
# "Microsoft Office ...", with OfficeClickToRun.exe as its uninstaller.
# Apply runs the installer at $Data.path for at most $Data.timeout seconds,
# then deletes it.
$uninstall = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)
$pollSeconds = 30

function Test-Installed {
    # A malformed subkey must not abort the probe.
    $entries = @(Get-ItemProperty -Path $uninstall -ErrorAction SilentlyContinue | Where-Object {
            "$($_.UninstallString)" -like '*\OfficeClickToRun.exe*' -and
            ("$($_.DisplayName)" -like 'Microsoft 365*' -or "$($_.DisplayName)" -like 'Microsoft Office*')
        })
    $entries.Count -gt 0
}

# An install or update in progress: the Click-to-Run client, or a
# Click-to-Run engine other than the resident /service instance.
function Test-Busy {
    $running = @(Get-CimInstance -ClassName Win32_Process -Filter "Name = 'OfficeC2RClient.exe' OR Name = 'OfficeClickToRun.exe'" |
            Where-Object { $_.Name -eq 'OfficeC2RClient.exe' -or "$($_.CommandLine)" -notmatch '/service' })
    $running.Count -gt 0
}

function Test-Done { (Test-Installed) -and -not (Test-Busy) }

function Stop-Tree([int] $id) {
    & taskkill.exe /PID $id /T /F | Out-Null
    # 128: the process is already gone.
    if ($LASTEXITCODE -notin 0, 128) { Write-Output "taskkill /PID $id exited with $LASTEXITCODE" }
}

if ($Mode -eq 'probe') {
    if (Test-Installed) { exit 0 }
    exit 10
}

$deadline = (Get-Date).AddSeconds([int] $Data.timeout)
$id = $null
$process = $null
try {
    while (Test-Busy) {
        if ((Get-Date) -gt $deadline) { throw 'another Click-to-Run install did not finish in time' }
        Start-Sleep -Seconds $pollSeconds
    }
    if (Test-Installed) { return }

    # Win32_Process.Create starts the installer outside this process tree, so
    # nothing it spawns holds the guest agent's output pipes open.
    $created = Invoke-CimMethod -ClassName Win32_Process -MethodName Create -Arguments @{
        CommandLine = "`"$($Data.path)`""
    }
    if ($created.ReturnValue -ne 0) { throw "Win32_Process.Create returned $($created.ReturnValue)" }
    $id = [int] $created.ProcessId
    $process = Get-Process -Id $id -ErrorAction SilentlyContinue
    if ($null -eq $process) {
        Write-Output 'the installer exited before it could be watched, so only the listing tells its result'
    }
    else {
        # Without a cached handle, ExitCode stays empty after the process exits.
        $null = $process.Handle
    }

    # The installer has no silent switch and may keep a window open in
    # session 0 after Office is in place, so completion is polled.
    while (-not (Test-Done)) {
        if ($null -ne $process -and $process.HasExited -and $process.ExitCode -ne 0) {
            throw "$($Data.path) exited with $($process.ExitCode)"
        }
        if ((Get-Date) -gt $deadline) {
            Stop-Tree $id
            throw "Office was not installed within $($Data.timeout) s"
        }
        Start-Sleep -Seconds $pollSeconds
    }
    if ($null -ne $process -and -not $process.HasExited) {
        Stop-Tree $id
        Write-Output 'stopped the installer, which kept running after Office was installed'
    }
}
finally {
    if ($null -ne $process) { $process.WaitForExit(60000) | Out-Null }
    try {
        Remove-Item -LiteralPath $Data.path -Force -ErrorAction Stop
    }
    catch {
        Write-Output "cannot delete $($Data.path): $_"
    }
}
