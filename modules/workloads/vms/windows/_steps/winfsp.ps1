# WinFsp at $Data.version or newer, which virtiofs.exe runs on; apply checks
# the MSI the host copied to $Data.path against $Data.sha256, installs it, and
# deletes it.
$wanted = [version] $Data.version
$uninstall = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'

function Test-WinFsp {
    $versions = @(Get-ChildItem -LiteralPath $uninstall | Get-ItemProperty |
        Where-Object { $_.PSObject.Properties['DisplayName'] -and $_.DisplayName -like 'WinFsp*' } |
        ForEach-Object { [version] $_.DisplayVersion })
    @($versions | Where-Object { $_ -ge $wanted }).Count -gt 0 -and
    $null -ne (Get-Service -Name 'WinFsp.Launcher' -ErrorAction SilentlyContinue)
}

if ($Mode -eq 'probe') {
    if (Test-WinFsp) { exit 0 }
    exit 10
}
$log = Join-Path (Split-Path -Parent $Data.path) 'winfsp-install.log'
$hash = (Get-FileHash -LiteralPath $Data.path -Algorithm SHA256).Hash
if ($hash -ne $Data.sha256) {
    Remove-Item -LiteralPath $Data.path
    throw "the WinFsp MSI copy has SHA-256 $hash, not $($Data.sha256)"
}
$process = Start-Process -FilePath (Join-Path $env:SystemRoot 'System32\msiexec.exe') -Wait -PassThru -ArgumentList @(
    '/i', "`"$($Data.path)`"", '/qn', '/norestart', '/l*v', "`"$log`""
)
Remove-Item -LiteralPath $Data.path
# 3010: installed; a reboot finishes it.
if ($process.ExitCode -notin 0, 3010) {
    throw "msiexec exited with $($process.ExitCode); its log is $log"
}
