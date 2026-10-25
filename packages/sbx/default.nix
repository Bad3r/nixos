{
  lib,
  stdenvNoCC,
  writeText,
  writeScript,
  writeShellScript,
  python3,
  qemu_kvm,
  openssh,
  socat,
  tesseract,
  util-linux,
  git,
  systemd,
  nix,
  xorriso,
  virtiofsd,
  # Rendered by modules/apps/sbx/nixos.nix; the bare package refuses to run.
  settings ? { },
}:
let
  python = python3.withPackages (ps: [ ps.libvirt ]);
  emulatorSource = lib.fileset.toSource {
    root = ./sbx;
    fileset = ./sbx/emulator.py;
  };
  # libvirt runs it as each sandbox's emulator; domains and save images pin its path.
  emulator = writeScript "sbx-qemu" ''
    #!${python3.interpreter} -I
    import sys

    sys.path.insert(0, "${emulatorSource}")
    from emulator import main

    main("${qemu_kvm}/bin/qemu-system-x86_64", sys.argv[1:])
  '';
  # Every guest id writes as the owner, and every host file shows as uid 1000 and gid 100,
  # the GUI base's sbx user, so a non-root guest user writes too and the owner deletes it all.
  shareDaemon = writeShellScript "sbx-virtiofsd" ''
    exec ${virtiofsd}/bin/virtiofsd \
      --translate-uid=squash-guest:0:0:4294967295 --translate-uid=squash-host:0:1000:4294967295 \
      --translate-gid=squash-guest:0:0:4294967295 --translate-gid=squash-host:0:100:4294967295 \
      "$@"
  '';
  tools = {
    emulator = "${emulator}";
    qemu_img = "${qemu_kvm}/bin/qemu-img";
    ssh = "${openssh}/bin/ssh";
    scp = "${openssh}/bin/scp";
    ssh_keygen = "${openssh}/bin/ssh-keygen";
    socat = lib.getExe socat;
    tesseract = lib.getExe tesseract;
    nsenter = "${util-linux}/bin/nsenter";
    git = lib.getExe git;
    systemctl = "${systemd}/bin/systemctl";
    nix = "${nix}/bin/nix";
    nix_store = "${nix}/bin/nix-store";
    timedatectl = "${systemd}/bin/timedatectl";
    xorriso = "${xorriso}/bin/xorriso";
    virtiofsd = "${shareDaemon}";
  };
  version = "0.1.0";
  settingsFile = writeText "sbx-settings.json" (builtins.toJSON (settings // { inherit tools; }));
in
stdenvNoCC.mkDerivation {
  pname = "sbx";
  inherit version;

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
    cat > $out/bin/sbx-mcp <<EOF
    #!${python.interpreter} -I
    import sys
    from pathlib import Path

    sys.path.insert(0, "$out/lib/sbx")
    from sbx.mcp import serve

    sys.exit(serve(Path("${settingsFile}"), "${version}"))
    EOF
    chmod 0755 $out/bin/sbx $out/bin/sbx-mcp
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HOME=$TMPDIR SBX_TEST_GIT=${lib.getExe git} ${python.interpreter} -I -m unittest discover --start-directory tests --top-level-directory .
    runHook postInstallCheck
  '';

  passthru = { inherit settings settingsFile; };

  meta = {
    description = "Disposable agent sandboxes on the owner's qemu:///session";
    mainProgram = "sbx";
    platforms = lib.platforms.linux;
  };
}
