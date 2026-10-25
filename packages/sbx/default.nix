{
  lib,
  stdenvNoCC,
  writeText,
  writeScript,
  writeScriptBin,
  python3,
  qemu_kvm,
  swtpm,
  openssh,
  socat,
  tesseract,
  util-linux,
  git,
  systemd,
  nix,
  xorriso,
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
  # First on sbx-libvirt's PATH: a sandbox's TPM emulator parses guest input,
  # so it gets no host network; libvirt reaches it over path-based sockets.
  swtpmShim = writeScriptBin "swtpm" ''
    #!${python3.interpreter} -I
    import os
    import sys

    sys.path.insert(0, "${emulatorSource}")
    from emulator import LaunchError, private_namespace

    try:
        private_namespace(os.getuid(), os.getgid())
    except (LaunchError, OSError) as error:
        sys.exit(f"sbx-swtpm: {error}")
    os.execv("${swtpm}/bin/swtpm", ["${swtpm}/bin/swtpm", *sys.argv[1:]])
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
    # Root's half of the Windows base export; never on PATH.
    install -d $out/libexec/sbx
    cat > $out/libexec/sbx/export-base <<EOF
    #!${python.interpreter} -I
    import sys

    sys.path.insert(0, "$out/lib/sbx")
    from sbx.export import main

    sys.exit(main())
    EOF
    chmod 0755 $out/libexec/sbx/export-base
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    HOME=$TMPDIR SBX_TEST_GIT=${lib.getExe git} ${python.interpreter} -I -m unittest discover --start-directory tests --top-level-directory .
    runHook postInstallCheck
  '';

  passthru = {
    inherit settings settingsFile swtpmShim;
    # swtpm_setup and swtpm_ioctl come from the real package behind the shim.
    swtpmPath = lib.makeBinPath [
      swtpmShim
      swtpm
    ];
  };

  meta = {
    description = "Disposable agent sandboxes on the owner's qemu:///session";
    mainProgram = "sbx";
    platforms = lib.platforms.linux;
  };
}
