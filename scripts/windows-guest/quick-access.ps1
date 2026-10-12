param([Parameter(Mandatory = $true)] [string] $ManifestPath)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$staging = Split-Path -Parent $ManifestPath
$root = Split-Path -Parent $staging
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$scriptPath = Join-Path $root 'bin\pin-quick-access.ps1'
$taskName = 'NixOS Outlook Quick Access'
$command = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$arguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $scriptPath + '"'

function Test-PinScript([string] $Path) {
    return (Test-Path -LiteralPath $Path -PathType Leaf) -and
        (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $manifest.hashes.'pin-quick-access.ps1'
}

function Get-PinTask {
    return Get-ScheduledTask -TaskPath '\' | Where-Object { $_.TaskName -eq $taskName }
}

function Test-PinTask($Task) {
    if (-not $Task) { return $false }
    $group = $Task.Principal.GroupId
    if (-not $group) { return $false }
    if (-not $group.StartsWith('S-1-')) {
        $group = ([Security.Principal.NTAccount] $group).Translate([Security.Principal.SecurityIdentifier]).Value
    }
    return $Task.Settings.Enabled -and $Task.Settings.StartWhenAvailable -and $group -eq 'S-1-5-32-545' -and
        $Task.Principal.LogonType -eq 4 -and $Task.Principal.RunLevel -eq 0 -and
        @($Task.Actions).Count -eq 1 -and $Task.Actions[0].Execute -eq $command -and
        $Task.Actions[0].Arguments -eq $arguments -and @($Task.Triggers).Count -eq 1 -and
        $Task.Triggers[0].CimClass.CimClassName -eq 'MSFT_TaskLogonTrigger' -and
        $Task.Triggers[0].Enabled -and $Task.Triggers[0].Delay -eq 'PT30S' -and
        $Task.Settings.ExecutionTimeLimit -eq 'PT3M' -and $Task.Settings.MultipleInstances -eq 2 -and
        -not $Task.Settings.DisallowStartIfOnBatteries -and -not $Task.Settings.StopIfGoingOnBatteries
}

try {
    $source = Join-Path $staging 'pin-quick-access.ps1'
    if (-not (Test-PinScript $source)) { throw 'Quick access pin script payload hash mismatch.' }
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $scriptPath) -Force
    if (-not (Test-PinScript $scriptPath)) {
        Copy-Item -LiteralPath $source -Destination $scriptPath -Force
    }
    if (-not (Test-PinTask (Get-PinTask))) {
        $action = New-ScheduledTaskAction -Execute $command -Argument $arguments
        $trigger = New-ScheduledTaskTrigger -AtLogOn
        $trigger.Delay = 'PT30S'
        $principal = New-ScheduledTaskPrincipal -GroupId 'S-1-5-32-545' -RunLevel Limited
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::FromMinutes(3))
        $null = Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force
        if (-not (Test-PinTask (Get-PinTask))) { throw 'Quick access logon task did not match the declaration.' }
    }
    $explorers = @(Get-CimInstance Win32_Process -Filter "Name='explorer.exe'" | Where-Object { $_.SessionId -ne 0 })
    if ($explorers.Count -eq 0) {
        [Console]::WriteLine('Windows Quick access pinning awaits an interactive File Explorer session.')
        exit 0
    }
    if ((Get-PinTask).State -eq 'Running') {
        $started = (Get-ScheduledTaskInfo -TaskName $taskName).LastRunTime
    } else {
        $started = [DateTime]::Now.AddSeconds(-1)
        Start-ScheduledTask -TaskName $taskName
    }
    for ($attempt = 0; $attempt -lt 120; $attempt++) {
        $info = Get-ScheduledTaskInfo -TaskName $taskName
        if ($info.LastRunTime -ge $started -and (Get-PinTask).State -ne 'Running') {
            if ($info.LastTaskResult -ne 0) { throw "Quick access pin task failed with result $($info.LastTaskResult)." }
            [Console]::WriteLine('Windows transfer drive is present in File Explorer Quick access.')
            exit 0
        }
        Start-Sleep -Seconds 1
    }
    throw 'Quick access pin task did not finish before its verification deadline.'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
