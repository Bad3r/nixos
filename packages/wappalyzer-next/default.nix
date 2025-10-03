{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.buildPythonApplication rec {
  pname = "wappalyzer-next";
  version = "1.0.17";

  format = "setuptools";

  src = fetchFromGitHub {
    owner = "s0md3v";
    repo = "wappalyzer-next";
    rev = "dd1651fc2f3186775d491f70a3c31cb431b0f4e5";
    hash = "sha256-QW19zx5KkrZJ+RTmcKNkcJtzn5fe7xqy3s5GdmBUsXg=";
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
