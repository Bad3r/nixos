{
  lib,
  stdenvNoCC,
  fetchzip,
  writeShellApplication,
  coreutils,
  findutils,
}:

let
  version = "0.0.90";

  templates = stdenvNoCC.mkDerivation {
    pname = "spec-kit-templates";
    inherit version;

    src = fetchzip {
      url = "https://github.com/github/spec-kit/releases/download/v${version}/spec-kit-template-claude-sh-v${version}.zip";
      hash = "sha256-X7YfFBuZdDRmiXANGzaHkXMvvTH7YKBWwi/2yIUMcpA=";
      stripRoot = false;
    };

    dontBuild = true;

    installPhase = ''
      runHook preInstall
      mkdir -p "$out/share/spec-kit"
      cp -r "$src/.claude" "$out/share/spec-kit/" 2>/dev/null || true
      cp -r "$src/.specify" "$out/share/spec-kit/" 2>/dev/null || true
      runHook postInstall
    '';

    meta = {
      description = "Spec-Kit templates for Claude Code";
      homepage = "https://github.com/github/spec-kit";
      license = lib.licenses.mit;
      platforms = lib.platforms.all;
    };
  };

  initScript = writeShellApplication {
    name = "spec-kit-init";

    runtimeInputs = [
      coreutils
      findutils
    ];

    text = /* bash */ ''
            TEMPLATE_DIR="${templates}/share/spec-kit"
            TARGET_DIR="."
            FORCE=false
            GITIGNORE_SPECIFY=false
            GITIGNORE_CLAUDE=false

            usage() {
              cat <<EOF
      Usage: spec-kit-init [OPTIONS] [TARGET_DIR]

      Initialize a project with Spec-Kit templates for Claude Code.

      Arguments:
        TARGET_DIR    Directory to initialize (default: current directory)

      Options:
        -f, --force               Overwrite existing files
        --gitignore <target>      Add directories to .gitignore (creates if missing)
                                  Targets: specify, claude, all
        -h, --help                Show this help message
      EOF
            }

            while [[ $# -gt 0 ]]; do
              case "$1" in
                -f|--force) FORCE=true; shift ;;
                --gitignore)
                  if [[ -z "''${2:-}" ]]; then
                    echo "Error: --gitignore requires an argument (specify, claude, all)" >&2
                    exit 1
                  fi
                  case "$2" in
                    specify) GITIGNORE_SPECIFY=true ;;
                    claude) GITIGNORE_CLAUDE=true ;;
                    all) GITIGNORE_SPECIFY=true; GITIGNORE_CLAUDE=true ;;
                    *) echo "Error: Invalid gitignore target: $2 (use: specify, claude, all)" >&2; exit 1 ;;
                  esac
                  shift 2
                  ;;
                -h|--help) usage; exit 0 ;;
                -*) echo "Error: Unknown option: $1" >&2; usage >&2; exit 1 ;;
                *) TARGET_DIR="$1"; shift ;;
              esac
            done

            # Create target directory if it doesn't exist
            if [ ! -d "$TARGET_DIR" ]; then
              mkdir -p "$TARGET_DIR"
              echo "Created directory: $TARGET_DIR"
            fi

            TARGET_DIR="$(cd "$TARGET_DIR" && pwd)"

            # Check for existing files that would be overwritten
            EXISTING=()
            while IFS= read -r -d "" file; do
              rel="''${file#"$TEMPLATE_DIR"/}"
              [ -f "$TARGET_DIR/$rel" ] && EXISTING+=("$rel")
            done < <(find "$TEMPLATE_DIR" -type f -print0)

            if [ ''${#EXISTING[@]} -gt 0 ] && [ "$FORCE" = false ]; then
              echo "Warning: The following files already exist in $TARGET_DIR:"
              printf '  %s\n' "''${EXISTING[@]}"
              echo "Use --force to overwrite."
              exit 1
            fi

            echo "Initializing Spec-Kit templates in: $TARGET_DIR"

            # Copy templates (merges into existing directories)
            # Use -T to treat dest as file (merges contents), --no-preserve=mode for writable files
            if [ -d "$TEMPLATE_DIR/.claude" ]; then
              mkdir -p "$TARGET_DIR/.claude"
              cp -rT --no-preserve=mode "$TEMPLATE_DIR/.claude" "$TARGET_DIR/.claude"
              echo "  Copied .claude/"
            fi
            if [ -d "$TEMPLATE_DIR/.specify" ]; then
              mkdir -p "$TARGET_DIR/.specify"
              cp -rT --no-preserve=mode "$TEMPLATE_DIR/.specify" "$TARGET_DIR/.specify"
              echo "  Copied .specify/"
            fi

            # Make scripts executable
            find "$TARGET_DIR/.specify/scripts" -name '*.sh' -exec chmod +x {} \; 2>/dev/null || true

            # Update .gitignore if requested
            add_to_gitignore() {
              local entry="$1"
              local gitignore="$TARGET_DIR/.gitignore"
              if [ ! -f "$gitignore" ]; then
                echo "$entry" > "$gitignore"
                echo "  Created .gitignore with $entry"
              elif ! grep -qxF "$entry" "$gitignore"; then
                echo "$entry" >> "$gitignore"
                echo "  Added $entry to .gitignore"
              else
                echo "  $entry already in .gitignore"
              fi
            }

            if [ "$GITIGNORE_SPECIFY" = true ]; then
              add_to_gitignore ".specify"
            fi
            if [ "$GITIGNORE_CLAUDE" = true ]; then
              add_to_gitignore ".claude"
            fi

            echo ""
            echo "Spec-Kit initialized! Available slash commands:"
            echo "  /speckit.constitution  /speckit.specify  /speckit.plan"
            echo "  /speckit.tasks         /speckit.implement"
    '';

    meta = {
      description = "Initialize a project with Spec-Kit templates for Claude Code";
      mainProgram = "spec-kit-init";
    };
  };

in
stdenvNoCC.mkDerivation {
  pname = "spec-kit";
  inherit version;

  dontUnpack = true;
  dontBuild = true;

  installPhase = ''
    runHook preInstall
    mkdir -p "$out/bin" "$out/share"
    ln -s "${initScript}/bin/spec-kit-init" "$out/bin/spec-kit-init"
    ln -s "${templates}/share/spec-kit" "$out/share/spec-kit"
    runHook postInstall
  '';

  meta = {
    description = "Spec-Kit for Claude Code - Spec-Driven Development toolkit";
    homepage = "https://github.com/github/spec-kit";
    license = lib.licenses.mit;
    mainProgram = "spec-kit-init";
    platforms = lib.platforms.all;
  };
}
