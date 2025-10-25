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
  rev = "4f46360aa493b04eae12045ac8c34a4e42441734";
in
rustPlatform.buildRustPackage (finalAttrs: {
  pname = "codex";
  version = "0.0.0";

  src = fetchFromGitHub {
    owner = "openai";
    repo = "codex";
    inherit rev;
    hash = "sha256-XqCx+9nafjYx7+84IXhuCGMk0wGfxsECBWblDcZTd3o=";
  };

  sourceRoot = "${finalAttrs.src.name}/codex-rs";

  patches = [ ./disable-update-check.patch ];

  cargoHash = "sha256-OxYA1ez11EBbjCZonCvCcCzPdsjFrU5bcHNQFwc7MRM=";

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
