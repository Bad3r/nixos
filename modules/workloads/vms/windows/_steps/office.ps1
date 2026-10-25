# Click-to-Run Office lists itself under Apps with OfficeClickToRun.exe as
# its uninstaller; the installer at $Data.path is deleted after it runs.
$uninstall = @(
    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
)

function Test-Installed {
    $entries = @(Get-ItemProperty -Path $uninstall | Where-Object {
            "$($_.UninstallString)" -like '*\OfficeClickToRun.exe*'
        })
    $entries.Count -gt 0
}

if ($Mode -eq 'probe') {
    if (Test-Installed) { exit 0 }
    exit 10
}
try {
    $process = Start-Process -FilePath $Data.path -PassThru
    # Without a cached handle, ExitCode stays empty after the process exits.
    $null = $process.Handle
    # The installer has no silent switch, and a window it keeps open in
    # session 0 never closes.
    if (-not $process.WaitForExit([int] $Data.timeout * 1000)) {
        Stop-Process -InputObject $process -Force
        $process.WaitForExit()
        if (-not (Test-Installed)) {
            throw "$($Data.path) ran longer than $($Data.timeout) s without installing Office"
        }
        Write-Output "stopped the installer after $($Data.timeout) s with Office installed"
    }
    elseif ($process.ExitCode -ne 0) {
        throw "$($Data.path) exited with $($process.ExitCode)"
    }
}
finally {
    Remove-Item -LiteralPath $Data.path -Force
}
