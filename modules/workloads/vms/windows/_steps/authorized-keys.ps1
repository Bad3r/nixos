# sshd ignores administrators_authorized_keys unless only SYSTEM and
# Administrators hold access to it.
$path = $Data.path
$wanted = @('S-1-5-18', 'S-1-5-32-544')

function Test-Acl {
    if (-not (Test-Path -LiteralPath $path)) { return $false }
    $acl = Get-Acl -LiteralPath $path
    if (-not $acl.AreAccessRulesProtected) { return $false }
    $sids = @($acl.Access | ForEach-Object {
            $_.IdentityReference.Translate([System.Security.Principal.SecurityIdentifier]).Value
        } | Sort-Object -Unique)
    $full = @($acl.Access | Where-Object { $_.FileSystemRights -ne 'FullControl' }).Count -eq 0
    $full -and ($null -eq (Compare-Object $sids $wanted))
}

if ($Mode -eq 'probe') {
    if (Test-Acl) { exit 0 }
    exit 10
}
& icacls.exe $path /inheritance:r /grant '*S-1-5-18:F' /grant '*S-1-5-32-544:F' | Out-Null
if ($LASTEXITCODE -ne 0) { throw "icacls exited with $LASTEXITCODE" }
