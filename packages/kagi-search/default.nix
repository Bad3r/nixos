{
  lib,
  stdenvNoCC,
  callPackage,
}:
let
  # kagi-search runs on browser-fetch's modules and interpreter: the jar, curl-impersonate and
  # the fingerprint's headers are browser-fetch's own.
  browser-fetch = callPackage ../browser-fetch { };
  inherit (browser-fetch) python;
  path = "${browser-fetch}/lib/browser-fetch";
in
stdenvNoCC.mkDerivation {
  pname = "kagi-search";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    # A path: flake copies ignored files too, such as a worktree's bytecode.
    fileset = lib.fileset.intersection (lib.fileset.unions [
      ./kagi_search
      ./tests
    ]) (lib.fileset.fileFilter (file: !file.hasExt "pyc") ./.);
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -d $out/lib/kagi-search $out/bin
    cp -r kagi_search $out/lib/kagi-search/
    # -B: bytecode the check's runs would write into $out differs per build.
    for entry in kagi-search:cli kagi-search-webrun:webrun; do
      name=''${entry%%:*}
      cat > $out/bin/$name <<EOF
    #!${python.interpreter} -IB
    import sys

    sys.path[:0] = ["$out/lib/kagi-search", "${path}"]
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
    # Against the installed copy, beside the browser-fetch it runs on.
    mkdir check
    cp -r $out/lib/kagi-search/kagi_search tests check/
    (cd check && ${python.interpreter} -IB -c '
    import sys, unittest
    sys.path[:0] = [".", "${path}"]
    unittest.main(module=None, argv=["unittest", "discover", "--start-directory", "tests", "--top-level-directory", "."])
    ')
    $out/bin/kagi-search --help >/dev/null
    echo '{"id":"install-check","model":"m","commands":{"time":[{"utc_offset":"+00:00"}]}}' \
      | XDG_STATE_HOME=$TMPDIR $out/bin/kagi-search-webrun > $TMPDIR/webrun.json
    grep -q '"encrypted_output": null' $TMPDIR/webrun.json
    if find $out -name __pycache__ | grep .; then
      echo "the check wrote bytecode into $out" >&2
      exit 1
    fi
    runHook postInstallCheck
  '';

  passthru = { inherit browser-fetch; };

  meta = {
    description = "Search Kagi with the session in browser-fetch's cookie jar";
    homepage = "https://github.com/Bad3r/nixos";
    license = lib.licenses.agpl3Only;
    mainProgram = "kagi-search";
    platforms = lib.platforms.linux;
  };
}
