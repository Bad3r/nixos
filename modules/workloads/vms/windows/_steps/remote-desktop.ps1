# Enables Remote Desktop and scopes the built-in firewall group to $Data.remote.
$remote = @($Data.remote | Sort-Object)
$key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server'
# The "Remote Desktop" group by its resource name, which no display language changes.
$group = '@FirewallAPI.dll,-28752'
$rules = @(Get-NetFirewallRule -Group $group)
if ($rules.Count -eq 0) { throw "no firewall rules in group $group" }

function Get-Remote($rule) {
    @(($rule | Get-NetFirewallAddressFilter).RemoteAddress | ForEach-Object {
            $_ -replace '/(32|255\.255\.255\.255)$', ''
        } | Sort-Object)
}

function Test-InPlace {
    if ((Get-ItemPropertyValue -Path $key -Name fDenyTSConnections) -ne 0) { return $false }
    foreach ($rule in $rules) {
        if ("$($rule.Enabled)" -ne 'True') { return $false }
        if ($null -ne (Compare-Object (Get-Remote $rule) $remote)) { return $false }
    }
    $true
}

if ($Mode -eq 'probe') {
    if (Test-InPlace) { exit 0 }
    exit 10
}
Set-ItemProperty -Path $key -Name fDenyTSConnections -Value 0 -Type DWord
$rules | Set-NetFirewallRule -RemoteAddress $remote -Enabled True
