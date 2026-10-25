# Drive letters for $Data.shares. In launcher mode the workloads-virtiofs task
# starts one WinFsp.Launcher instance of the virtiofs class per share at every
# boot; in service mode VirtioFsSvc serves the only share.
$shares = @($Data.shares)
$launched = @(if ($Data.mode -eq 'launcher') { $shares })
$served = @(if ($Data.mode -eq 'service') { $shares })
$active = $launched + $served
$exe = Join-Path $env:ProgramFiles 'Virtio-Win\VioFS\virtiofs.exe'
# Arguments replace virtiofs.exe's registry settings, which name the file
# system NTFS so that Windows runs programs from it as administrator.
$fsArguments = '-F NTFS'
$classKey = 'HKLM:\SOFTWARE\WOW6432Node\WinFsp\Services\virtiofs'
$classCommandLine = "-t %1 -m %2 $fsArguments"
$taskName = 'workloads-virtiofs'
$powershell = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$log = Join-Path $env:ProgramData 'workloads\virtiofs.log'
# Every running virtiofs.exe restarts its file system on any virtio-fs device
# arrival, which can break mounted shares, so a change in the attached tags
# restarts every instance.
$attachedFile = Join-Path $env:ProgramData 'workloads\virtiofs.attached'
$attached = @($launched | Where-Object attached | ForEach-Object tag | Sort-Object) -join ' '
$winfsp = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\WOW6432Node\WinFsp' -ErrorAction SilentlyContinue
$launchctl = if ($winfsp) { Join-Path $winfsp.InstallDir 'bin\launchctl-x64.exe' }
$service = Get-CimInstance -ClassName Win32_Service -Filter "Name='VirtioFsSvc'"

if ($active.Count -gt 0 -and -not ((Test-Path -LiteralPath $exe) -and $service)) {
    throw "VirtioFsSvc or $exe is missing; the virtio-win guest tools install both"
}
if ($launched.Count -gt 0 -and -not $launchctl) { throw 'WinFsp is not installed' }

function Get-CommandLine($share) { "$exe -t $($share.tag) -m $($share.letter): $fsArguments" }

function Get-TaskArguments {
    $script = @'
$ErrorActionPreference = 'Stop'
(Get-Service -Name 'WinFsp.Launcher').WaitForStatus('Running', [TimeSpan]::FromMinutes(5))
foreach ($share in @(@@SHARES@@)) {
    $tag, $letter = $share -split '='
    $result = @(& '@@LAUNCHCTL@@' start virtiofs $tag $tag "$($letter):") -join ' '
    Add-Content -LiteralPath '@@LOG@@' -Value "$(Get-Date -Format o) $tag $result"
}
'@
    $list = ($launched | ForEach-Object { "'$($_.tag)=$($_.letter)'" }) -join ', '
    $script = $script.Replace('@@SHARES@@', $list).Replace('@@LAUNCHCTL@@', $launchctl).Replace('@@LOG@@', $log)
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($script))
    "-NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded"
}

