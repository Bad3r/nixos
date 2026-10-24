{
  lib,
  stdenvNoCC,
  python3,
}:
stdenvNoCC.mkDerivation {
  pname = "workloads";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./workloads
      ./tests
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -d $out/lib/workloads $out/bin
    cp -r workloads $out/lib/workloads/
    cat > $out/bin/workloads <<EOF
    #!${python3.interpreter} -I
    import sys
    from pathlib import Path

    sys.path.insert(0, "$out/lib/workloads")
    from workloads.cli import main

    sys.exit(main(Path("/etc/workloads/names.json")))
    EOF
    chmod 0755 $out/bin/workloads
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${python3.interpreter} -I -m unittest discover --start-directory tests --top-level-directory .
    runHook postInstallCheck
  '';

  meta = {
    description = "Command line for declared workloads and live sandboxes";
    mainProgram = "workloads";
    platforms = lib.platforms.linux;
  };
}
