{
  lib,
  stdenvNoCC,
  python3,
}:
stdenvNoCC.mkDerivation {
  pname = "warp-devices";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./warp_devices
      ./tests
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -d $out/lib/warp-devices $out/bin
    cp -r warp_devices $out/lib/warp-devices/
    cat > $out/bin/warp-devices <<EOF
    #!${python3.interpreter} -I
    import sys

    sys.path.insert(0, "$out/lib/warp-devices")
    from warp_devices.cli import main

    sys.exit(main())
    EOF
    chmod 0755 $out/bin/warp-devices
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${python3.interpreter} -I -m unittest discover --start-directory tests --top-level-directory .
    $out/bin/warp-devices --help >/dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "List Cloudflare Zero Trust WARP devices with status, Mesh and public IPs, and per-device DEX history";
    homepage = "https://github.com/Bad3r/nixos";
    license = lib.licenses.agpl3Only;
    mainProgram = "warp-devices";
    platforms = lib.platforms.linux;
  };
}
