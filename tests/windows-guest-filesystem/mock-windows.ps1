param([string] $ScriptPath, [string] $ManifestPath, [string] $Case, [string] $Mode)

$ErrorActionPreference = 'Stop'
$env:SystemRoot = 'C:\Windows'
$global:fixtureRoot = Split-Path -Parent (Split-Path -Parent $ManifestPath)
$null = New-PSDrive -Name C -PSProvider FileSystem -Root $global:fixtureRoot
$global:fixtureBinary = '"' + (Join-Path $global:fixtureRoot 'bin\virtiofs.exe') + '" -t transfer -m T: -F VirtIO-FS'
$global:fixtureCase = $Case
$global:fixtureInstalled = $Case -notin @('new', 'install-failure', 'reboot', 'bad-hash')
$global:fixtureDriverInstalled = $global:fixtureInstalled
$global:fixtureExeInstalled = $global:fixtureInstalled
$global:fixtureServiceExists = $global:fixtureInstalled
$global:fixtureServiceRunning = $global:fixtureInstalled
$global:fixtureOwnerOverride = $Case -eq 'owner'
$global:fixtureSettings = @{ MountPoint = 'T:'; FileSystemName = 'VirtIO-FS' }
$global:fixtureBootTime = [DateTime]::new(2026, 1, 1)

function Get-CimInstance($ClassName, $Filter) {
    switch ($ClassName) {
        'Win32_OperatingSystem' { return [pscustomobject] @{ LastBootUpTime = $global:fixtureBootTime } }
        'Win32_LogicalDisk' {
            if ($global:fixtureCase -eq 'collision') { return [pscustomobject] @{ FileSystem = 'NTFS' } }
            if ($global:fixtureServiceRunning) { return [pscustomobject] @{ FileSystem = 'VirtIO-FS' } }
            return $null
        }
        'Win32_SystemDriver' {
            if ($global:fixtureDriverInstalled) { return [pscustomobject] @{ PathName = '\SystemRoot\System32\DriverStore\viofs.sys' } }
            return $null
        }
        'Win32_Service' {
            if (-not $global:fixtureServiceExists) { return $null }
            $state = if ($global:fixtureServiceRunning) { 'Running' } else { 'Stopped' }
            return [pscustomobject] @{ PathName = $global:fixtureBinary; StartMode = 'Auto'; StartName = 'LocalSystem'; State = $state }
        }
        default { throw "Unexpected CIM class $ClassName." }
    }
}

function Test-Path($LiteralPath, $PathType) {
    if ($LiteralPath -eq (Join-Path $global:fixtureRoot 'bin\virtiofs.exe')) { return $global:fixtureExeInstalled }
    if ($LiteralPath -eq 'T:\') { return $global:fixtureServiceRunning }
    return $true
}

function Get-ChildItem($LiteralPath) {
    if ($global:fixtureInstalled) { return [pscustomobject] @{ DisplayName = 'WinFsp'; DisplayVersion = '2.1.25156' } }
}
function Get-ItemProperty { process { return $_ } }
function Get-FileHash($LiteralPath, $Algorithm) {
    $name = ($LiteralPath -split '[/\\]')[-1]
    if ($global:fixtureCase -eq 'bad-hash' -and $name -eq 'viofs.sys') { return [pscustomobject] @{ Hash = 'corrupt' } }
    return [pscustomobject] @{ Hash = $name }
}
function Get-Item($LiteralPath) {
    $key = [pscustomobject] @{ Path = $LiteralPath }
    return $key | Add-Member -MemberType ScriptMethod -Name GetValue -Value {
        param($Name, $Default)
        if ($this.Path -like '*WinFsp') { return $global:fixtureRoot }
        if ($this.Path -like '*Services\VirtioFsSvc') { return @('VirtioFsDrv') }
        if ($Name -eq 'PendingRebootBootTime') {
            if ($global:fixtureCase -eq 'pending-reboot') { return $global:fixtureBootTime.ToString('o') }
            return $null
        }
        if ($Name -eq 'Owner') {
            if ($global:fixtureOwnerOverride) { return '0:0' }
            return $null
        }
        return $global:fixtureSettings[$Name]
    } -PassThru
}
function New-Item { }
function New-ItemProperty($Path, $Name, $Value, $PropertyType, [switch] $Force) {
    if ($global:fixtureCase -eq 'ready') { throw 'A ready probe mutated the registry.' }
    if ($Name -eq 'PendingRebootBootTime') { [Console]::WriteLine($Name) }
    $global:fixtureSettings[$Name] = $Value
}
function Remove-ItemProperty($Path, $Name) {
    if ($Name -ne 'Owner') { throw "Unexpected removal $Name." }
    $global:fixtureOwnerOverride = $false
    [Console]::WriteLine('removed Owner')
}
function Start-Process($FilePath, $ArgumentList, [switch] $Wait, [switch] $PassThru, [switch] $NoNewWindow) {
    if ($global:fixtureCase -eq 'ready') { throw 'A ready probe ran an installer.' }
    if ($global:fixtureCase -eq 'install-failure') { return [pscustomobject] @{ ExitCode = 1618 } }
    if ($global:fixtureCase -eq 'reboot') { return [pscustomobject] @{ ExitCode = 3010 } }
    if ($FilePath -like '*msiexec.exe') {
        if ($ArgumentList -notcontains '/norestart' -or $ArgumentList -notcontains 'ADDLOCAL=F.Main,F.User') {
            throw 'MSI must select Core and suppress reboot.'
        }
        $global:fixtureInstalled = $true
    } elseif ($FilePath -like '*pnputil.exe') {
        if ($ArgumentList -contains '/reboot') { throw 'Driver setup requested an automatic reboot.' }
        $global:fixtureDriverInstalled = $true
    } else { throw "Unexpected installer $FilePath." }
    return [pscustomobject] @{ ExitCode = 0 }
}
function Stop-Service($Name) { $global:fixtureServiceRunning = $false }
function Get-Service($Name) {
    $service = [pscustomobject] @{}
    return $service | Add-Member -MemberType ScriptMethod -Name WaitForStatus -Value { param($State, $Timeout) } -PassThru
}
function Invoke-CimMethod($InputObject, $MethodName, $Arguments) {
    if ($Arguments.PathName -ne $global:fixtureBinary -or $Arguments.StartName -ne 'LocalSystem' -or
        $Arguments.StartMode -ne 'Automatic' -or $Arguments.ServiceDependencies -notcontains 'VirtioFsDrv') {
        throw 'Service configuration differs from the declaration.'
    }
    return [pscustomobject] @{ ReturnValue = 0 }
}
function New-Service($Name, $BinaryPathName, $StartupType, $DependsOn) {
    if ($BinaryPathName -ne $global:fixtureBinary -or $StartupType -ne 'Automatic' -or $DependsOn -ne 'VirtioFsDrv') {
        throw 'New service differs from the declaration.'
    }
    $global:fixtureServiceExists = $true
}
function Start-Service($Name) { $global:fixtureServiceRunning = $true }
function Copy-Item($LiteralPath, $Destination, [switch] $Force) { $global:fixtureExeInstalled = $true }
function Start-Sleep($Seconds) { throw 'Fixture did not converge after installation.' }
function Restart-Computer { throw 'Provisioning must not restart Windows.' }

& $ScriptPath -ManifestPath $ManifestPath -Mode $Mode
exit $LASTEXITCODE
