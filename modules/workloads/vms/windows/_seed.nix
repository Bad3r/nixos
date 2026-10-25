# The seed CD-ROM of one Windows guest: answer file, boot-critical virtio
# drivers, guest tools, the OpenSSH installer firstlogon.ps1 runs, and the
# WinFsp installer that virtiofs shares need.
{ lib, pkgs }:
{
  guestName,
  accountName,
  edition,
  locale,
  timeZone,
}:
let
  virtioWin = pkgs.virtio-win;

  openssh = pkgs.fetchurl {
    url = "https://github.com/PowerShell/Win32-OpenSSH/releases/download/10.4.0.0p1-Preview/OpenSSH-Win64-v10.4.0.0.msi";
    hash = "sha256-eI2GQ0ZKAetjZAov10b57SPRBrWpAaNfiNyM1A5Eask=";
  };

  winfsp = pkgs.fetchurl {
    url = "https://github.com/winfsp/winfsp/releases/download/v2.1/winfsp-2.1.25156.msi";
    hash = "sha256-Bzpw4A93Qj40vtmLhuYA3vkzk7pYIiBPrFeikyTbn3o=";
  };

  answerFile = pkgs.writeText "autounattend.xml" (
    import ./_autounattend.nix { inherit lib; } {
      computerName = guestName;
      inherit
        accountName
        edition
        locale
        timeZone
        ;
      # The first file system root holding firstlogon.ps1 is the seed.
      firstLogonCommand = ''powershell.exe -NoProfile -NonInteractive -ExecutionPolicy Bypass -Command "& (Get-PSDrive -PSProvider FileSystem | ForEach-Object { Join-Path $_.Root 'firstlogon.ps1' } | Where-Object { Test-Path $_ } | Select-Object -First 1)"'';
    }
  );

  # Storage for virtio-blk and virtio-scsi disks, and the network adapter.
  drivers = [
    "viostor"
    "vioscsi"
    "NetKVM"
  ];
in
pkgs.runCommand "${guestName}-seed.iso"
  {
    nativeBuildInputs = [
      pkgs.libxml2
      pkgs.xorriso
    ];
  }
  ''
    xmllint --noout ${answerFile}
    mkdir tree
    cp ${answerFile} tree/autounattend.xml
    ${lib.concatMapStrings (driver: ''
      mkdir -p 'tree/$WinPEDriver$/${driver}'
      find ${virtioWin}/${driver}/w11/amd64 -maxdepth 1 -type f ! -name '*.pdb' \
        -exec cp -t 'tree/$WinPEDriver$/${driver}' {} +
    '') drivers}
    cp ${virtioWin}/virtio-win-guest-tools.exe tree/virtio-win-guest-tools.exe
    cp ${openssh} tree/OpenSSH-Win64.msi
    cp ${winfsp} tree/winfsp.msi
    cp ${./_firstlogon.ps1} tree/firstlogon.ps1
    find tree -exec touch -h -d "@$SOURCE_DATE_EPOCH" {} +
    xorriso -as mkisofs -iso-level 3 -volid XSEED -joliet -joliet-long -rational-rock \
      -output "$out" tree
  ''
