{
  lib,
  stdenvNoCC,
  callPackage,
  python3,
  curl-impersonate,
  iproute2,
  nspr,
  passt,
  util-linux,
  xvfb,
}:
let
  camoufox = callPackage ../camoufox { };
  python = python3.withPackages (
    ps:
    [
      ps.idna
      ps.markitdown
      ps.playwright
      # The Public Suffix List, as Gecko's cookie code reads it.
      ps.publicsuffixlist
      camoufox.python
    ]
    # Document converters only; no audio, YouTube, Outlook or Azure extras.
    ++ ps.markitdown.optional-dependencies.pdf
    ++ ps.markitdown.optional-dependencies.docx
    ++ ps.markitdown.optional-dependencies.pptx
    ++ ps.markitdown.optional-dependencies.xlsx
  );
in
stdenvNoCC.mkDerivation {
  pname = "browser-fetch";
  version = "0.1.0";

  src = lib.fileset.toSource {
    root = ./.;
    # A path: flake copies ignored files too, such as a worktree's bytecode.
    fileset = lib.fileset.intersection (lib.fileset.unions [
      ./browser_fetch
      ./tests
    ]) (lib.fileset.fileFilter (file: !file.hasExt "pyc") ./.);
  };

  dontConfigure = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -d $out/lib/browser-fetch $out/bin $out/libexec
    cp -r browser_fetch $out/lib/browser-fetch/
    substituteInPlace $out/lib/browser-fetch/browser_fetch/tools.py \
      --replace-fail "@curlImpersonate@" "${lib.getExe' curl-impersonate "curl-impersonate"}" \
      --replace-fail "@camoufox@" "${camoufox.executable}" \
      --replace-fail "@camoufoxVersion@" "${camoufox.version}" \
      --replace-fail "@xvfb@" "${lib.getExe' xvfb "Xvfb"}" \
      --replace-fail "@unshare@" "${lib.getExe' util-linux "unshare"}" \
      --replace-fail "@pasta@" "${lib.getExe' passt "pasta"}" \
      --replace-fail "@ip@" "${lib.getExe' iproute2 "ip"}" \
      --replace-fail "@session@" "$out/libexec/browser-fetch-session"
    # -B: bytecode the check's runs would write into $out differs per build.
    for entry in bin/browser-fetch:cli libexec/browser-fetch-session:session; do
      cat > $out/''${entry%%:*} <<EOF
    #!${python.interpreter} -IB
    import sys

    sys.path.insert(0, "$out/lib/browser-fetch")
    from browser_fetch.''${entry##*:} import main

    sys.exit(main())
    EOF
      chmod 0755 $out/''${entry%%:*}
    done
    runHook postInstall
  '';

  doInstallCheck = true;
  installCheckPhase = ''
    runHook preInstallCheck
    # Against the installed copy, whose tools are store paths.
    mkdir check
    cp -r $out/lib/browser-fetch/browser_fetch tests check/
    # NSPR, whose PR_ParseTimeString Gecko reads cookie dates with, checks the port.
    (cd check && BROWSER_FETCH_TEST_NSPR=${lib.getLib nspr}/lib/libnspr4.so \
      ${python.interpreter} -I -m unittest discover --start-directory tests --top-level-directory .)
    $out/bin/browser-fetch --help >/dev/null
    if find $out -name __pycache__ | grep .; then
      echo "the check wrote bytecode into $out" >&2
      exit 1
    fi
    runHook postInstallCheck
  '';

  passthru = { inherit camoufox python; };

  meta = {
    description = "Fetch a web page with a browser's TLS fingerprint and Camoufox's cookie jar, or in Camoufox";
    homepage = "https://github.com/Bad3r/nixos";
    license = lib.licenses.agpl3Only;
    mainProgram = "browser-fetch";
    platforms = lib.platforms.linux;
  };
}
