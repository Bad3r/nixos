param([string] $ScriptPath, [string] $Case, [string] $Mode)

$ErrorActionPreference = 'Stop'
$global:fixtureCase = $Case

function New-FixtureRule(
    [string] $Name,
    [string] $DisplayName,
    [string] $Description,
    [string] $Direction,
    [string] $Action,
    [string] $Enabled,
    [string] $Profile,
    [string] $Protocol,
    [string[]] $LocalPort,
    [string[]] $LocalAddress,
    [string[]] $RemoteAddress
) {
    return [pscustomobject] @{
        Name = $Name
        DisplayName = $DisplayName
        Description = $Description
        Direction = $Direction
        Action = $Action
        Enabled = $Enabled
        Profile = $Profile
        PortFilter = [pscustomobject] @{
            Protocol = $Protocol
            LocalPort = $LocalPort
        }
        AddressFilter = [pscustomobject] @{
            LocalAddress = $LocalAddress
            RemoteAddress = $RemoteAddress
        }
    }
}

$readyRule = New-FixtureRule `
    'NixOS-Guest-Services-TCP-8000-9999' `
    'NixOS guest services TCP 8000-9999' `
    'Managed by the NixOS Windows guest provisioner.' `
    'Inbound' 'Allow' 'True' 'Any' 'TCP' @('8000-9999') @('Any') @('10.11.11.0/24')
$staleRule = New-FixtureRule `
    'NixOS-Guest-Services-TCP-8000-9999' `
    'Old guest services rule' `
    'Managed by the NixOS Windows guest provisioner.' `
    'Inbound' 'Block' 'False' 'Private' 'UDP' @('8000') @('Any') @('10.0.0.0/8')
$global:fixtureRules = if ($Case -in @('ready')) { @($readyRule) } elseif ($Case -in @('stale', 'apply-failure')) { @($staleRule) } else { @() }

function Get-NetFirewallRule {
    [CmdletBinding()]
    param([string] $Name, [string] $PolicyStore)
    if ($PolicyStore -ne 'PersistentStore') { throw "Unexpected policy store $PolicyStore." }
    $rules = @($global:fixtureRules | Where-Object { $_.Name -eq $Name })
    if ($rules.Count -eq 0) {
        # Windows reports an unmatched -Name as an error, not as an empty result.
        Write-Error -Category ObjectNotFound -TargetObject $Name -ErrorId 'CmdletizationQuery_NotFound_InstanceID' `
            -Message "No MSFT_NetFirewallRule objects found with property 'InstanceID' equal to '$Name'.  Verify the value of the property and retry."
        return
    }
    return $rules
}

function Get-NetFirewallPortFilter {
    [CmdletBinding()]
    param([psobject] $AssociatedNetFirewallRule, [string] $PolicyStore)
    if ($PolicyStore -ne 'PersistentStore') { throw "Unexpected policy store $PolicyStore." }
    return $AssociatedNetFirewallRule.PortFilter
}

function Get-NetFirewallAddressFilter {
    [CmdletBinding()]
    param([psobject] $AssociatedNetFirewallRule, [string] $PolicyStore)
    if ($PolicyStore -ne 'PersistentStore') { throw "Unexpected policy store $PolicyStore." }
    return $AssociatedNetFirewallRule.AddressFilter
}

function Remove-NetFirewallRule {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true, ValueFromPipeline = $true)] [psobject] $InputObject)
    process {
        if ($global:fixtureCase -eq 'apply-failure') { throw 'fixture firewall operation failed.' }
        $global:fixtureRules = @($global:fixtureRules | Where-Object { $_.Name -ne $InputObject.Name })
        if ($global:fixtureCase -eq 'stale') {
            [Console]::WriteLine('fixture firewall rule replaced')
        }
    }
}

function New-NetFirewallRule {
    [CmdletBinding()]
    param(
        [string] $PolicyStore,
        [string] $Name,
        [string] $DisplayName,
        [string] $Description,
        [string] $Direction,
        [string] $Action,
        [string] $Enabled,
        [string] $Profile,
        [string] $Protocol,
        [string[]] $LocalAddress,
        [string[]] $LocalPort,
        [string[]] $RemoteAddress
    )
    if ($PolicyStore -ne 'PersistentStore' -or $Direction -ne 'Inbound' -or $Action -ne 'Allow' -or
        $Enabled -ne 'True' -or $Profile -ne 'Any' -or $Protocol -ne 'TCP' -or
        $LocalAddress -notcontains 'Any' -or $LocalPort -notcontains '8000-9999' -or
        $RemoteAddress -notcontains '10.11.11.0/24') {
        throw 'The new guest firewall rule differs from the policy.'
    }
    $global:fixtureRules = @((New-FixtureRule `
        $Name $DisplayName $Description $Direction $Action $Enabled $Profile $Protocol `
        $LocalPort $LocalAddress $RemoteAddress))
    if ($global:fixtureCase -eq 'missing') {
        [Console]::WriteLine('fixture firewall rule created')
    }
}

& $ScriptPath -Mode $Mode
exit $LASTEXITCODE
