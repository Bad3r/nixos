# Inbound allow rules named workloads-<service>, each open to the guest's
# gateways only; workloads-* rules nothing declares are removed.
$prefix = 'workloads-'
$wanted = @{}
foreach ($rule in @($Data.rules)) { $wanted[$prefix + $rule.name] = $rule }
$present = @(Get-NetFirewallRule -Name "$prefix*" -ErrorAction SilentlyContinue)

function Test-Rule($existing, $rule) {
    $ports = $existing | Get-NetFirewallPortFilter
    $remote = @(($existing | Get-NetFirewallAddressFilter).RemoteAddress | ForEach-Object {
            $_ -replace '/(32|255\.255\.255\.255)$', ''
        })
    "$($existing.Enabled)" -eq 'True' -and
    "$($existing.Direction)" -eq 'Inbound' -and
    "$($existing.Action)" -eq 'Allow' -and
    "$($existing.Profile)" -eq 'Any' -and
    $ports.Protocol -eq $rule.protocol -and
    "$($ports.LocalPort)" -eq "$($rule.port)" -and
    $null -eq (Compare-Object @($remote | Sort-Object) @(@($rule.remote) | Sort-Object))
}

$stale = @($present | Where-Object { -not $wanted.ContainsKey($_.Name) -or -not (Test-Rule $_ $wanted[$_.Name]) })
$missing = @($wanted.Keys | Where-Object { $_ -notin @($present | ForEach-Object Name) })
if ($Mode -eq 'probe') {
    if ($stale.Count -eq 0 -and $missing.Count -eq 0) { exit 0 }
    exit 10
}
$stale | Remove-NetFirewallRule
foreach ($name in $wanted.Keys) {
    if (Get-NetFirewallRule -Name $name -ErrorAction SilentlyContinue) { continue }
    $rule = $wanted[$name]
    New-NetFirewallRule -Name $name -DisplayName $name -Direction Inbound -Action Allow -Profile Any `
        -Protocol $rule.protocol -LocalPort $rule.port -RemoteAddress @($rule.remote) | Out-Null
}
