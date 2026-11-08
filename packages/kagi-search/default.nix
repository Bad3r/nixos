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
    for entry in kagi-search:cli kagi-search-webrun:webrun; do
      name=''${entry%%:*}
      cat > $out/bin/$name <<EOF
    #!${python3.interpreter} -I
    import sys

    sys.path.insert(0, "$out/lib/kagi-search")
    from kagi_search.''${entry#*:} import main

    sys.exit(main())
    EOF
      chmod 0755 $out/bin/$name
    done
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    ${python3.interpreter} -I -m unittest discover --start-directory tests --top-level-directory .
    $out/bin/kagi-search --help >/dev/null
    echo '{"id":"install-check","model":"m","commands":{"time":[{"utc_offset":"+00:00"}]}}' \
      | XDG_STATE_HOME=$TMPDIR $out/bin/kagi-search-webrun > $TMPDIR/webrun.json
    grep -q '"encrypted_output": null' $TMPDIR/webrun.json
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
