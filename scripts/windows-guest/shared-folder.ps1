param(
    [Parameter(Mandatory = $true)] [string] $ManifestPath,
    [ValidateSet('Probe', 'Apply')] [string] $Mode = 'Probe'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$staging = Split-Path -Parent $ManifestPath
$root = Split-Path -Parent $staging
$manifest = Get-Content -LiteralPath $ManifestPath -Raw | ConvertFrom-Json
$settingsPath = 'HKLM:\SOFTWARE\VirtIO-FS'
$statePath = 'HKLM:\SOFTWARE\NixOS\VirtioFS'
$executable = Join-Path $root 'bin\virtiofs.exe'
# Selecting a tag through arguments bypasses virtiofs's registry mount settings.
$binaryPath = '"' + $executable + '" -t transfer -m T: -F VirtIO-FS'
$bootTime = (Get-CimInstance Win32_OperatingSystem).LastBootUpTime.ToString('o')
$mutex = New-Object System.Threading.Mutex($false, 'Global\NixOSVirtioFSProvisioning')
$locked = $false

function Get-RegistryValue([string] $Path, [string] $Name) {
    if (Test-Path -LiteralPath $Path) {
        $key = Get-Item -LiteralPath $Path
        return $key.GetValue($Name, $null)
    }
    return $null
}

function Test-Hash([string] $Path, [string] $Expected) {
    return (Test-Path -LiteralPath $Path -PathType Leaf) -and
        ((Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash -eq $Expected)
}

function Test-WinFsp {
    $uninstall = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    $products = @(Get-ChildItem -LiteralPath $uninstall | Get-ItemProperty |
        Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'WinFsp*' })
    $installDir = Get-RegistryValue 'HKLM:\SOFTWARE\WOW6432Node\WinFsp' 'InstallDir'
    return (@($products | Where-Object { $_.DisplayVersion -eq $manifest.winfsp_version }).Count -gt 0) -and
        $installDir -and (Test-Path -LiteralPath (Join-Path $installDir 'bin\winfsp-x64.dll'))
}

function Test-Driver {
    $driver = Get-CimInstance Win32_SystemDriver -Filter "Name='VirtioFsDrv'"
    if (-not $driver) { return $false }
    $path = [Environment]::ExpandEnvironmentVariables($driver.PathName.Trim('"'))
    if ($path.StartsWith('\??\')) { $path = $path.Substring(4) }
    $path = $path -replace '^\\SystemRoot', $env:SystemRoot
    return Test-Hash $path $manifest.hashes.'viofs.sys'
}

function Get-Mount {
    return Get-CimInstance Win32_LogicalDisk -Filter "DeviceID='T:'"
}

function Test-Settings {
    return (Get-RegistryValue $settingsPath 'MountPoint') -eq 'T:' -and
        (Get-RegistryValue $settingsPath 'FileSystemName') -eq 'VirtIO-FS' -and
        $null -eq (Get-RegistryValue $settingsPath 'Owner')
}

function Test-Service {
    $service = Get-CimInstance Win32_Service -Filter "Name='VirtioFsSvc'"
    $dependencies = @(Get-RegistryValue 'HKLM:\SYSTEM\CurrentControlSet\Services\VirtioFsSvc' 'DependOnService')
    return $service -and $service.PathName -eq $binaryPath -and
        $service.StartMode -eq 'Auto' -and $service.StartName -eq 'LocalSystem' -and
        $service.State -eq 'Running' -and $dependencies -contains 'VirtioFsDrv'
}

function Test-Ready {
    $mount = Get-Mount
    return (Test-WinFsp) -and (Test-Driver) -and
        (Test-Hash $executable $manifest.hashes.'virtiofs.exe') -and
        (Test-Settings) -and (Test-Service) -and $mount -and
        $mount.FileSystem -eq 'VirtIO-FS' -and (Test-Path -LiteralPath 'T:\')
}

function Invoke-Installer([string] $Path, [string[]] $Arguments) {
    $process = Start-Process -FilePath $Path -ArgumentList $Arguments -Wait -PassThru -NoNewWindow
    if ($process.ExitCode -eq 3010) {
        $null = New-Item -Path $statePath -Force
        $null = New-ItemProperty -Path $statePath -Name 'PendingRebootBootTime' -Value $bootTime -PropertyType String -Force
        throw 'Windows filesystem installation needs a guest restart; no restart was requested automatically.'
    }
    if ($process.ExitCode -ne 0) {
        throw "Installer $Path failed with exit code $($process.ExitCode)."
    }
}

try {
    $locked = $mutex.WaitOne(0)
    if (-not $locked) { throw 'Another Windows filesystem provisioning process is still running.' }
    if ((Get-RegistryValue $statePath 'PendingRebootBootTime') -eq $bootTime) {
        throw 'Windows filesystem installation is waiting for a guest restart.'
    }
    $mount = Get-Mount
    if ($mount -and $mount.FileSystem -ne 'VirtIO-FS') {
        throw "Drive T: is occupied by $($mount.FileSystem); free that drive letter before provisioning."
    }
    if (Test-Ready) {
        [Console]::WriteLine('Windows filesystem ready: VirtioFsSvc is automatic and running, and T: is mounted.')
        exit 0
    }
    if ($Mode -eq 'Probe') {
        [Console]::WriteLine('WinFsp, the VirtIO filesystem driver, service or mount differs from the declaration.')
        exit 10
    }
    foreach ($file in $manifest.hashes.PSObject.Properties) {
        if (-not (Test-Hash (Join-Path $staging $file.Name) $file.Value)) {
            throw "Payload hash mismatch: $($file.Name)."
        }
    }
    $service = Get-CimInstance Win32_Service -Filter "Name='VirtioFsSvc'"
    if ($service -and $service.State -ne 'Stopped') {
        Stop-Service -Name VirtioFsSvc
        (Get-Service VirtioFsSvc).WaitForStatus('Stopped', [TimeSpan]::FromSeconds(30))
    }
    if (-not (Test-WinFsp)) {
        Invoke-Installer (Join-Path $env:SystemRoot 'System32\msiexec.exe') @(
            '/i', ('"' + (Join-Path $staging 'winfsp.msi') + '"'), '/qn', '/norestart',
            'ADDLOCAL=F.Main,F.User', 'REBOOT=ReallySuppress',
            '/l*v', ('"' + (Join-Path $root 'winfsp-install.log') + '"')
        )
        if (-not (Test-WinFsp)) { throw 'WinFsp Core installation did not match the pinned version.' }
    }
    if (-not (Test-Driver)) {
        Invoke-Installer (Join-Path $env:SystemRoot 'System32\pnputil.exe') @(
            '/add-driver', ('"' + (Join-Path $staging 'viofs.inf') + '"'), '/install'
        )
        if (-not (Test-Driver)) {
            throw 'Windows did not select the pinned VirtIO filesystem driver; inspect its driver ranking and restart requirements.'
        }
    }
    $null = New-Item -ItemType Directory -Path (Split-Path -Parent $executable) -Force
    if (-not (Test-Hash $executable $manifest.hashes.'virtiofs.exe')) {
        Copy-Item -LiteralPath (Join-Path $staging 'virtiofs.exe') -Destination $executable -Force
    }
    $null = New-Item -Path $settingsPath -Force
    $null = New-ItemProperty -Path $settingsPath -Name MountPoint -Value 'T:' -PropertyType String -Force
    $null = New-ItemProperty -Path $settingsPath -Name FileSystemName -Value 'VirtIO-FS' -PropertyType String -Force
    if ($null -ne (Get-RegistryValue $settingsPath 'Owner')) {
        Remove-ItemProperty -Path $settingsPath -Name Owner
    }
    if ($service) {
        $result = Invoke-CimMethod -InputObject $service -MethodName Change -Arguments @{
            PathName = $binaryPath
            StartMode = 'Automatic'
            StartName = 'LocalSystem'
            ServiceDependencies = [string[]] @('VirtioFsDrv')
        }
        if ($result.ReturnValue -ne 0) { throw "VirtioFsSvc configuration failed: $($result.ReturnValue)." }
    } else {
        $null = New-Service -Name VirtioFsSvc -BinaryPathName $binaryPath -StartupType Automatic -DependsOn VirtioFsDrv
    }
    Start-Service -Name VirtioFsSvc
    (Get-Service VirtioFsSvc).WaitForStatus('Running', [TimeSpan]::FromSeconds(30))
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        if (Test-Ready) {
            [Console]::WriteLine('Windows filesystem ready: VirtioFsSvc is automatic and running, and T: is mounted.')
            exit 0
        }
        Start-Sleep -Seconds 1
    }
    throw 'VirtioFsSvc started, but the declared T: mount failed verification.'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
} finally {
    if ($locked) { $mutex.ReleaseMutex() }
    $mutex.Dispose()
}
