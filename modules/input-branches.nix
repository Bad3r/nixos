{
  config,
  inputs,
  lib,
  rootPath,
  ...
}:
{
  imports = [ inputs.input-branches.flakeModules.default ];

  input-branches.inputs = {
    nixpkgs = {
      upstream = {
        url = "github:NixOS/nixpkgs";
        ref = "nixpkgs-unstable";
      };
      shallow = true;
    };
    home-manager.upstream = {
      url = "github:nix-community/home-manager";
      ref = "master";
    };
    stylix.upstream = {
      url = "github:nix-community/stylix";
      ref = "master";
    };
  };

  # Import mitigation module and (optionally) force nixpkgs source to the local input path
  flake.nixosModules.base = {
    imports = [ inputs.input-branches.modules.nixos.default ];
    nixpkgs.flake.source = lib.mkForce (rootPath + "/inputs/nixpkgs");
  };

  perSystem =
    psArgs@{ pkgs, ... }:
    {
      # Expose input-branches commands in the dev shell
      make-shells.default.packages = psArgs.config.input-branches.commands.all;

      # Exclude input branches from formatting for speed
      treefmt.settings.global.excludes = [ "${config.input-branches.baseDir}/*" ];

      # Pre-push hook: ensure ONLY CHANGED input submodules are pushed to origin.
      # Also perform a lightweight upstream provenance check via GitHub API when a
      # squashed upstream commit is embedded in the submodule HEAD message.
      pre-commit.settings.hooks.check-submodules-pushed = {
        enable = false;
        stages = [ ];
        always_run = true;
        verbose = true;
        require_serial = true;
        entry = lib.getExe (
          pkgs.writeShellApplication {
            name = "check-submodules-pushed";
            runtimeInputs = [
              pkgs.git
              pkgs.gnugrep
              pkgs.gnused
              pkgs.coreutils
              pkgs.jq
              pkgs.curl
              pkgs.gh
            ];
            text = ''
              set -euo pipefail
              set -o xtrace

              ROOT=$(git rev-parse --show-toplevel 2>/dev/null || pwd)
              cd "$ROOT"

              # Determine current branch
              SP_BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo main)

              # Prefer remote base from Git's pre-push stdin (format: local_sha local_ref remote_sha remote_ref)
              BASE=""
              # shellcheck disable=SC2034 # LOCAL_* and REMOTE_* used for clarity; only REMOTE_SHA is needed
              if read -r LOCAL_SHA LOCAL_REF REMOTE_SHA REMOTE_REF; then
                if [ -n "''${REMOTE_SHA:-}" ] && [ "''${REMOTE_SHA:-0000000}" != "0000000000000000000000000000000000000000" ]; then
                  BASE="$REMOTE_SHA"
                fi
              fi < /dev/stdin || true

              # Fallbacks when pre-push stdin didn't provide a remote base
              if [ -z "$BASE" ]; then
                if git rev-parse --verify -q "origin/$SP_BRANCH" >/dev/null; then
                  BASE="origin/$SP_BRANCH"
                else
                  # Last resort: use the root commit
                  BASE=$(git rev-list --max-parents=0 HEAD | tail -n1)
                fi
              fi

              # Determine which input submodules changed in this push range
              CHANGED_NAMES=$(git diff --name-only "$BASE..HEAD" | sed -n 's/^inputs\///p' | cut -d/ -f1 | sort -u)
              if [ -z "$CHANGED_NAMES" ]; then
                echo "No inputs/* submodule changes detected; nothing to do."
                exit 0
              fi

              PARENT_ORIGIN=$(git remote get-url --push origin 2>/dev/null || git remote get-url origin 2>/dev/null || true)
              if [ -z "$PARENT_ORIGIN" ]; then
                echo "Error: could not resolve superproject origin URL" >&2
                exit 1
              fi

              for name in $CHANGED_NAMES; do
                path="inputs/$name"
                [ -d "$path" ] || { echo "Warning: missing submodule path $path" >&2; continue; }
                echo "==> Processing $name ($path)"

                # Verify clean worktree and get HEAD sha
                status=$(git -C "$path" status --porcelain)
                if [ -n "$status" ]; then
                  echo "Error: submodule $path not clean" >&2
                  exit 1
                fi
                head_sha=$(git -C "$path" rev-parse --quiet HEAD)
                [ -n "$head_sha" ] || { echo "Error: could not find HEAD of $path" >&2; exit 1; }

                # Ensure submodule origin push url points to superproject origin
                if ! git -C "$path" remote get-url origin >/dev/null 2>&1; then
                  git -C "$path" remote add origin "$PARENT_ORIGIN"
                else
                  git -C "$path" remote set-url --push origin "$PARENT_ORIGIN"
                fi

                # Select target branch for the submodule push
                sub_branch=$(git config -f .gitmodules "submodule.$path.branch" 2>/dev/null || true)
                if [ -z "$sub_branch" ]; then
                  sub_branch="inputs/$SP_BRANCH/$name"
                fi

                # Determine remote tip to use accurate force-with-lease
                remote_sha=$(git ls-remote --heads "$PARENT_ORIGIN" "refs/heads/$sub_branch" | awk '{print $1}' | head -n1 || true)
                if [ "''${remote_sha:-}" = "$head_sha" ]; then
                  echo "Remote already at $head_sha; skipping push for $name"
                else
                  echo "Pushing $name HEAD $head_sha -> origin:$sub_branch (remote was ''${remote_sha:-<none>})"
                  if [ -n "''${remote_sha:-}" ]; then
                    git -C "$path" push --force-with-lease="refs/heads/$sub_branch:''$remote_sha" -u origin "HEAD:refs/heads/$sub_branch"
                  else
                    git -C "$path" push -u origin "HEAD:refs/heads/$sub_branch"
                  fi
                  # Verify the branch exists on origin
                  if ! git ls-remote --heads "$PARENT_ORIGIN" "refs/heads/$sub_branch" | grep -q .; then
                    echo "Error: failed to verify remote branch '$sub_branch' for $name" >&2
                    exit 1
                  fi
                fi

                # Lightweight provenance check: if commit message embeds an upstream sha and upstream is GitHub
                msg=$(git -C "$path" log -1 --pretty=%B || true)
                upstream_sha=$(printf "%s" "$msg" | sed -n 's/.*squashed upstream \([0-9a-f]\{7,40\}\).*/\1/p' | head -n1)
                upstream_url=$(git -C "$path" remote get-url upstream 2>/dev/null || true)
                upstream_ref=$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name upstream/HEAD 2>/dev/null | sed 's|^upstream/||' || true)
                [ -n "$upstream_ref" ] || upstream_ref="master"
                if [ -n "$upstream_sha" ]; then
                  case "$upstream_url" in
                    https://github.com/*|git@github.com:*)
                      owner_repo="$upstream_url"
                      owner_repo="''${owner_repo#git@github.com:}"
                      owner_repo="''${owner_repo#https://github.com/}"
                      owner_repo="''${owner_repo%.git}"
                      owner="''${owner_repo%%/*}"
                      repo="''${owner_repo#*/}"
                      echo "Provenance: GitHub compare $owner/$repo $upstream_sha...$upstream_ref"
                      if command -v gh >/dev/null 2>&1; then
                        status=$(gh api "repos/$owner/$repo/compare/$upstream_sha...$upstream_ref" --jq .status 2>/dev/null || true)
                      else
                        resp=$(curl -sSL --connect-timeout 10 --max-time 30 -H "Accept: application/vnd.github+json" "https://api.github.com/repos/$owner/$repo/compare/$upstream_sha...$upstream_ref" || true)
                        status=$(printf "%s" "$resp" | jq -r '.status // empty')
                      fi
                      if [ "$status" = "ahead" ] || [ "$status" = "identical" ]; then
                        echo "Provenance OK: upstream sha is reachable (status=$status)."
                      else
                        [ -n "$status" ] || status="unknown"
                        echo "Error: provenance check failed for $name (status=$status)." >&2
                        exit 1
                      fi
                      ;;
                    *) ;;
                  esac
                fi

                # Avoid full hydration of nixpkgs when preparing a push.
                # Keep blobless for speed unless explicitly overridden.
                if git -C "$path" remote get-url upstream >/dev/null 2>&1; then
                  up_head=$(git -C "$path" rev-parse --abbrev-ref --symbolic-full-name upstream/HEAD 2>/dev/null | sed 's|^upstream/||' || true)
                  if [ "$name" = "nixpkgs" ] && [ -z "''${HYDRATE_NIXPKGS:-}" ]; then
                    if [ -n "$up_head" ]; then
                      git -C "$path" fetch --filter=blob:none upstream "$up_head" || true
                    else
                      git -C "$path" fetch --filter=blob:none upstream || true
                    fi
                  else
                    if [ -n "$up_head" ]; then
                      git -C "$path" fetch --no-filter upstream "$up_head" || true
                    else
                      git -C "$path" fetch --no-filter upstream || true
                    fi
                  fi
                fi
              done
            '';
          }
        );
      };
    };
}
