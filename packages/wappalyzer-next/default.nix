{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.buildPythonApplication rec {
  pname = "wappalyzer-next";
  version = "2.0.1";

  format = "setuptools";

  src = fetchFromGitHub {
    owner = "s0md3v";
    repo = "wappalyzer-next";
    tag = version;
    hash = "sha256-P/x5Si6JnUTA3G/LO3RyxS0VltxjMX7dtIsC11qJ+kQ=";
  };

  propagatedBuildInputs = with python3Packages; [
    requests
    huepy
    playwright
    tldextract
    beautifulsoup4
    dnspython
  ];

  # Upstream publishes no automated tests; disable to avoid unnecessary failures.
  doCheck = false;

  passthru.updateScript = ./update.py;

  meta = {
    description = "Wappalyzer-based technology stack detection CLI";
    homepage = "https://github.com/s0md3v/wappalyzer-next";
    license = lib.licenses.gpl3Only;
    mainProgram = "wappalyzer";
    platforms = lib.platforms.linux;
  };
}
