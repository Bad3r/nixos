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
# Task Scheduler reports 267011 for a task that never ran and 267009 while it runs.
$global:fixtureLastResult = switch ($Case) {
    'no-session' { 267011 }
    'trigger-race' { 267011 }
    'pin-failure' { 1 }
    'already-running' { 267009 }
    default { 0 }
}
$global:fixtureCopied = $false
$global:fixtureCommand = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$global:fixtureInstalledScript = Join-Path $global:fixtureRoot 'bin\pin-quick-access.ps1'
$global:fixtureArguments = '-NoProfile -NonInteractive -WindowStyle Hidden -ExecutionPolicy Bypass -File "' + $global:fixtureInstalledScript + '"'

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
    $hash = 'pin-quick-access.ps1'
    if ($global:fixtureCase -eq 'bad-hash') {
        $hash = 'corrupt'
    } elseif ($global:fixtureCase -eq 'script-changed' -and -not $global:fixtureCopied -and
        $LiteralPath -eq $global:fixtureInstalledScript) {
        $hash = 'previous-pin-quick-access.ps1'
    }
    return [pscustomobject] @{ Hash = $hash }
}
function New-Item { }
function Copy-Item {
    $global:fixtureCopied = $true
    [Console]::WriteLine('pin script replaced')
}
function Assert-RootTaskPath([string] $TaskPath) {
    if ($TaskPath -ne '\') { throw "Task cmdlets must name the root task folder, not '$TaskPath'." }
}
function Start-Sleep { }
function Get-ScheduledTask {
    [CmdletBinding()]
    param([string] $TaskPath, [string] $TaskName)
    Assert-RootTaskPath $TaskPath
    if (-not $global:fixtureRegistered) {
        # Windows reports a query that matches no task as an error, not as an empty result.
        Write-Error -Category ObjectNotFound -TargetObject $TaskName -ErrorId 'CmdletizationQuery_NotFound_TaskName' `
            -Message "No MSFT_ScheduledTask objects found with property 'TaskName' equal to '$TaskName'.  Verify the value of the property and retry."
        return
    }
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
function Register-ScheduledTask($TaskPath, $TaskName, $Action, $Trigger, $Principal, $Settings, [switch] $Force) {
    Assert-RootTaskPath $TaskPath
    if ($TaskName -ne 'NixOS Outlook Quick Access' -or $Trigger.Delay -ne 'PT30S') { throw 'Incorrect logon task.' }
    $global:fixtureRegistered = $true
    $global:fixtureEnabled = $true
    $global:fixtureLastResult = 267011
    [Console]::WriteLine('task registered')
}
function Get-CimInstance($ClassName, $Filter) {
    if ($global:fixtureCase -eq 'trigger-race') {
        # The logon trigger starts the task after the script's first state read, and the query
        # then takes long enough that a start time taken afterwards lies past that run's start.
        $global:fixtureRunning = $true
        $global:fixtureLastRun = [DateTime]::Now
        $global:fixtureLastResult = 267009
        [System.Threading.Thread]::Sleep(1500)
    }
    if ($global:fixtureCase -ne 'no-session') { return [pscustomobject] @{ SessionId = 1 } }
}
function Start-ScheduledTask($TaskPath, $TaskName) {
    Assert-RootTaskPath $TaskPath
    if ($global:fixtureCase -eq 'already-running') { throw 'An existing task must not be restarted.' }
    if ($global:fixtureRunning) {
        # MultipleInstances IgnoreNew: a start while the task runs changes nothing.
        [Console]::WriteLine('task start ignored')
        return
    }
    [Console]::WriteLine('task started')
    $global:fixtureLastRun = [DateTime]::Now
    $global:fixtureLastResult = if ($global:fixtureCase -eq 'pin-failure') { 1 } else { 0 }
}
function Get-ScheduledTaskInfo($TaskPath, $TaskName) {
    Assert-RootTaskPath $TaskPath
    $result = [pscustomobject] @{ LastRunTime = $global:fixtureLastRun; LastTaskResult = $global:fixtureLastResult }
    # A running task finishes, successfully, once its status has been read.
    if ($global:fixtureRunning) {
        $global:fixtureRunning = $false
        $global:fixtureLastResult = 0
    }
    return $result
}

if ($ScriptPath -like '*pin-quick-access.ps1') { & $ScriptPath } else { & $ScriptPath -ManifestPath $ManifestPath }
exit $LASTEXITCODE
