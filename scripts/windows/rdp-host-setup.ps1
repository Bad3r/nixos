<#
.SYNOPSIS
  Configures a Windows 10/11 host as a Remote Desktop target for Remmina/FreeRDP over the Cloudflare WARP Mesh.

.DESCRIPTION
  Applies, or with -Check only reports, the host-side settings for AVC444 Remote Desktop,
  RemoteApp, OpenSSH, and WinRM. Group Policy settings go into the local machine policy
  (Registry.pol, the file gpedit.msc edits), so they show in gpedit and survive policy refreshes.
  Every step is idempotent; a second run changes nothing. Exits 1 when any setting drifts.

.PARAMETER Check
  Report the state of every setting without changing anything.

.PARAMETER MeshRange
  Remote address range allowed to reach sshd and WinRM.

.PARAMETER AuthorizedKey
  OpenSSH public key lines added to administrators_authorized_keys.

.PARAMETER SkipSsh
  Leave OpenSSH untouched.

.PARAMETER SkipWinRM
  Leave WinRM untouched.

.EXAMPLE
  .\rdp-host-setup.ps1 -Check

.EXAMPLE
  .\rdp-host-setup.ps1 -AuthorizedKey (Get-Content .\id_ed25519.pub)
#>
[CmdletBinding()]
param(
  [switch]$Check,
  [string]$MeshRange = '100.96.0.0/12',
  [string[]]$AuthorizedKey = @(),
  [switch]$SkipSsh,
  [switch]$SkipWinRM
)

Set-StrictMode -Version 3
$ErrorActionPreference = 'Stop'

$identity = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
if (-not $identity.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  throw 'Run from an elevated PowerShell.'
}

$TsPolicyKey = 'SOFTWARE\Policies\Microsoft\Windows NT\Terminal Services'

# Local machine policy under Computer Configuration > Administrative Templates >
# Windows Components > Remote Desktop Services > Remote Desktop Session Host.
$Policies = [ordered]@{
  # Connections > Allow users to connect remotely by using Remote Desktop Services: Enabled
  fDenyTSConnections               = 0
  # Security > Require user authentication for remote connections by using NLA: Enabled
  UserAuthentication               = 1
  # Remote Session Environment > Prioritize H.264/AVC 444 graphics mode: Enabled
  AVC444ModePreferred              = 1
  # Remote Session Environment > Configure H.264/AVC hardware encoding: Disabled
  # (Enabled makes the AVC444 encoder fail with 0x80070057 and drop the session)
  AVCHardwareEncodePreferred       = 0
  # Remote Session Environment > Use hardware graphics adapters for all RDS sessions: Enabled
  bEnumerateHWBeforeSW             = 1
  # Remote Session Environment > Configure image quality for RemoteFX Adaptive Graphics: High
  # (Lossless restricts the server to lossless codecs, so H.264 never runs)
  ImageQuality                     = 2
  # Remote Session Environment > Configure RemoteFX Adaptive Graphics: Optimize for experience
  GraphicsProfile                  = 2
  # Remote Session Environment > Use advanced RemoteFX graphics for RemoteApp: Enabled
  fEnableRemoteFXAdvancedRemoteApp = 1
  # Remote Session Environment > Enable enhanced shell experience for RemoteApp: Enabled
  UseShellAppRuntimeRemoteApp      = 1
}

# Plain registry values with no Administrative Template on client editions.
$RegistryValues = @(
  # 60 fps frame cap (the default interval caps sessions at 30 fps)
  @{ Path = 'HKLM:\SYSTEM\CurrentControlSet\Control\Terminal Server\WinStations'; Name = 'DWMFRAMEINTERVAL'; Value = 15 }
  # Any installed program may start as a RemoteApp
  @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Terminal Server\TSAppAllowList'; Name = 'fDisabledAllowList'; Value = 1 }
  @{ Path = "HKLM:\$TsPolicyKey"; Name = 'fAllowUnlistedRemotePrograms'; Value = 1 }
)

