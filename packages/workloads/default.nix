{
  lib,
  stdenvNoCC,
  python3,
  nftables,
  conntrack-tools,
  iproute2,
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
    cat > $out/bin/workload-grantd <<EOF
    #!${python3.interpreter} -I
    import sys
    from pathlib import Path

    sys.path.insert(0, "$out/lib/workloads")
    from workloads.grantd import Tools, main

    tools = Tools(
        nft="${lib.getExe nftables}",
        conntrack="${lib.getExe' conntrack-tools "conntrack"}",
        ip="${lib.getExe' iproute2 "ip"}",
    )
    sys.exit(main(Path("/etc/workloads/grants.json"), tools, Path("/run/workloads/grantd.lock")))
    EOF
    chmod 0755 $out/bin/workloads $out/bin/workload-grantd
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${python3.interpreter} -I -m unittest discover --start-directory tests --top-level-directory .
    runHook postInstallCheck
  '';

  meta = {
    description = "Command line and grant helper for declared workloads and live sandboxes";
    mainProgram = "workloads";
    platforms = lib.platforms.linux;
  };
}
