# Custom package source builds

Templates for packages built from source with a language builder; [Reference implementations](custom-packages-style-guide.md#reference-implementations) lists a package of each type in the tree.
Each template elides `meta`, whose fields are in [Required meta fields](custom-packages-style-guide.md#required-meta-fields).

## Rust (buildRustPackage)

```nix
{
  lib,
  rustPlatform,
  fetchFromGitHub,
  pkg-config,
  openssl,
}:

let
  pin = lib.importJSON ./hashes.json;
in
rustPlatform.buildRustPackage rec {
  pname = "example-tool";
  inherit (pin) version;

  src = fetchFromGitHub {
    owner = "example";
    repo = "example-tool";
    rev = "v${version}";
    hash = pin.srcHash;
  };

  cargoHash = pin.cargoHash;

  nativeBuildInputs = [ pkg-config ];
  buildInputs = [ openssl ];

  passthru.updateScript = ./update.py;

  meta = { ... };
}
```

## Go (buildGoModule)

```nix
{
  lib,
  buildGoModule,
  fetchFromGitHub,
}:

buildGoModule rec {
  pname = "example-go";
  version = "1.0.0";

  src = fetchFromGitHub {
    owner = "example";
    repo = "example-go";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  vendorHash = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";

  ldflags = [ "-s" "-w" ];

  meta = { ... };
}
```

## Python (buildPythonApplication)

```nix
{
  lib,
  python3Packages,
  fetchFromGitHub,
}:

python3Packages.buildPythonApplication rec {
  pname = "example-py";
  version = "1.0.0";
  format = "setuptools";

  src = fetchFromGitHub {
    owner = "example";
    repo = "example-py";
    rev = "v${version}";
    hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
  };

  propagatedBuildInputs = with python3Packages; [
    requests
  ];

  doCheck = false; # Only if upstream has no tests

  meta = { ... };
}
```
