$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
Set-StrictMode -Version Latest

try {
    $shell = New-Object -ComObject Shell.Application
    $quickAccess = $shell.NameSpace('shell:::{679f85cb-0220-4080-b29b-5540cc05aab6}')
    if (-not $quickAccess) { throw 'File Explorer Quick access is unavailable in this user session.' }
    for ($attempt = 0; $attempt -lt 60; $attempt++) {
        if (Test-Path -LiteralPath 'T:\') { break }
        Start-Sleep -Seconds 1
    }
    if (-not (Test-Path -LiteralPath 'T:\')) { throw 'The Windows transfer drive did not mount before pinning.' }
    $present = @($quickAccess.Items() | Where-Object { $_.Path.TrimEnd('\') -eq 'T:' })
    if ($present.Count -gt 0) { exit 0 }
    $folder = $shell.NameSpace('T:\')
    if (-not $folder) { throw 'File Explorer cannot open the Windows transfer drive.' }
    $folder.Self.InvokeVerb('pintohome')
    for ($attempt = 0; $attempt -lt 30; $attempt++) {
        $present = @($quickAccess.Items() | Where-Object { $_.Path.TrimEnd('\') -eq 'T:' })
        if ($present.Count -gt 0) { exit 0 }
        Start-Sleep -Seconds 1
    }
    throw 'The Windows transfer drive was not added to File Explorer Quick access.'
} catch {
    [Console]::Error.WriteLine($_.Exception.Message)
    exit 1
}
