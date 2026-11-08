{
  lib,
  stdenvNoCC,
  python3,
}:
stdenvNoCC.mkDerivation {
  pname = "kagi-search";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    fileset = lib.fileset.unions [
      ./kagi_search
      ./tests
    ];
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -d $out/lib/kagi-search $out/bin
    cp -r kagi_search $out/lib/kagi-search/
    cat > $out/bin/kagi-search <<EOF
    #!${python3.interpreter} -I
    import sys

    sys.path.insert(0, "$out/lib/kagi-search")
    from kagi_search.cli import main

    sys.exit(main())
    EOF
    chmod 0755 $out/bin/kagi-search
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${python3.interpreter} -I -m unittest discover --start-directory tests --top-level-directory .
    $out/bin/kagi-search --help >/dev/null
    runHook postInstallCheck
  '';

  meta = {
    description = "Search Kagi with the session of LibreWolf's default profile";
    homepage = "https://github.com/Bad3r/nixos";
    license = lib.licenses.agpl3Only;
    mainProgram = "kagi-search";
    platforms = lib.platforms.linux;
  };
}
