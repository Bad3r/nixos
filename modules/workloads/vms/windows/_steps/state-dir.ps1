# $Data.path holds installers that run as SYSTEM: it and everything in it
# belong to Administrators, and only SYSTEM and Administrators hold access.
$path = $Data.path
$wanted = @('S-1-5-18', 'S-1-5-32-544')

function Get-Sid($identity) {
    $identity.Translate([System.Security.Principal.SecurityIdentifier]).Value
}

function Test-Item($item, [bool] $root) {
    $acl = Get-Acl -LiteralPath $item
    if ((Get-Sid ([System.Security.Principal.NTAccount] $acl.Owner)) -notin $wanted) { return $false }
    if ($root -and -not $acl.AreAccessRulesProtected) { return $false }
    $rules = @($acl.Access)
    $foreign = @($rules | Where-Object {
            (Get-Sid $_.IdentityReference) -notin $wanted -or "$($_.AccessControlType)" -ne 'Allow' -or
            ($root -and ("$($_.FileSystemRights)" -ne 'FullControl' -or "$($_.InheritanceFlags)" -ne 'ContainerInherit, ObjectInherit'))
        })
    $rules.Count -gt 0 -and $foreign.Count -eq 0
}

function Test-Tree {
    if (-not (Test-Item $path $true)) { return $false }
    foreach ($child in @(Get-ChildItem -LiteralPath $path -Recurse -Force)) {
        if (-not (Test-Item $child.FullName $false)) { return $false }
    }
    $true
}

function Invoke-Icacls([string[]] $arguments) {
    & icacls.exe @arguments | Out-Null
    if ($LASTEXITCODE -ne 0) { throw "icacls $arguments exited with $LASTEXITCODE" }
}

if ($Mode -eq 'probe') {
    if (Test-Tree) { exit 0 }
    exit 10
}
Invoke-Icacls @($path, '/setowner', '*S-1-5-32-544', '/T', '/C')
Invoke-Icacls @($path, '/inheritance:r', '/grant:r', '*S-1-5-18:(OI)(CI)F', '*S-1-5-32-544:(OI)(CI)F')
if (@(Get-ChildItem -LiteralPath $path -Force).Count -gt 0) {
    Invoke-Icacls @((Join-Path $path '*'), '/reset', '/T', '/C')
}
