# Runs once from the seed CD-ROM at the autologon that ends Windows Setup.
# workloads-provision@<guest> waits for firstlogon.done before its steps and
# fails with the contents of firstlogon.failed.
$ErrorActionPreference = 'Stop'
$state = Join-Path $env:ProgramData 'workloads'
New-Item -ItemType Directory -Force -Path $state | Out-Null
Start-Transcript -Path (Join-Path $state 'firstlogon.log') -Append | Out-Null

function Invoke-Installer([string] $file, [string[]] $arguments) {
    $process = Start-Process -FilePath $file -ArgumentList $arguments -Wait -PassThru
    # 3010: installed; a reboot finishes it.
    if ($process.ExitCode -notin 0, 3010) {
        throw "$file $arguments exited with $($process.ExitCode)"
    }
}

function Invoke-Native([string] $file, [string[]] $arguments) {
    & $file @arguments
    if ($LASTEXITCODE -ne 0) {
        throw "$file $arguments exited with $LASTEXITCODE"
    }
}

try {
    Invoke-Installer (Join-Path $PSScriptRoot 'virtio-win-guest-tools.exe') @('/install', '/quiet', '/norestart')
    Invoke-Installer 'msiexec.exe' @('/i', "`"$(Join-Path $PSScriptRoot 'OpenSSH-Win64.msi')`"", '/qn', '/norestart')
    # The MSI opens port 22 to any address; provisioning opens it to the host only.
    $msiRule = Get-NetFirewallRule -DisplayName 'OpenSSH SSH Server Preview (sshd)' -ErrorAction SilentlyContinue
    if ($msiRule) { $msiRule | Remove-NetFirewallRule } else { Write-Output 'The OpenSSH MSI added no firewall rule.' }
    Set-Service -Name sshd -StartupType Automatic
    Start-Service -Name sshd

    # A sleeping guest sits in pmsuspended, and Fast Startup is a hibernation.
    Invoke-Native 'powercfg.exe' @('/hibernate', 'off')
    Set-ItemProperty -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Power' -Name HiberbootEnabled -Value 0 -Type DWord
    foreach ($setting in 'standby-timeout-ac', 'standby-timeout-dc', 'hibernate-timeout-ac', 'hibernate-timeout-dc') {
        Invoke-Native 'powercfg.exe' @('/change', $setting, '0')
    }

    Set-LocalUser -Name $env:USERNAME -PasswordNeverExpires $true
    Invoke-Native 'net.exe' @('accounts', '/maxpwage:unlimited')

    Set-Content -Path (Join-Path $state 'firstlogon.done') -Value ''
}
catch {
    Set-Content -Path (Join-Path $state 'firstlogon.failed') -Value ($_ | Out-String)
    throw
}
finally {
    Stop-Transcript | Out-Null
}
