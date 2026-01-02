# DEPRECATED: This custom package is no longer used.
# Codex is now installed from upstream nixpkgs.
# This file is prefixed with '_' to prevent auto-import.
# Kept for reference in case upstream regresses.
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
  rev = "89591e42460b0455a0fe73147028092f7942f0c8";
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "codex";
  version = "0.0.0";

  src = fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    inherit rev;
    hash = "sha256-1ophzOL39/Xln6JQoUw8YCQ3ya4nos3Ypj8jMms5mNc=";
  };

  sourceRoot = "${finalAttrs.src.name}/codex-rs";

  patches = [ ./disable-update-check.patch ];

  cargoHash = "sha256-3wjd2XI1aIx9NlhZgOGhg8d+9sCdsJacALX+zaN8K2E=";

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
