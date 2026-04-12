{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  nodejs_22,
}:

buildNpmPackage rec {
  pname = "source-map-explorer";
  version = "2.5.3";

  src = fetchFromGitHub {
    owner = "danvk";
    repo = "source-map-explorer";
    rev = "v${version}";
    hash = "sha256-IcGhRkU+Mqx1rfOu1p3HDNeozPunNzgW/L+JrYVatvc=";
  };

  nodejs = nodejs_22;

  npmDepsHash = "sha256-1yZrv1pe82r8GuJT/EXBB5NH+htezN4BJN8dX7v9zKE=";

  meta = {
    description = "Analyze and debug space usage through source maps";
    homepage = "https://github.com/danvk/source-map-explorer";
    license = lib.licenses.asl20;
    mainProgram = "source-map-explorer";
    platforms = lib.platforms.linux;
  };
}
