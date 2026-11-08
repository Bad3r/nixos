# The Python launcher paired with the browser build, and fpgen with its pinned model, never downloading.
{
  lib,
  buildPythonPackage,
  fetchPypi,
  fetchurl,
  unzip,
  poetry-core,
  pythonRelaxDepsHook,
  camoufox,
  pin,
  python,
  click,
  httpx,
  indexed-zstd,
  inquirer,
  language-tags,
  numpy,
  orjson,
  platformdirs,
  playwright,
  pysocks,
  pyyaml,
  requests,
  rich,
  rich-click,
  screeninfo,
  typing-extensions,
  ua-parser,
  zstandard,
}:

let
  model = fetchurl {
    url = pin.modelUrl;
    hash = pin.modelHash;
  };

  fpgen = buildPythonPackage {
    pname = "fpgen";
    version = pin.fpgenVersion;
    pyproject = true;

    src = fetchPypi {
      pname = "fpgen";
      version = pin.fpgenVersion;
      hash = pin.fpgenHash;
    };

    build-system = [ poetry-core ];
    nativeBuildInputs = [ unzip ];
    dependencies = [
      click
      httpx
      indexed-zstd
      numpy
      orjson
      zstandard
    ];

    # The model is the store's: fpgen never refreshes it on import.
    postPatch = ''
      substituteInPlace fpgen/pkgman.py \
        --replace-fail "files_are_recent(FILE_PAIRS.values())" "True"
    '';

    postInstall = ''
      unzip -q ${model} -d $out/${python.sitePackages}/fpgen/data
    '';

    pythonImportsCheck = [ "fpgen" ];

    meta = {
      description = "Browser fingerprint generator from a Bayesian network of real traffic";
      homepage = "https://github.com/scrapfly/fingerprint-generator";
      license = lib.licenses.asl20;
    };
  };

in
buildPythonPackage {
  pname = "camoufox";
  version = pin.libraryVersion;
  pyproject = true;

  src = fetchPypi {
    pname = "camoufox";
    version = pin.libraryVersion;
    hash = pin.libraryHash;
  };

  build-system = [ poetry-core ];
  nativeBuildInputs = [ pythonRelaxDepsHook ];
  # Camoufox caps Playwright below the release nixpkgs ships; browser-fetch's
  # GuardTest launches this browser through the pair in its check.
  pythonRelaxDeps = [ "playwright" ];

  dependencies = [
    fpgen
    inquirer
    language-tags
    numpy
    orjson
    platformdirs
    playwright
    pysocks
    pyyaml
    requests
    rich
    rich-click
    screeninfo
    typing-extensions
    ua-parser
  ];

  # The model is the store's and read-only: check it against the pin, never fetch or re-date it.
  postPatch = ''
    substituteInPlace src/camoufox/fpgen_model.py \
      --replace-fail "            _stamp(data_dir)" "            pass" \
      --replace-fail "    print(f\"Downloading fpgen model {PIN['tag']}: {PIN['url']}\", file=sys.stderr)" \
                     "    raise FpgenModelError(f\"fpgen's model in {data_dir} is not the pinned {PIN['tag']}\")"
    grep -q '"tag": "v${camoufox.version}"' src/camoufox/browser-pin.json
  '';

  pythonImportsCheck = [ "camoufox" ];

  # The launcher's model pin and the one fpgen carries must agree, or the
  # first fingerprint fails at run time.
  postInstallCheck = ''
    ${python.interpreter} -c 'from camoufox.fpgen_model import is_pinned; assert is_pinned()'
  '';

  passthru = { inherit fpgen model; };

  meta = {
    description = "Python launcher for the Camoufox browser";
    homepage = "https://github.com/daijro/camoufox/tree/main/python";
    license = lib.licenses.mit;
  };
}