$GpDir = Join-Path $env:windir 'System32\GroupPolicy'
$PolPath = Join-Path $GpDir 'Machine\Registry.pol'
$GptIni = Join-Path $GpDir 'gpt.ini'
$RegistryCse = '[{35378EAC-683F-11D2-A89A-00C04FBBCFA2}{D02B1F72-3407-48AE-BA88-E8213C6761F1}]'
$PRegSignature = [uint32]0x67655250
$SshRuleName = 'OpenSSH-Server-In-TCP'
$WinRmRuleName = 'WinRM-HTTP-In-Mesh'
$script:Drift = 0

function Write-State([string]$Item, [string]$Want, [string]$Have) {
  $ok = $Want -eq $Have
  if (-not $ok) { $script:Drift++ }
  $tag = if ($ok) { 'OK' } else { 'DRIFT' }
  Write-Output ('{0,-5} {1}: want {2}, have {3}' -f $tag, $Item, $Want, $Have)
}

function Write-Change([string]$Message) { Write-Output "SET   $Message" }

# --- Registry.pol (PReg v1) ---------------------------------------------------

function Read-PRegString([byte[]]$Bytes, [ref]$Pos) {
  $start = $Pos.Value
  while ($Bytes[$Pos.Value] -ne 0 -or $Bytes[$Pos.Value + 1] -ne 0) { $Pos.Value += 2 }
  $text = [Text.Encoding]::Unicode.GetString($Bytes, $start, $Pos.Value - $start)
  $Pos.Value += 2
  $text
}

function Skip-PRegChar([byte[]]$Bytes, [ref]$Pos, [char]$Char) {
  if ([BitConverter]::ToChar($Bytes, $Pos.Value) -ne $Char) {
    throw "Registry.pol: expected '$Char' at byte $($Pos.Value)"
  }
  $Pos.Value += 2
}

function Read-PolicyFile([byte[]]$Bytes) {
  $entries = New-Object System.Collections.ArrayList
  if ($null -eq $Bytes) { return ,$entries }
  if ($Bytes.Length -lt 8 -or [BitConverter]::ToUInt32($Bytes, 0) -ne $PRegSignature -or [BitConverter]::ToUInt32($Bytes, 4) -ne 1) {
    throw "$PolPath is not a PReg version 1 file"
  }
  $pos = 8
  while ($pos -lt $Bytes.Length) {
    Skip-PRegChar $Bytes ([ref]$pos) '['
    $key = Read-PRegString $Bytes ([ref]$pos)
    Skip-PRegChar $Bytes ([ref]$pos) ';'
    $name = Read-PRegString $Bytes ([ref]$pos)
    Skip-PRegChar $Bytes ([ref]$pos) ';'
    $type = [BitConverter]::ToUInt32($Bytes, $pos); $pos += 4
    Skip-PRegChar $Bytes ([ref]$pos) ';'
    $size = [BitConverter]::ToUInt32($Bytes, $pos); $pos += 4
    Skip-PRegChar $Bytes ([ref]$pos) ';'
    $data = New-Object byte[] $size
    if ($size -gt 0) { [Array]::Copy($Bytes, $pos, $data, 0, $size) }
    $pos += $size
    Skip-PRegChar $Bytes ([ref]$pos) ']'
    [void]$entries.Add([pscustomobject]@{ Key = $key; Name = $name; Type = $type; Data = $data })
  }
  ,$entries
}

function ConvertTo-PRegBytes($Entries) {
  $stream = New-Object IO.MemoryStream
  $writer = New-Object IO.BinaryWriter($stream)
  $unicode = [Text.Encoding]::Unicode
  $writer.Write($PRegSignature)
  $writer.Write([uint32]1)
  foreach ($entry in $Entries) {
    $writer.Write($unicode.GetBytes('[' + $entry.Key + [char]0 + ';' + $entry.Name + [char]0 + ';'))
    $writer.Write([uint32]$entry.Type)
    $writer.Write($unicode.GetBytes(';'))
    $writer.Write([uint32]$entry.Data.Length)
    $writer.Write($unicode.GetBytes(';'))
    $writer.Write([byte[]]$entry.Data)
    $writer.Write($unicode.GetBytes(']'))
  }
  $writer.Flush()
  ,$stream.ToArray()
}

