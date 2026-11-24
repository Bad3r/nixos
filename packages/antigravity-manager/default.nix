{
  lib,
  rustPlatform,
  fetchFromGitHub,
  fetchNpmDeps,
  npmHooks,
  nodejs,
  pkg-config,
  cmake,
  git,
  go,
  perl,
  wrapGAppsHook3,
  glib-networking,
  gtk3,
  libayatana-appindicator,
  librsvg,
  libsecret,
  libsoup_3,
  sqlite,
  webkitgtk_4_1,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "antigravity-manager";
  version = "5.0.4";

  src = fetchFromGitHub {
    owner = "lbjlaq";
    repo = "Antigravity-Manager";
    tag = "v${finalAttrs.version}";
    hash = "sha256-QHmurqcoFhX1pgbCjMs29niIGDegz5OIzaeXGbVkNMg=";
  };

  cargoRoot = "src-tauri";
  buildAndTestSubdir = "src-tauri";
  cargoHash = "sha256-qLgZTq9PF9OrQrm5/ehl3aBaQ9Uh2Btw8bZyn+LMwU0=";

  npmDeps = fetchNpmDeps {
    name = "${finalAttrs.pname}-${finalAttrs.version}-npm-deps";
    inherit (finalAttrs) src;
    hash = "sha256-DbhVeZsHkR6juuhREvd6PzC9Cq7GS2CBpFk/bEE0y+A=";
  };

  nativeBuildInputs = [
    npmHooks.npmConfigHook
    nodejs
    pkg-config
    # BoringSSL for the browser-impersonating HTTP client; boring-sys2 patches it with git apply.
    cmake
    git
    go
    perl
    rustPlatform.bindgenHook
    wrapGAppsHook3
  ];

  buildInputs = [
    glib-networking
    gtk3
    librsvg
    libsoup_3
    sqlite
    webkitgtk_4_1
  ];

  dontUseCmakeConfigure = true;

  preBuild = ''
    export GOCACHE="$TMPDIR/go-cache"
    # tauri::generate_context! embeds ../dist at compile time.
    npm run build
  '';

  doCheck = false;

  postInstall = ''
    mkdir -p "$out/share/antigravity-manager"
    cp -r dist "$out/share/antigravity-manager/dist"
  '';

  preFixup = ''
    gappsWrapperArgs+=(
      # The CLI's agy account switch stores the token with secret-tool.
      --prefix PATH : ${lib.makeBinPath [ libsecret ]}
      --prefix LD_LIBRARY_PATH : ${lib.makeLibraryPath [ libayatana-appindicator ]}
      --set-default ABV_DIST_PATH "$out/share/antigravity-manager/dist"
    )
  '';

  meta = {
    description = "Antigravity account manager and local Anthropic, OpenAI, and Gemini API proxy";
    homepage = "https://github.com/lbjlaq/Antigravity-Manager";
    changelog = "https://github.com/lbjlaq/Antigravity-Manager/releases/tag/v${finalAttrs.version}";
    license = lib.licenses.cc-by-nc-sa-40;
    mainProgram = "antigravity-server";
    platforms = lib.platforms.linux;
    maintainers = [ ];
  };
})
