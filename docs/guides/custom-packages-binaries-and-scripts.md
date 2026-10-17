# Custom package binaries and scripts

Templates for pre-built binaries and shell scripts; [Reference implementations](custom-packages-style-guide.md#reference-implementations) lists a package of each type in the tree.
Each template elides `meta`, whose fields are in [Required meta fields](custom-packages-style-guide.md#required-meta-fields).

## Binary download (stdenvNoCC)

Pre-built binaries with multi-platform support pick their download by host system and set `meta.platforms` from the same table:

```nix
{
  lib,
  stdenvNoCC,
  fetchzip,
  makeWrapper,
}:

let
  version = "1.0.0";

  downloads = {
    x86_64-linux = {
      url = "https://example.com/releases/${version}/example-linux-x64.zip";
      sha256 = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
    };
    aarch64-linux = {
      url = "https://example.com/releases/${version}/example-linux-arm64.zip";
      sha256 = "sha256-BBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBBB=";
    };
  };

  platform =
    downloads.${stdenvNoCC.hostPlatform.system}
      or (throw "example: unsupported system ${stdenvNoCC.hostPlatform.system}");
in
stdenvNoCC.mkDerivation {
  pname = "example";
  inherit version;

  src = fetchzip {
    inherit (platform) url sha256;
    stripRoot = false;
  };

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    install -Dm755 "$src/example" "$out/bin/example"
    runHook postInstall
  '';

  meta = { ... };
}
```

## Shell wrapper (writeShellApplication)

Simple shell scripts with runtime dependencies use `writeShellApplication`.
The `/* bash */` annotation enables tree-sitter language injection, for syntax highlighting and LSP support through otter.nvim:

```nix
{
  lib,
  writeShellApplication,
  curl,
  jq,
}:

writeShellApplication {
  name = "example-script";

  runtimeInputs = [
    curl
    jq
  ];

  text = /* bash */ ''
    echo "Example script"
    curl -s https://api.example.com | jq .
  '';

  meta = { ... };
}
```