function Get-PolicyDword($Entries, [string]$Name) {
  $hit = @($Entries | Where-Object { $_.Key -ieq $TsPolicyKey -and $_.Name -ieq $Name })
  if ($hit.Count -eq 1 -and $hit[0].Type -eq 4 -and $hit[0].Data.Length -eq 4) {
    return [string][BitConverter]::ToUInt32($hit[0].Data, 0)
  }
  if ($hit.Count -gt 1) { return '<duplicate>' }
  '<unset>'
}

function Update-GptIni {
  if (-not (Test-Path $GptIni)) {
    Set-Content -Path $GptIni -Encoding ASCII -Value @('[General]', "gPCMachineExtensionNames=$RegistryCse", 'Version=1')
    return
  }
  $lines = [Collections.Generic.List[string]]@(Get-Content -Path $GptIni)
  $versionIndex = -1
  $extIndex = -1
  for ($n = 0; $n -lt $lines.Count; $n++) {
    if ($lines[$n] -match '^Version=') { $versionIndex = $n }
    if ($lines[$n] -match '^gPCMachineExtensionNames=') { $extIndex = $n }
  }
  # The low word counts machine policy revisions, the high word user policy revisions.
  $version = if ($versionIndex -ge 0) { [int64]($lines[$versionIndex] -replace '^Version=', '') } else { 0 }
  $machine = (($version -band 0xFFFF) + 1) -band 0xFFFF
  $newVersion = ($version -band 0xFFFF0000) + $machine
  if ($versionIndex -ge 0) { $lines[$versionIndex] = "Version=$newVersion" } else { $lines.Add("Version=$newVersion") }
  if ($extIndex -lt 0) {
    $lines.Insert([Math]::Min(1, $lines.Count), "gPCMachineExtensionNames=$RegistryCse")
  } elseif ($lines[$extIndex] -notmatch '35378EAC-683F-11D2-A89A-00C04FBBCFA2') {
    $groups = @([regex]::Matches($lines[$extIndex], '\[[^\]]*\]') | ForEach-Object { $_.Value }) + $RegistryCse
    $lines[$extIndex] = 'gPCMachineExtensionNames=' + (($groups | Sort-Object) -join '')
  }
  Set-Content -Path $GptIni -Encoding ASCII -Value $lines
}

function Set-LocalMachinePolicy {
  $before = if (Test-Path $PolPath) { [IO.File]::ReadAllBytes($PolPath) } else { $null }
  $entries = Read-PolicyFile $before
  if ($null -ne $before) {
    $roundTrip = ConvertTo-PRegBytes $entries
    if ([Convert]::ToBase64String($roundTrip) -ne [Convert]::ToBase64String($before)) {
      throw "$PolPath does not round-trip through the parser; leaving it unchanged"
    }
  }
  foreach ($name in $Policies.Keys) {
    $want = [uint32]$Policies[$name]
    $have = Get-PolicyDword $entries $name
    if ($have -eq [string]$want) { continue }
    $stale = @($entries | Where-Object { $_.Key -ieq $TsPolicyKey -and ($_.Name -ieq $name -or $_.Name -ieq "**del.$name") })
    foreach ($entry in $stale) { [void]$entries.Remove($entry) }
    [void]$entries.Add([pscustomobject]@{ Key = $TsPolicyKey; Name = $name; Type = 4; Data = [BitConverter]::GetBytes($want) })
    Write-Change "policy $name = $want (was $have)"
  }
  $after = ConvertTo-PRegBytes $entries
  if ($null -ne $before -and [Convert]::ToBase64String($after) -eq [Convert]::ToBase64String($before)) { return $false }
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  if ($null -ne $before) { Copy-Item -Path $PolPath -Destination "$PolPath.bak-$stamp" }
  if (Test-Path $GptIni) { Copy-Item -Path $GptIni -Destination "$GptIni.bak-$stamp" }
  $machineDir = Split-Path $PolPath
  if (-not (Test-Path $machineDir)) { New-Item -ItemType Directory -Path $machineDir | Out-Null }
  [IO.File]::WriteAllBytes($PolPath, $after)
  Update-GptIni
  Write-Change "wrote $PolPath (backup suffix .bak-$stamp)"
  $true
}

