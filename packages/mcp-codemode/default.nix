{
  lib,
  stdenvNoCC,
  python314,
  nodejs_24,
  bubblewrap,
}:
stdenvNoCC.mkDerivation {
  pname = "mcp-codemode";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.intersection (lib.fileset.unions [
      ./mcp_codemode
      ./sandbox.mjs
      ./tests
    ]) (lib.fileset.fileFilter (file: !file.hasExt "pyc") ./.);
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -d $out/lib/mcp-codemode $out/bin
    cp -r mcp_codemode sandbox.mjs $out/lib/mcp-codemode/
    substituteInPlace $out/lib/mcp-codemode/mcp_codemode/_paths.py \
      --replace-fail "@node@" "${lib.getExe nodejs_24}" \
      --replace-fail "@bwrap@" "${lib.getExe bubblewrap}" \
      --replace-fail "@sandbox@" "$out/lib/mcp-codemode/sandbox.mjs"
    cat > $out/bin/mcp-codemode <<EOF
    #!${python314.interpreter} -IB
    import sys

    sys.path[:0] = ["$out/lib/mcp-codemode"]
    from mcp_codemode.cli import main

    sys.exit(main())
    EOF
    chmod 0755 $out/bin/mcp-codemode
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    mkdir check
    cp -r $out/lib/mcp-codemode/mcp_codemode $out/lib/mcp-codemode/sandbox.mjs tests check/
    (cd check && ${python314.interpreter} -IB -c '
    import sys, unittest
    sys.path[:0] = ["."]
    unittest.main(module=None, argv=["unittest", "discover", "--start-directory", "tests", "--top-level-directory", "."])
    ')
    $out/bin/mcp-codemode --help >/dev/null
    if find $out -name __pycache__ | grep .; then
      echo "the check wrote bytecode into $out" >&2
      exit 1
    fi
    runHook postInstallCheck
  '';

  meta = {
    description = "Local Code Mode MCP gateway multiplexing stdio and Streamable HTTP servers";
    homepage = "https://github.com/Bad3r/nixos";
    license = lib.licenses.agpl3Only;
    mainProgram = "mcp-codemode";
    platforms = lib.platforms.linux;
  };
}
