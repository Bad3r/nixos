{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.buildPythonApplication rec {
  pname = "wappalyzer-next";
  version = "1.0.20";

  format = "setuptools";

  src = fetchFromGitHub {
    owner = "s0md3v";
    repo = "wappalyzer-next";
    rev = "88ceb4873d4f14a3c44a1bb22c38c3db47919fe5";
    hash = "sha256-vu9Gci9E+DEZYCljTpP4cX7lk6aG/BOqAeGVyhuFnkI=";
  };

  propagatedBuildInputs = with python3Packages; [
    requests
    huepy
    selenium
    tldextract
    beautifulsoup4
    dnspython
  ];

  # Upstream publishes no automated tests; disable to avoid unnecessary failures.
  doCheck = false;

  meta = {
    description = "Wappalyzer-based technology stack detection CLI";
    homepage = "https://github.com/s0md3v/wappalyzer-next";
    license = lib.licenses.gpl3Only;
    mainProgram = "wappalyzer";
    platforms = lib.platforms.linux;
  };
}
