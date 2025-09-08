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
        url = "https://github.com/NixOS/nixpkgs.git";
        ref = "nixpkgs-unstable";
      };
      shallow = true;
    };
    home-manager.upstream = {
      url = "https://github.com/nix-community/home-manager.git";
      ref = "master";
    };
    stylix.upstream = {
      url = "https://github.com/nix-community/stylix.git";
      ref = "master";
    };
  };

  # Import mitigation module and (optionally) force nixpkgs source to the local input path
  flake.modules.nixos.base = {
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

      # Pre-push hook to ensure submodule commits are pushed
      pre-commit.settings.hooks.check-submodules-pushed = {
        enable = true;
        stages = [ "pre-push" ];
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
            text =
              let
                inputValues = lib.attrValues config.input-branches.inputs;
                chunks = map (v: ''
                  (
                    unset GIT_DIR
                    cd ${v.path_}
                    echo "==> Checking ${v.path_}"
                    current_commit=$(git rev-parse --quiet HEAD)
                    [ -z "$current_commit" ] && {
                      echo "Error: could not find HEAD of submodule ${v.path_}"
                      exit 1
                    }
                    status=$(git status --porcelain)
                    echo "$status" | grep -q . && {
                      echo "Error: submodule ${v.path_} not clean"
                      exit 1
                    }
                    ref='${v.upstream.ref or "master"}'

                    # Detect squashed inputs: commit message contains "squashed upstream <sha>"
                    msg=$(git log -1 --pretty=%B || true)
                    upstream_sha=$(printf "%s" "$msg" | sed -n 's/.*squashed upstream \([0-9a-f]\{7,40\}\).*/\1/p' | head -n1)

                    # Select target commit to verify (prefer embedded upstream sha when present)
                    if [ -n "$upstream_sha" ]; then
                      target_commit="$upstream_sha"
                    else
                      target_commit="$current_commit"
                    fi
                    if [ -n "$upstream_sha" ]; then
                      echo "Detected squashed input; verifying upstream commit $upstream_sha on upstream/$ref"
                    else
                      echo "No squash marker; verifying local HEAD $current_commit on upstream/$ref"
                    fi

                    skip_fetch=""
                    # If we have an upstream sha and the upstream is GitHub, try a lightweight API check first
                    if [ -n "$upstream_sha" ]; then
                      upstream_url=$(git remote get-url upstream 2>/dev/null || true)
                      case "$upstream_url" in
                        https://github.com/*|git@github.com:*)
                          # Normalize to owner/repo without .git
                          owner_repo="$upstream_url"
                          owner_repo="''${owner_repo#git@github.com:}"
                          owner_repo="''${owner_repo#https://github.com/}"
                          owner_repo="''${owner_repo%.git}"
                          owner="''${owner_repo%%/*}"
                          repo="''${owner_repo#*/}"
                          echo "GitHub compare: $owner/$repo $upstream_sha...$ref"
                          if command -v gh >/dev/null 2>&1; then
                            status=$(gh api \
                              "repos/$owner/$repo/compare/$upstream_sha...$ref" \
                              --jq .status 2>/dev/null || true)
                          else
                            resp=$(curl -sSL --connect-timeout 10 --max-time 30 \
                                   -H "Accept: application/vnd.github+json" \
                                   "https://api.github.com/repos/$owner/$repo/compare/$upstream_sha...$ref" || true)
                            status=$(printf "%s" "$resp" | jq -r '.status // empty')
                          fi
                          # Accept when base (upstream_sha) is reachable from head (ref): ahead or identical
                          if [ "$status" = "ahead" ] || [ "$status" = "identical" ]; then
                            echo "GitHub reports commit is reachable on upstream/$ref (status=$status)."
                            skip_fetch=1
                          else
                            [ -n "$status" ] || status="unknown"
                            echo "GitHub API not conclusive (status=$status); will verify via git fetch."
                          fi
                          ;;
                        *) ;;
                      esac
                    fi

                    # Perform a shallow, blobless fetch to minimize data; show progress and fail fast on slow links
                    # Clear any stale shallow.lock to avoid blocked fetches
                    git_dir=$(git rev-parse --git-dir 2>/dev/null || true)
                    if [ -n "$git_dir" ] && [ -f "$git_dir/shallow.lock" ]; then
                      echo "Found stale shallow.lock in $git_dir; removing"
                      rm -f "$git_dir/shallow.lock" || true
                    fi

                    if [ -z "$skip_fetch" ]; then
                      # Initial fetch with progress and low-speed fail-fast; avoid interactive prompts
                      if ! GIT_TERMINAL_PROMPT=0 \
                           GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=30 \
                           timeout 120s git fetch --depth=1 --filter=blob:none --progress -v upstream "$ref"; then
                        echo "Warning: initial fetch failed or timed out for ${v.path_}; attempting shallow deepen"
                      fi

                      # Try to verify ancestry; if history too shallow, deepen incrementally
                      if ! git merge-base --is-ancestor "$target_commit" "upstream/$ref"; then
                        attempts=0
                        while [ $attempts -lt 8 ]; do
                          attempts=$((attempts+1))
                          echo "Deepening history (attempt $attempts/8) for ${v.path_}..."
                          # Clean up possible leftover shallow.lock before deepen
                          git_dir=$(git rev-parse --git-dir 2>/dev/null || true)
                          if [ -n "$git_dir" ] && [ -f "$git_dir/shallow.lock" ]; then
                            echo "Found stale shallow.lock in $git_dir; removing"
                            rm -f "$git_dir/shallow.lock" || true
                          fi

                          if ! GIT_TERMINAL_PROMPT=0 \
                                GIT_HTTP_LOW_SPEED_LIMIT=1000 GIT_HTTP_LOW_SPEED_TIME=30 \
                                timeout 120s git fetch --deepen=100 --filter=blob:none --progress -v upstream "$ref"; then
                            echo "Warning: deepen fetch failed (attempt $attempts) for ${v.path_}"
                            break
                          fi
                          if git merge-base --is-ancestor "$target_commit" "upstream/$ref"; then
                            break
                          fi
                        done
                        if ! git merge-base --is-ancestor "$target_commit" "upstream/$ref"; then
                          echo "Error: submodule ${v.path_} commit $target_commit is not reachable from upstream/$ref"
                          exit 1
                        fi
                      fi
                    fi
                  )
                '') inputValues;
                withHeader = lib.concat [
                  ''
                    set -o xtrace
                  ''
                ] chunks;
              in
              lib.concatLines withHeader;
          }
        );
      };
    };
}
