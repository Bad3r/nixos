{ callPackage, python3Packages }:

let
  pyaescrypt = python3Packages.callPackage ./pyaescrypt.nix { };
in
{
  list = callPackage ./list.nix { };
  extract = callPackage ./extract.nix { inherit pyaescrypt; };
}
