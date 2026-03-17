{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.buildPythonApplication rec {
  pname = "snip";
  version = "0.6.0";
  pyproject = true;

  src = fetchFromGitHub {
    owner = "phlx0";
    repo = "snip";
    rev = "v${version}";
    hash = "sha256-gApmF1yOjVuz4tZ9VGItFb0uX6qrzcLeQjmp2oVs2WI=";
  };

  nativeBuildInputs = [ python3Packages.hatchling ];

  propagatedBuildInputs = [
    python3Packages.pyperclip
    python3Packages.textual
  ];

  nativeCheckInputs = [
    python3Packages.pytestCheckHook
    python3Packages."pytest-asyncio"
  ];

  pythonImportsCheck = [ "snip" ];

  meta = {
    description = "Terminal snippet manager for storing, searching, and reusing code snippets";
    homepage = "https://github.com/phlx0/snip";
    changelog = "https://github.com/phlx0/snip/releases/tag/v${version}";
    license = lib.licenses.mit;
    mainProgram = "snip";
    platforms = lib.platforms.unix;
  };
}
