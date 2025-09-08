{
  # Per-user R2 "ready-to-run" profile
  #
  # This Home-Manager module sets up a minimal rclone remote named `r2` and
  # installs helper wrappers for rclone and s5cmd that read environment values
  # from ~/.config/cloudflare/r2/env.
  #
  # Secrets: Do NOT store credentials in Nix. Create the env file securely,
  # preferably via sops as outlined in docs/sops-nixos.md and
  # docs/sops-dotfile.example.yaml. Example content:
  #
  #   # ~/.config/cloudflare/r2/env (0400)
  #   AWS_ACCESS_KEY_ID=...           # R2 access key
  #   AWS_SECRET_ACCESS_KEY=...       # R2 secret key
  #   R2_ACCOUNT_ID=...               # e.g., abcdef1234567890abcdef1234567890
  #   # Optional: if not using R2_ACCOUNT_ID
  #   # AWS_ENDPOINT_URL=https://<ACCOUNT_ID>.r2.cloudflarestorage.com
  #
  # Usage:
  #   # rclone with env automatically set
  #   r2 ls r2:my-bucket
  #   r2 copy ./file.txt r2:my-bucket/path/
  #
  #   # s5cmd with endpoint set
  #   r2s5 ls s3://my-bucket/
  #   r2s5 cp ./file.txt s3://my-bucket/path/
  #
  flake.modules.homeManager.base =
    {
      pkgs,
      config,
      lib,
      ...
    }:
    let
      envFile = "${config.home.homeDirectory}/.config/cloudflare/r2/env";

      r2 = pkgs.writeShellApplication {
        name = "r2";
        runtimeInputs = with pkgs; [
          rclone
          coreutils
        ];
        text = ''
          set -euo pipefail
          # Load per-user R2 env if present
          if [ -f ${lib.escapeShellArg envFile} ]; then
            # shellcheck disable=SC1091
            . ${lib.escapeShellArg envFile}
          fi

          set +u
          ak="''${AWS_ACCESS_KEY_ID:-}"
          sk="''${AWS_SECRET_ACCESS_KEY:-}"
          acc="''${R2_ACCOUNT_ID:-}"
          rce="''${RCLONE_CONFIG_R2_ENDPOINT:-}"
          set -u
          if [ -z "''${ak}" ] || [ -z "''${sk}" ]; then
            echo "[r2] Missing AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY. See docs/sops-nixos.md." >&2
            exit 1
          fi

          if [ -n "''${acc}" ] && [ -z "''${rce}" ]; then
            export RCLONE_CONFIG_R2_ENDPOINT="https://''${acc}.r2.cloudflarestorage.com"
          fi

          exec rclone "$@"
        '';
      };

      r2s5 = pkgs.writeShellApplication {
        name = "r2s5";
        runtimeInputs = with pkgs; [
          s5cmd
          coreutils
        ];
        text = ''
          set -euo pipefail
          if [ -f ${lib.escapeShellArg envFile} ]; then
            # shellcheck disable=SC1091
            . ${lib.escapeShellArg envFile}
          fi

          set +u
          ak="''${AWS_ACCESS_KEY_ID:-}"
          sk="''${AWS_SECRET_ACCESS_KEY:-}"
          acc="''${R2_ACCOUNT_ID:-}"
          aeu="''${AWS_ENDPOINT_URL:-}"
          set -u
          if [ -z "''${ak}" ] || [ -z "''${sk}" ]; then
            echo "[r2s5] Missing AWS_ACCESS_KEY_ID or AWS_SECRET_ACCESS_KEY. See docs/sops-nixos.md." >&2
            exit 1
          fi

          if [ -n "''${acc}" ]; then
            exec s5cmd --endpoint-url "https://''${acc}.r2.cloudflarestorage.com" "$@"
          elif [ -n "''${aeu}" ]; then
            exec s5cmd --endpoint-url "''${aeu}" "$@"
          else
            exec s5cmd "$@"
          fi
        '';
      };
    in
    {
      # sops-nix HM module is imported centrally in modules/home-manager/nixos.nix

      # Keep all assignments under `config` to satisfy strict checks
      config = {
        # Minimal rclone remote using env overrides
        xdg.configFile."rclone/rclone.conf".text = ''
          [r2]
          type = s3
          provider = Cloudflare
          # endpoint, access_key_id, and secret_access_key are provided at runtime via env:
          #   RCLONE_CONFIG_R2_ENDPOINT, AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
        '';

        xdg.configFile."cloudflare/r2/README".text = ''
          Cloudflare R2 per-user configuration

          Place credentials in: ${envFile}

          Example env file (chmod 0400):
            AWS_ACCESS_KEY_ID=...
            AWS_SECRET_ACCESS_KEY=...
            R2_ACCOUNT_ID=...
            # optional alternative:
            # AWS_ENDPOINT_URL=https://<ACCOUNT_ID>.r2.cloudflarestorage.com

          See docs/sops-nixos.md and docs/sops-dotfile.example.yaml to manage
          this file with sops (recommended).
        '';

        home.packages = [
          r2
          r2s5
        ];
      };
    };
}
