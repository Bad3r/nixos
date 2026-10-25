{
  lib,
  stdenvNoCC,
  installShellFiles,
  bash,
  zsh,
  fish,
  writeText,
  writeScript,
  writeShellScript,
  writeScriptBin,
  python3,
  qemu_kvm,
  swtpm,
  coreutils,
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
  python = python3.withPackages (ps: [
    ps.argcomplete
    ps.libvirt
    ps.pillow
  ]);
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
  nativeBuildInputs = [ installShellFiles ];

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
    installShellCompletion --cmd sbx \
      --bash <(${python}/bin/register-python-argcomplete --no-defaults --shell bash sbx) \
      --zsh <(${python}/bin/register-python-argcomplete --no-defaults --shell zsh sbx) \
      --fish <(${python}/bin/register-python-argcomplete --shell fish sbx)
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
  nativeInstallCheckInputs = [
    bash
    zsh
    fish
  ];
  installCheckPhase = ''
    runHook preInstallCheck
    HOME=$TMPDIR SBX_TEST_GIT=${lib.getExe git} \
      SBX_TEST_PACKAGE=$out \
      ${python.interpreter} -I -m unittest discover --start-directory tests --top-level-directory .
    runHook postInstallCheck
  '';

  passthru = {
    inherit
      emulator
      settings
      settingsFile
      swtpmShim
      ;
    # PATH of sbx-libvirt: the shim wins over swtpm, whose package still gives
    # swtpm_setup and swtpm_ioctl; the rest is the user manager's own PATH.
    daemonPath = lib.concatStringsSep ":" [
      (lib.makeBinPath [
        swtpmShim
        swtpm
        coreutils
      ])
      "/run/wrappers/bin"
      "/etc/profiles/per-user/%u/bin"
      "/run/current-system/sw/bin"
    ];
  };

  meta = {
    description = "Disposable agent sandboxes on the owner's qemu:///session";
    mainProgram = "sbx";
    platforms = lib.platforms.linux;
  };
}
