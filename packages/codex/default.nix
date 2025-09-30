{
  lib,
  stdenv,
  rustPlatform,
  fetchFromGitHub,
  installShellFiles,
  makeBinaryWrapper,
  nix-update-script,
  pkg-config,
  openssl,
  ripgrep,
  versionCheckHook,
  installShellCompletions ? stdenv.buildPlatform.canExecute stdenv.hostPlatform,
}:

let
  rev = "bf76258cdc279dfd09f6c06508f8c5f65d427927";
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "codex";
  version = "0.0.0";

  src = fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    inherit rev;
    hash = "sha256-ux6/7596nA8yg3EJR8sHNphpd4U+1lZbsmY7iFJZD6s=";
  };

  sourceRoot = "${finalAttrs.src.name}/codex-rs";

  patches = [ ./disable-update-check.patch ];

  cargoHash = "sha256-ZyG8TrEbgStxzdTL+zBvtV4aYlHDTb+iID6WxbJO2yk=";

  nativeBuildInputs = [
    installShellFiles
    makeBinaryWrapper
    pkg-config
  ];

  buildInputs = [ openssl ];

  # NOTE: part of the upstream test suite requires network access and
  # additional system integration pieces. Until codex stabilizes, keeping
  # tests disabled avoids churn from frequently skipped cases.
  doCheck = false;

  postInstall = lib.optionalString installShellCompletions ''
    installShellCompletion --cmd codex \
      --bash <($out/bin/codex completion bash) \
      --fish <($out/bin/codex completion fish) \
      --zsh <($out/bin/codex completion zsh)
  '';

  postFixup = ''
    wrapProgram $out/bin/codex \
      --set CODEX_DISABLE_UPDATE_CHECK 1 \
      --prefix PATH : ${lib.makeBinPath [ ripgrep ]}
  '';

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];

  passthru = {
    updateScript = nix-update-script {
      extraArgs = [
        "--version-regex"
        "^rust-v(\\d+\\.\\d+\\.\\d+)$"
      ];
    };
  };

  meta = {
    description = "Lightweight coding agent that runs in your terminal";
    homepage = "https://github.com/openai/codex";
    changelog = "https://raw.githubusercontent.com/openai/codex/${rev}/CHANGELOG.md";
    license = lib.licenses.asl20;
    mainProgram = "codex";
    maintainers = with lib.maintainers; [
      malo
      delafthi
    ];
    platforms = lib.platforms.unix;
  };
})
