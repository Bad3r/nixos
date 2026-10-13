param([ValidateSet('Probe', 'Apply')] [string] $Mode = 'Probe')

$ErrorActionPreference = 'Stop'
$ruleName = 'NixOS-Guest-Services-TCP-8000-9999'
$displayName = 'NixOS guest services TCP 8000-9999'
$description = 'Managed by the NixOS Windows guest provisioner.'
$remoteAddress = '10.11.11.0/24'
$localPort = '8000-9999'

function Test-SingleValue([object[]] $Values, [string] $Expected) {
    $actual = @($Values | ForEach-Object { [string] $_ })
    return $actual.Count -eq 1 -and $actual[0] -eq $Expected
}

function Get-GuestServicesRule {
    try {
        $rules = @(Get-NetFirewallRule -Name $ruleName -PolicyStore PersistentStore)
    } catch {
        # Windows reports an unmatched -Name as ObjectNotFound instead of an empty result.
        if ($_.CategoryInfo.Category -ne 'ObjectNotFound') { throw }
        $rules = @()
    }
    if ($rules.Count -gt 1) {
        throw "Multiple persistent firewall rules use the managed name '$ruleName'."
    }
    return $rules
}

function Test-GuestServicesRule {
    $rules = @(Get-GuestServicesRule)
    if ($rules.Count -ne 1) { return $false }
    $rule = $rules[0]
    $portFilters = @(Get-NetFirewallPortFilter -AssociatedNetFirewallRule $rule -PolicyStore PersistentStore)
    $addressFilters = @(Get-NetFirewallAddressFilter -AssociatedNetFirewallRule $rule -PolicyStore PersistentStore)
    if ($portFilters.Count -ne 1 -or $addressFilters.Count -ne 1) { return $false }
    $portFilter = $portFilters[0]
    $addressFilter = $addressFilters[0]

    return [string] $rule.DisplayName -eq $displayName -and
        [string] $rule.Description -eq $description -and
        [string] $rule.Direction -eq 'Inbound' -and
        [string] $rule.Action -eq 'Allow' -and
        [string] $rule.Enabled -eq 'True' -and
        [string] $rule.Profile -eq 'Any' -and
        [string] $portFilter.Protocol -eq 'TCP' -and
        (Test-SingleValue $portFilter.LocalPort $localPort) -and
        (Test-SingleValue $addressFilter.LocalAddress 'Any') -and
        (Test-SingleValue $addressFilter.RemoteAddress $remoteAddress)
}

if (Test-GuestServicesRule) {
    [Console]::WriteLine('Windows guest services firewall rule ready: TCP 8000-9999 from 10.11.11.0/24.')
    exit 0
}

if ($Mode -eq 'Probe') {
    [Console]::WriteLine('The managed Windows guest services firewall rule is missing or differs from policy.')
    exit 10
}

$rules = @(Get-GuestServicesRule)
if ($rules.Count -eq 1) {
    $null = $rules | Remove-NetFirewallRule
}
$null = New-NetFirewallRule `
    -PolicyStore PersistentStore `
    -Name $ruleName `
    -DisplayName $displayName `
    -Description $description `
    -Direction Inbound `
    -Action Allow `
    -Enabled True `
    -Profile Any `
    -Protocol TCP `
    -LocalAddress Any `
    -LocalPort $localPort `
    -RemoteAddress $remoteAddress

if (-not (Test-GuestServicesRule)) {
    throw 'The Windows guest services firewall rule did not converge to policy.'
}
[Console]::WriteLine('Windows guest services firewall rule ready: TCP 8000-9999 from 10.11.11.0/24.')
exit 0