# --- helpers --------------------------------------------------------------------

function Get-RegValue([string]$Path, [string]$Name) {
  $item = Get-ItemProperty -Path $Path -Name $Name -ErrorAction SilentlyContinue
  if ($null -eq $item) { return '<unset>' }
  [string]$item.$Name
}

function Set-RegDword([string]$Path, [string]$Name, [int]$Value) {
  # New-Item only on a missing key: on an existing key -Force recreates it empty.
  if (-not (Test-Path $Path)) { New-Item -Path $Path -Force | Out-Null }
  if ((Get-RegValue $Path $Name) -ne [string]$Value) {
    New-ItemProperty -Path $Path -Name $Name -PropertyType DWord -Value $Value -Force | Out-Null
    Write-Change "$Path\$Name = $Value"
  }
}

function ConvertTo-MaskNotation([string]$Cidr) {
  $address, $bits = $Cidr -split '/'
  if ($null -eq $bits) { return $Cidr }
  $mask = [uint32]0
  for ($b = 0; $b -lt [int]$bits; $b++) { $mask = $mask -bor ([uint32]1 -shl (31 - $b)) }
  $octets = [BitConverter]::GetBytes($mask)
  [Array]::Reverse($octets)
  "$address/" + ($octets -join '.')
}

function Get-RuleState([string]$Name) {
  $rule = Get-NetFirewallRule -Name $Name -ErrorAction SilentlyContinue
  if ($null -eq $rule) { return '<missing>' }
  $address = ($rule | Get-NetFirewallAddressFilter).RemoteAddress -join ','
  $port = ($rule | Get-NetFirewallPortFilter).LocalPort -join ','
  "enabled=$($rule.Enabled) profile=$($rule.Profile) remote=$address port=$port"
}

function Set-MeshRule([string]$Name, [string]$DisplayName, [int]$Port) {
  $want = "enabled=True profile=Any remote=$(ConvertTo-MaskNotation $MeshRange) port=$Port"
  if ((Get-RuleState $Name) -eq $want) { return }
  if (Get-NetFirewallRule -Name $Name -ErrorAction SilentlyContinue) {
    Set-NetFirewallRule -Name $Name -Enabled True -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -Profile Any -RemoteAddress $MeshRange
  } else {
    New-NetFirewallRule -Name $Name -DisplayName $DisplayName -Enabled True -Direction Inbound -Action Allow -Protocol TCP -LocalPort $Port -Profile Any -RemoteAddress $MeshRange | Out-Null
  }
  Write-Change "firewall rule $Name"
}

function Get-KeyId([string]$Line) { (($Line.Trim() -split '\s+') | Select-Object -First 2) -join ' ' }

$AdminKeysPath = Join-Path $env:ProgramData 'ssh\administrators_authorized_keys'

function Get-AdminKeyIds {
  if (-not (Test-Path $AdminKeysPath)) { return @() }
  @(Get-Content -Path $AdminKeysPath | Where-Object { $_ -match '\S' -and $_ -notmatch '^\s*#' } | ForEach-Object { Get-KeyId $_ })
}

function Test-WinRmListener {
  [bool](Get-ChildItem -Path WSMan:\localhost\Listener -ErrorAction SilentlyContinue | Where-Object { $_.Keys -contains 'Transport=HTTP' })
}

# --- apply ----------------------------------------------------------------------