function Get-Task { Get-ScheduledTask -TaskName $taskName -TaskPath '\' -ErrorAction SilentlyContinue }

function Test-Task {
    $task = Get-Task
    if ($launched.Count -eq 0) { return $null -eq $task }
    if ($null -eq $task) { return $false }
    $actions = @($task.Actions)
    $triggers = @($task.Triggers)
    $user = $task.Principal.UserId
    $system = $user -eq 'S-1-5-18' -or
    ([System.Security.Principal.NTAccount] $user).Translate([System.Security.Principal.SecurityIdentifier]).Value -eq 'S-1-5-18'
    $system -and "$($task.State)" -ne 'Disabled' -and
    $actions.Count -eq 1 -and $actions[0].Execute -eq $powershell -and $actions[0].Arguments -eq (Get-TaskArguments) -and
    $triggers.Count -eq 1 -and $triggers[0].CimClass.CimClassName -eq 'MSFT_TaskBootTrigger'
}

function Get-Class { Get-Item -LiteralPath $classKey -ErrorAction SilentlyContinue }

function Test-Class {
    $key = Get-Class
    if (-not $key) { return $false }
    (@($key.GetValueNames() | Sort-Object) -join ',') -eq 'CommandLine,Executable,JobControl' -and $key.SubKeyCount -eq 0 -and
    $key.GetValue('Executable') -eq $exe -and $key.GetValue('CommandLine') -eq $classCommandLine -and
    "$($key.GetValueKind('JobControl'))" -eq 'DWord' -and $key.GetValue('JobControl') -eq 1
}

function Get-Recorded {
    if (Test-Path -LiteralPath $attachedFile) { "$(Get-Content -LiteralPath $attachedFile -Raw)".Trim() }
}

function Get-BrokenDevices {
    @(Get-CimInstance -ClassName Win32_PnPEntity | Where-Object {
            $_.PNPDeviceID -like 'PCI\VEN_1AF4&DEV_105A*' -and ($_.Service -ne 'VirtioFsDrv' -or $_.Status -ne 'OK')
        })
}

# Running virtiofs instances, by name, with their command lines unquoted.
function Get-Instances {
    $instances = @{}
    if (-not $launchctl -or (Get-Service -Name 'WinFsp.Launcher').Status -ne 'Running') { return $instances }
    $lines = @(& $launchctl list | Where-Object { $_ })
    if ($LASTEXITCODE -ne 0 -or $lines[0] -ne 'OK') { throw "launchctl list failed: $lines" }
    foreach ($line in @($lines | Select-Object -Skip 1)) {
        $class, $name = -split $line
        if ($class -ne 'virtiofs') { continue }
        $info = @(& $launchctl info virtiofs $name | Where-Object { $_ })
        # The instance exited after the list.
        if ($info[0] -ne 'OK') { continue }
        $instances[$name] = (($info | Select-Object -Skip 2) -join ' ').Replace('"', '').Trim()
    }
    $instances
}

function Test-Mounted($share) {
    $drive = [System.IO.DriveInfo]::GetDrives() | Where-Object Name -EQ "$($share.letter):\"
    $null -ne $drive -and $drive.IsReady
}

function Test-Service {
    if ($served.Count -eq 0) { return -not $service -or ($service.StartMode -eq 'Disabled' -and $service.State -eq 'Stopped') }
    $service.PathName -eq "`"$exe`" -t $($served[0].tag) -m $($served[0].letter): $fsArguments" -and
    $service.StartMode -eq 'Auto' -and $service.State -eq 'Running'
}

function Test-InPlace {
    $script:service = Get-CimInstance -ClassName Win32_Service -Filter "Name='VirtioFsSvc'"
    if (-not (Test-Service) -or -not (Test-Task)) { return $false }
    if ($launched.Count -gt 0 -and (-not (Test-Class) -or (Get-Recorded) -ne $attached)) { return $false }
    $instances = Get-Instances
    if ($instances.Count -ne $launched.Count) { return $false }
    foreach ($share in $launched) {
        if ($instances[$share.tag] -ne (Get-CommandLine $share)) { return $false }
    }
    @($active | Where-Object { $_.attached -and -not (Test-Mounted $_) }).Count -eq 0
}

if ($Mode -eq 'probe') {
    if (Test-InPlace) { exit 0 }
    exit 10
}

if ($served.Count -eq 0 -and $service -and -not (Test-Service)) {
    if ($service.State -ne 'Stopped') {
        Stop-Service -Name VirtioFsSvc -Force
        (Get-Service -Name VirtioFsSvc).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
    }
    Set-Service -Name VirtioFsSvc -StartupType Disabled
}
$restartAll = $launched.Count -gt 0 -and (Get-Recorded) -ne $attached
$instances = Get-Instances
foreach ($name in @($instances.Keys)) {
    $share = $launched | Where-Object tag -EQ $name
    if (-not $restartAll -and $share -and $instances[$name] -eq (Get-CommandLine $share)) { continue }
    $result = @(& $launchctl stop virtiofs $name) -join ' '
    if ($result -notlike 'OK*') { throw "launchctl stop virtiofs $name failed: $result" }
    $instances.Remove($name)
}
if ($launched.Count -eq 0 -and (Get-Task)) {
    Unregister-ScheduledTask -TaskName $taskName -TaskPath '\' -Confirm:$false
}
if ($active.Count -eq 0) { exit 0 }

if ((Get-BrokenDevices).Count -gt 0) {
    & pnputil.exe /add-driver (Join-Path $env:ProgramFiles 'Virtio-Win\VioFS\viofs.inf') /install | Out-Null
    $code = $LASTEXITCODE
    if ($code -eq 3010) { throw 'pnputil installed the viofs driver, which needs a restart: reboot the guest' }
    # 259: no device took the driver.
    if ($code -notin 0, 259) { throw "pnputil exited with $code" }
    $broken = Get-BrokenDevices
    if ($broken.Count -gt 0) {
        $states = ($broken | ForEach-Object { "$($_.PNPDeviceID) is $($_.Status), problem $($_.ConfigManagerErrorCode)" }) -join '; '
        throw "virtio-fs devices lack a working viofs driver: $states"
    }
}

$servedInPlace = $served.Count -gt 0 -and (Test-Service)
# A running VirtioFsSvc holds its own letter until it restarts below.
$serviceLetter = if ($service -and $service.State -ne 'Stopped' -and $service.PathName -match ' -m ([A-Z]):') { $Matches[1] }
# Instances read after the drives, so a letter an instance mounted meanwhile counts as its own.
$taken = @([System.IO.DriveInfo]::GetDrives() | ForEach-Object Name)
$instances = Get-Instances
foreach ($share in $active) {
    if ($instances.ContainsKey($share.tag)) { continue }
    if ($served.Count -gt 0 -and $share.letter -eq $serviceLetter) { continue }
    if ("$($share.letter):\" -in $taken) {
        throw "drive $($share.letter): is in use, so share $($share.tag) cannot mount there; free it or set the share's driveLetter"
    }
}

if ($served.Count -gt 0 -and -not $servedInPlace) {
    $path = "`"$exe`" -t $($served[0].tag) -m $($served[0].letter): $fsArguments"
    $restart = $service.State -ne 'Stopped'
    $result = Invoke-CimMethod -InputObject $service -MethodName Change -Arguments @{ PathName = $path; StartMode = 'Automatic' }
    if ($result.ReturnValue -ne 0) { throw "configuring VirtioFsSvc failed with $($result.ReturnValue)" }
    if ($restart) { Restart-Service -Name VirtioFsSvc -Force } else { Start-Service -Name VirtioFsSvc }
}

if ($launched.Count -gt 0) {
    if (-not (Test-Class)) {
        if (Get-Class) { Remove-Item -LiteralPath $classKey -Recurse }
        New-Item -Path $classKey -Force | Out-Null
        New-ItemProperty -LiteralPath $classKey -Name Executable -Value $exe -PropertyType String -Force | Out-Null
        New-ItemProperty -LiteralPath $classKey -Name CommandLine -Value $classCommandLine -PropertyType String -Force | Out-Null
        New-ItemProperty -LiteralPath $classKey -Name JobControl -Value 1 -PropertyType DWord -Force | Out-Null
    }
    if (-not (Test-Task)) {
        $action = New-ScheduledTaskAction -Execute $powershell -Argument (Get-TaskArguments)
        $principal = New-ScheduledTaskPrincipal -UserId 'S-1-5-18' -LogonType ServiceAccount -RunLevel Highest
        $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit (New-TimeSpan -Minutes 10)
        Register-ScheduledTask -TaskName $taskName -TaskPath '\' -Action $action -Trigger (New-ScheduledTaskTrigger -AtStartup) `
            -Principal $principal -Settings $settings -Force | Out-Null
    }
    if ("$((Get-Service -Name 'WinFsp.Launcher').Status)" -ne 'Running') { Start-Service -Name 'WinFsp.Launcher' }
    Start-ScheduledTask -TaskName $taskName -TaskPath '\'
    Set-Content -LiteralPath $attachedFile -Value $attached
}

$where = if ($served.Count -gt 0) { 'VirtioFsSvc logs to the Application event log' } else { "launcher results are in $log" }
$deadline = (Get-Date).AddMinutes(2)
while (-not (Test-InPlace)) {
    if ((Get-Date) -gt $deadline) { throw "the shares did not mount within two minutes; $where" }
    Start-Sleep -Seconds 2
}
