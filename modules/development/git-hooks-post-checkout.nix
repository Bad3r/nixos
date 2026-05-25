_: {
  perSystem =
    { pkgs, ... }:
    {
      files.files = [
        {
          path = ".githooks/post-checkout";
          drv = pkgs.writeText "post-checkout" ''
            #!/usr/bin/env bash
            # Managed by Nix. Edit modules/development/git-hooks-post-checkout.nix
            # then run `nix develop -c write-files` to refresh.
            #
            # post-checkout args: $1=prev_head $2=new_head $3=flag (1=branch, 0=file)
            # Fires on `git checkout <branch>` and on `git worktree add`.
            [ "''${3:-0}" = "1" ] || exit 0

            # Borrow submodule object stores from the primary checkout instead of
            # re-fetching multi-gigabyte submodules (e.g. nixpkgs) into every
            # linked worktree. Worktrees share the common git dir, so the primary
            # checkout keeps its submodule clones at <common-dir>/modules/<path>;
            # a linked worktree would otherwise clone fresh copies under
            # <common-dir>/worktrees/<name>/modules/<path>. --reference points the
            # new clone's alternates at the primary store, so the primary checkout
            # must retain those objects (avoid aggressive `git gc`/prune) while
            # linked worktrees exist. A linked worktree only benefits once the
            # primary checkout has initialized the submodule at least once;
            # otherwise the reference path is absent and the clone falls back to a
            # normal fetch.
            git_dir="$(git rev-parse --absolute-git-dir 2>/dev/null || true)"
            common_dir="$(git rev-parse --git-common-dir 2>/dev/null || true)"
            case "$common_dir" in
            /*) ;;
            *) common_dir="$git_dir" ;;
            esac

            git config --file .gitmodules --get-regexp '\.path$' 2>/dev/null |
              while read -r module_key submodule_path; do
                [ -n "$submodule_path" ] || continue
                module_name="''${module_key#submodule.}"
                module_name="''${module_name%.path}"
                [ "$(git config --get "submodule.$module_name.active" 2>/dev/null || echo true)" = "false" ] &&
                  continue

                reference_args=()
                if [ -n "$common_dir" ] && [ "$git_dir" != "$common_dir" ]; then
                  reference_repo="$common_dir/modules/$module_name"
                  [ -d "$reference_repo" ] && reference_args=(--reference "$reference_repo")
                fi

                if ! git submodule update --init --recursive --quiet "''${reference_args[@]}" -- "$submodule_path"; then
                  printf 'post-checkout: submodule update failed for %s (continuing)\n' "$submodule_path" >&2
                fi
              done

            exit 0
          '';
        }
      ];
    };
}
