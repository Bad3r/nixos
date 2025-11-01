{
  lib,
  rustPlatform,
  cargo-tauri,
  npmHooks,
  fetchFromGitHub,
  fetchNpmDeps,
  pkg-config,
  python3,
  nodejs,
  webkitgtk_4_1,
  glib,
  gtk3,
  openssl,
  pango,
  cairo,
  pixman,
  protobuf,
  perl,
  makeWrapper,
  nix-update-script,
  jq,
  wasm-pack,
  lld,
  wasm-bindgen-cli_0_2_100,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "yaak";
  version = "2025.7.3";

  src = fetchFromGitHub {
    owner = "mountain-loop";
    repo = "yaak";
    tag = "v${finalAttrs.version}";
    hash = "sha256-s6mZrTEBMZlgA/Xz8zpox0d7lXrXsJLGNHfKyYGliz0=";
  };

  npmDeps = fetchNpmDeps {
    inherit (finalAttrs) src;
    hash = "sha256-QK1yID1U7KUeRbfMbTUsj7qhHRG+W9GmmN6vRJcdrPc=";
  };

  cargoHash = "sha256-mhQo5p1iBn7hGGiUu1e3RZ8CAtNvdk/gPw/wj8XqGmQ=";

  cargoRoot = "src-tauri";

  nativeBuildInputs = [
    cargo-tauri.hook
    npmHooks.npmConfigHook
    pkg-config
    nodejs
    python3
    protobuf
    perl
    makeWrapper
    wasm-pack
    lld
  ];

  buildInputs = [
    glib
    gtk3
    openssl
    webkitgtk_4_1
    pango
    cairo
    pixman
  ];

  env = {
    ELECTRON_SKIP_BINARY_DOWNLOAD = "1";
    WASM_PACK_PATH = "${wasm-pack}/bin/wasm-pack";
    WASM_PACK_BINARY = "${wasm-pack}/bin/wasm-pack";
    NPM_CONFIG_IGNORE_SCRIPTS = "true";
  };

  postPatch = ''
    substituteInPlace package.json \
      --replace-fail '"bootstrap:vendor-node": "node scripts/vendor-node.cjs",' "" \
      --replace-fail '"bootstrap:vendor-protoc": "node scripts/vendor-protoc.cjs",' ""
    tmp=$(mktemp)
    ${jq}/bin/jq 'del(.devDependencies["wasm-pack"])' src-tauri/yaak-templates/package.json > "$tmp"
    mv "$tmp" src-tauri/yaak-templates/package.json
    substituteInPlace src-tauri/yaak-templates/package.json \
      --replace-fail 'wasm-pack build --target bundler' 'wasm-pack build --mode no-install --target bundler'
  '';

  preBuild = ''
    export WASM_PACK_CACHE="$TMPDIR/wasm-pack-cache"
    mkdir -p "$WASM_PACK_CACHE/.wasm-bindgen-cargo-install-0.2.100/bin"
    mkdir -p "$WASM_PACK_CACHE/wasm-bindgen-c59d5019a2b42393"

    # Use wasm-bindgen-cli 0.2.100 from nixpkgs (required version)
    cp ${wasm-bindgen-cli_0_2_100}/bin/wasm-bindgen "$WASM_PACK_CACHE/.wasm-bindgen-cargo-install-0.2.100/bin/"
    cp ${wasm-bindgen-cli_0_2_100}/bin/wasm-bindgen-test-runner "$WASM_PACK_CACHE/.wasm-bindgen-cargo-install-0.2.100/bin/" || true
    cp ${wasm-bindgen-cli_0_2_100}/bin/wasm-bindgen "$WASM_PACK_CACHE/wasm-bindgen-c59d5019a2b42393/"
    cp ${wasm-bindgen-cli_0_2_100}/bin/wasm-bindgen-test-runner "$WASM_PACK_CACHE/wasm-bindgen-c59d5019a2b42393/" || true
    chmod +x "$WASM_PACK_CACHE/.wasm-bindgen-cargo-install-0.2.100/bin/"* || true
    chmod +x "$WASM_PACK_CACHE/wasm-bindgen-c59d5019a2b42393/"* || true
    mkdir -p src-tauri/vendored/node
    ln -sfn ${nodejs}/bin/node src-tauri/vendored/node/yaaknode
    ln -sfn ${nodejs}/bin/node src-tauri/vendored/node/yaaknode-x86_64-unknown-linux-gnu
    mkdir -p src-tauri/vendored/protoc
    ln -sfn ${protobuf}/bin/protoc src-tauri/vendored/protoc/yaakprotoc
    ln -sfn ${protobuf}/bin/protoc src-tauri/vendored/protoc/yaakprotoc-x86_64-unknown-linux-gnu
    ln -sfn ${protobuf}/include src-tauri/vendored/protoc/include
  '';

  # Permission denied (os error 13)
  # write to src-tauri/vendored/protoc/include
  doCheck = false;

  preInstall = "pushd src-tauri";

  postInstall = "popd";

  postFixup = ''
    wrapProgram $out/bin/yaak-app \
      --inherit-argv0 \
      --set-default WEBKIT_DISABLE_DMABUF_RENDERER 1
  '';

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Desktop API client for organizing and executing REST, GraphQL, and gRPC requests";
    homepage = "https://yaak.app/";
    changelog = "https://github.com/mountain-loop/yaak/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.mit;
    maintainers = with lib.maintainers; [ redyf ];
    mainProgram = "yaak";
    platforms = [ "x86_64-linux" ];
  };
})
