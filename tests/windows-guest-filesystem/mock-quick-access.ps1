param([string] $ScriptPath, [string] $ManifestPath, [string] $Case)

$ErrorActionPreference = 'Stop'
$env:SystemRoot = 'C:\Windows'
$global:fixtureRoot = Split-Path -Parent (Split-Path -Parent $ManifestPath)
$null = New-PSDrive -Name C -PSProvider FileSystem -Root $global:fixtureRoot
$global:fixtureCase = $Case
$global:fixturePinned = $Case -eq 'ready'
$global:fixtureRegistered = $Case -ne 'new'
$global:fixtureEnabled = $Case -ne 'disabled'
$global:fixtureLastRun = [DateTime]::MinValue
$global:fixtureRunning = $Case -eq 'already-running'
if ($global:fixtureRunning) { $global:fixtureLastRun = [DateTime]::Now.AddSeconds(-20) }
$global:fixtureCommand = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$global:fixtureArguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + (Join-Path $global:fixtureRoot 'bin\pin-quick-access.ps1') + '"'

function New-Object([string] $ComObject) {
    $shell = [pscustomobject] @{}
    return $shell | Add-Member -MemberType ScriptMethod -Name NameSpace -Value {
        param($Path)
        if ($Path -like 'shell:*') {
            $quickAccess = [pscustomobject] @{}
            return $quickAccess | Add-Member -MemberType ScriptMethod -Name Items -Value {
                if ($global:fixturePinned) { return [pscustomobject] @{ Path = 'T:\' } }
            } -PassThru
        }
        $item = [pscustomobject] @{}
        $null = $item | Add-Member -MemberType ScriptMethod -Name InvokeVerb -Value {
            param($Verb)
            if ($Verb -ne 'pintohome' -or $global:fixturePinned) { throw 'Pinning toggled an existing entry.' }
            [Console]::WriteLine('pin invoked')
            if ($global:fixtureCase -ne 'pin-failure') { $global:fixturePinned = $true }
        }
        return [pscustomobject] @{ Self = $item }
    } -PassThru
}
function Test-Path($LiteralPath, $PathType) { return $true }
function Get-FileHash($LiteralPath, $Algorithm) {
    $hash = if ($global:fixtureCase -eq 'bad-hash') { 'corrupt' } else { 'pin-quick-access.ps1' }
    return [pscustomobject] @{ Hash = $hash }
}
function New-Item { }
function Copy-Item { }
function Start-Sleep { }
function Get-ScheduledTask($TaskPath) {
    if (-not $global:fixtureRegistered) { return }
    return [pscustomobject] @{
        TaskName = 'NixOS Outlook Quick Access'
        State = $(if ($global:fixtureRunning) { 'Running' } else { 'Ready' })
        Principal = [pscustomobject] @{ GroupId = 'S-1-5-32-545'; LogonType = 4; RunLevel = 0 }
        Actions = @([pscustomobject] @{ Execute = $global:fixtureCommand; Arguments = $global:fixtureArguments })
        Triggers = @([pscustomobject] @{ CimClass = [pscustomobject] @{ CimClassName = 'MSFT_TaskLogonTrigger' }; Enabled = $true; Delay = 'PT30S' })
        Settings = [pscustomobject] @{ Enabled = $global:fixtureEnabled; StartWhenAvailable = $true; ExecutionTimeLimit = 'PT3M'; MultipleInstances = 2; DisallowStartIfOnBatteries = $false; StopIfGoingOnBatteries = $false }
    }
}
function New-ScheduledTaskAction($Execute, $Argument) { return [pscustomobject] @{ Execute = $Execute; Arguments = $Argument } }
function New-ScheduledTaskTrigger([switch] $AtLogOn) { return [pscustomobject] @{ Delay = '' } }
function New-ScheduledTaskPrincipal($GroupId, $RunLevel) {
    if ($GroupId -ne 'S-1-5-32-545' -or $RunLevel -ne 'Limited') { throw 'Task must use interactive Users with limited privileges.' }
    return [pscustomobject] @{}
}
function New-ScheduledTaskSettingsSet { return [pscustomobject] @{} }
function Register-ScheduledTask($TaskName, $Action, $Trigger, $Principal, $Settings, [switch] $Force) {
    if ($TaskName -ne 'NixOS Outlook Quick Access' -or $Trigger.Delay -ne 'PT30S') { throw 'Incorrect logon task.' }
    $global:fixtureRegistered = $true
    $global:fixtureEnabled = $true
    [Console]::WriteLine('task registered')
}
function Get-CimInstance($ClassName, $Filter) {
    if ($global:fixtureCase -ne 'no-session') { return [pscustomobject] @{ SessionId = 1 } }
}
function Start-ScheduledTask($TaskName) {
    if ($global:fixtureCase -eq 'already-running') { throw 'An existing task must not be restarted.' }
    $global:fixtureLastRun = [DateTime]::Now
}
function Get-ScheduledTaskInfo($TaskName) {
    $global:fixtureRunning = $false
    $result = if ($global:fixtureCase -eq 'pin-failure') { 1 } else { 0 }
    return [pscustomobject] @{ LastRunTime = $global:fixtureLastRun; LastTaskResult = $result }
}

if ($ScriptPath -like '*pin-quick-access.ps1') { & $ScriptPath } else { & $ScriptPath -ManifestPath $ManifestPath }
exit $LASTEXITCODE