if (-not $Check) {
  $policyChanged = Set-LocalMachinePolicy
  foreach ($name in $Policies.Keys) { Set-RegDword "HKLM:\$TsPolicyKey" $name $Policies[$name] }
  foreach ($value in $RegistryValues) { Set-RegDword $value.Path $value.Name $value.Value }

  if (-not $SkipSsh) {
    $capability = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
    if ($capability.State -ne 'Installed') {
      Add-WindowsCapability -Online -Name $capability.Name | Out-Null
      Write-Change "installed $($capability.Name)"
    }
    if ((Get-Service sshd).StartType -ne 'Automatic') { Set-Service -Name sshd -StartupType Automatic; Write-Change 'sshd startup = Automatic' }
    if ((Get-Service sshd).Status -ne 'Running') { Start-Service -Name sshd; Write-Change 'started sshd' }
    Set-MeshRule $SshRuleName 'OpenSSH SSH Server (sshd)' 22
    $known = Get-AdminKeyIds
    $missing = @($AuthorizedKey | Where-Object { $_ -match '\S' -and (Get-KeyId $_) -notin $known })
    if ($missing.Count -gt 0) {
      Add-Content -Path $AdminKeysPath -Value $missing -Encoding ASCII
      # sshd ignores the file unless only Administrators and SYSTEM can write it.
      icacls.exe $AdminKeysPath /inheritance:r /grant '*S-1-5-32-544:F' /grant '*S-1-5-18:F' | Out-Null
      Write-Change "added $($missing.Count) key(s) to $AdminKeysPath"
    }
  }

  if (-not $SkipWinRM) {
    if ((Get-Service WinRM).StartType -ne 'Automatic') { Set-Service -Name WinRM -StartupType Automatic; Write-Change 'WinRM startup = Automatic' }
    if ((Get-Service WinRM).Status -ne 'Running') { Start-Service -Name WinRM; Write-Change 'started WinRM' }
    if (-not (Test-WinRmListener)) { Enable-PSRemoting -SkipNetworkProfileCheck -Force | Out-Null; Write-Change 'enabled PowerShell remoting (HTTP listener)' }
    Set-MeshRule $WinRmRuleName 'Windows Remote Management (HTTP-In, Mesh)' 5985
  }

  if ($policyChanged) {
    # Domain policy errors make gpupdate report failure even when local policy applied.
    gpupdate.exe /target:computer /force | Out-Null
    Write-Change 'ran gpupdate /target:computer /force'
  }
}

# --- report ---------------------------------------------------------------------

$entries = Read-PolicyFile $(if (Test-Path $PolPath) { [IO.File]::ReadAllBytes($PolPath) } else { $null })
foreach ($name in $Policies.Keys) {
  Write-State "local policy $name" ([string]$Policies[$name]) (Get-PolicyDword $entries $name)
  # A domain GPO that sets the same value wins over local policy.
  Write-State "effective $name" ([string]$Policies[$name]) (Get-RegValue "HKLM:\$TsPolicyKey" $name)
}
foreach ($value in $RegistryValues) {
  Write-State "$($value.Path)\$($value.Name)" ([string]$value.Value) (Get-RegValue $value.Path $value.Name)
}

if (-not $SkipSsh) {
  $capability = Get-WindowsCapability -Online -Name 'OpenSSH.Server*' | Select-Object -First 1
  Write-State 'OpenSSH.Server capability' 'Installed' ([string]$capability.State)
  $sshd = Get-Service -Name sshd -ErrorAction SilentlyContinue
  Write-State 'sshd' 'Running/Automatic' $(if ($sshd) { "$($sshd.Status)/$($sshd.StartType)" } else { '<missing>' })
  Write-State "firewall $SshRuleName" "enabled=True profile=Any remote=$(ConvertTo-MaskNotation $MeshRange) port=22" (Get-RuleState $SshRuleName)
  $known = Get-AdminKeyIds
  foreach ($key in $AuthorizedKey | Where-Object { $_ -match '\S' }) {
    Write-State "admin key $((Get-KeyId $key).Substring(0, [Math]::Min(40, (Get-KeyId $key).Length)))..." 'present' $(if ((Get-KeyId $key) -in $known) { 'present' } else { 'missing' })
  }
}

if (-not $SkipWinRM) {
  $winrm = Get-Service -Name WinRM
  Write-State 'WinRM' 'Running/Automatic' "$($winrm.Status)/$($winrm.StartType)"
  Write-State 'WinRM HTTP listener' 'True' ([string](Test-WinRmListener))
  Write-State "firewall $WinRmRuleName" "enabled=True profile=Any remote=$(ConvertTo-MaskNotation $MeshRange) port=5985" (Get-RuleState $WinRmRuleName)
}

if ($script:Drift -gt 0) {
  Write-Output "$($script:Drift) setting(s) drift"
  exit 1
}
Write-Output 'all settings match'
