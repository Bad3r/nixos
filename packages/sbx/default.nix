{
  lib,
  stdenvNoCC,
  writeText,
  python3,
  qemu_kvm,
  openssh,
  socat,
  tesseract,
  iproute2,
  git,
  systemd,
  nix,
  # Rendered by modules/apps/sbx/nixos.nix; the bare package refuses to run.
  settings ? { },
}:
let
  python = python3.withPackages (ps: [ ps.libvirt ]);
  tools = {
    emulator = "${qemu_kvm}/bin/qemu-system-x86_64";
    qemu_img = "${qemu_kvm}/bin/qemu-img";
    ssh = "${openssh}/bin/ssh";
    scp = "${openssh}/bin/scp";
    ssh_keygen = "${openssh}/bin/ssh-keygen";
    socat = lib.getExe socat;
    tesseract = lib.getExe tesseract;
    ss = "${iproute2}/bin/ss";
    git = lib.getExe git;
    systemctl = "${systemd}/bin/systemctl";
    nix = "${nix}/bin/nix";
    nix_store = "${nix}/bin/nix-store";
    timedatectl = "${systemd}/bin/timedatectl";
  };
  settingsFile = writeText "sbx-settings.json" (builtins.toJSON (settings // { inherit tools; }));
in
stdenvNoCC.mkDerivation {
  pname = "sbx";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./sbx
      ./tests
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -d $out/lib/sbx $out/bin
    cp -r sbx $out/lib/sbx/
    cat > $out/bin/sbx <<EOF
    #!${python.interpreter} -I
    import sys
    from pathlib import Path

    sys.path.insert(0, "$out/lib/sbx")
    from sbx.cli import main

    sys.exit(main(Path("${settingsFile}")))
    EOF
    chmod 0755 $out/bin/sbx
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HOME=$TMPDIR ${python.interpreter} -I -m unittest discover --start-directory tests --top-level-directory .
    runHook postInstallCheck
  '';

  passthru = { inherit settings settingsFile; };

  meta = {
    description = "Disposable agent sandboxes on the owner's qemu:///session";
    mainProgram = "sbx";
    platforms = lib.platforms.linux;
  };
}
