{
  lib,
  buildPythonPackage,
  fetchPypi,
  setuptools,
  cryptography,
}:

buildPythonPackage rec {
  pname = "pyAesCrypt";
  version = "6.1.1";
  format = "setuptools";

  src = fetchPypi {
    inherit pname version;
    hash = "sha256-a/j5fAPsDkIAjakRrCXlI/EfFg9oTV8ryVec5QG+nq4=";
  };

  nativeBuildInputs = [ setuptools ];
  propagatedBuildInputs = [ cryptography ];

  pythonImportsCheck = [ "pyAesCrypt" ];

  meta = with lib; {
    description = "Encrypt and decrypt files and streams in AES Crypt format (version 2)";
    homepage = "https://github.com/marcobellaccini/pyAesCrypt";
    license = licenses.asl20;
    mainProgram = "pyAesCrypt";
  };
}
