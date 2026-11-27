/*
  Package: rip
  Description: Safe rm replacement that moves files to the trash.
  Repository: https://github.com/Bad3r/nixos

  Summary:
    * Moves files and directories to the FreeDesktop trash through trash-cli instead of deleting them.
    * Restores trashed files and lists the ones trashed from the current directory.

  Options:
    -u, --unbury [<path>...]: Restore trashed files, through a picker when no path is given.
    -s, --seance: List files trashed from the current directory.
    -i, --inspect: Show files and confirm before trashing them.
    --empty-trash: Permanently delete everything in the trash.
    --graveyard <path>: Use another trash directory.
    --one-file-system: Skip operands that hold a mount point.

  Notes:
    * `rm` is aliased to `rip`; the agent `rm` shim runs it with rm's own flags only.
    * An operand that is itself a mount point is skipped: trash-put cannot move it intact.
    * Home-filesystem trash entries expire after ten days.
*/
let
  ripModule =
    {
      config,
      lib,
      metaOwner,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.rip.extended;
      owner = metaOwner.username;

      ripWrapper = pkgs.rip.override { trash-cli = cfg.package; };

      ripCompletion = pkgs.writeTextFile {
        name = "rip-zsh-completion";
        destination = "/share/zsh/site-functions/_rip";
        text = ''
          #compdef rip

          # Hand-written completion for the rip wrapper; the flag list must stay
          # in sync with the case-statements in packages/rip.

          _rip_files() {
            # `(#m)` and `$MATCH` require extendedglob; ensure it is set even
            # when the caller's shell disables it. `localoptions` confines the
            # change to this function.
            setopt localoptions extendedglob
            # Mirror the escaping shim trash-cli uses in _trash_files (see
            # _trash-put / _trash-restore on the same fpath). Operate on a
            # copy of `words` because `line` only holds positional args while
            # `CURRENT` indexes `words`; mixing the two leaves the in-progress
            # word in the exclusion set and silently breaks completion when a
            # half-typed path contains a metachar.
            local -a tmp_words
            tmp_words=( "''${words[@]}" )
            tmp_words[CURRENT]=()
            tmp_words=( ''${tmp_words//(#m)[\[\]()\\*?#<>~\^\|]/\\$MATCH} )
            _files -F tmp_words
          }

          _rip() {
            local context state line curcontext="$curcontext"
            typeset -A opt_args

            # Exclusion lists mirror the wrapper's mode_count check: the four
            # mode flags (--empty-trash, -s/--seance, -u/--unbury, positional
            # FILES) are mutually exclusive. -i/--inspect is a trash-mode
            # modifier and is rejected by the wrapper alongside the mode
            # flags, so list it symmetrically. -u/--unbury also excludes the
            # global positional spec (`*`) so files-to-trash completion stops
            # firing once the operator has committed to a restore.
            _arguments -C -s -S \
              '(- *)'{-h,--help}'[print help and exit]' \
              '(--empty-trash --seance -s --unbury -u -i --inspect *)--empty-trash[permanently empty the trash]' \
              '(--empty-trash --seance -s --unbury -u -i --inspect *)'{-s,--seance}'[list files trashed from cwd]' \
              '(--empty-trash --seance -s --unbury -u -i --inspect *)'{-u,--unbury}'[restore trashed files (interactive picker if no PATH)]:*::path to restore:_rip_files' \
              '(--empty-trash --seance -s --unbury -u)'{-i,--inspect}'[inspect (ls -la) and prompt before trashing]' \
              {-f,--force}'[skip all confirmation prompts]' \
              {-v,--verbose}'[explain what is being moved to trash]' \
              '--graveyard=[override trash directory for this invocation]:trash dir:_files -/' \
              {-r,-R,-d,--recursive,--dir}'[rm compat, no-op]' \
              '--one-file-system[skip operands that hold a mount point]' \
              '*:files to trash:_rip_files'
          }

          _rip "$@"
        '';
      };
    in
    {
      options.programs.rip.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable the rip trash wrapper backed by trash-cli.";
        };

        package = lib.mkPackageOption pkgs "trash-cli" { };

        trashPath = lib.mkOption {
          type = lib.types.path;
          default = "/var/cache/Trash";
          description = ''
            Persistent trash store for files on the home filesystem. A
            symlink is created from `~/.local/share/Trash` to this path so
            `trash-cli` treats it as the FreeDesktop "home trash".

            This path must live on the same filesystem (same `st_dev`) as the
            files being trashed. `trash-cli` follows the FreeDesktop Trash
            spec and refuses to use the home trash for any file on a
            different volume, failing with "trash dir and file to be trashed
            are not in the same volume" and then falling back to per-volume
            `.Trash-<uid>` directories that an unprivileged user normally
            cannot create at a mount root. Pointing this at the `/tmp` tmpfs
            therefore breaks trashing every file under `/home` (a separate
            volume), which is why the default is a disk-backed path on the
            root filesystem rather than `/tmp/Trash`.

            The non-replacing `L` form is used for the symlink, so it is
            skipped if anything (real directory, file, or stale symlink with
            a different target) already exists at `~/.local/share/Trash`.
            Changing this option will not retarget an existing symlink:
            remove `~/.local/share/Trash` manually, then rebuild, to pick up
            the new value.

            The directory is created via `systemd.tmpfiles` with the `10d`
            age qualifier, so entries older than ten days are cleaned up
            automatically. Override that rule directly if longer retention is
            required.
          '';
          example = "/home/alice/.local/share/Trash";
        };
      };

      config = lib.mkIf cfg.enable {
        environment.shellAliases.rm = "rip";

        environment.systemPackages = [
          cfg.package
          ripWrapper
          ripCompletion
        ];

        # Bootstrap the trash store and point the XDG home trash at it. The
        # store sits on the same filesystem as the files being trashed (see
        # `trashPath` above), so it survives reboots outside the `/tmp` tmpfs.
        systemd.tmpfiles.settings."rip-trash" = {
          # Create the trash directory; clean entries older than 10 days.
          ${cfg.trashPath}.d = {
            mode = "0700";
            user = owner;
            group = "users";
            age = "10d";
          };
          # Bootstrap the XDG data parent so the symlink below can be placed
          # on freshly provisioned users. Without this, `L` is a no-op when
          # `~/.local/share` does not yet exist and `trash-cli` later
          # materialises `Trash` as a real directory.
          "/home/${owner}/.local/share".d = {
            mode = "0755";
            user = owner;
            group = "users";
          };
          # Point home-partition trash at the configured path. Use `L` (not
          # `L+`) so any existing entry at that path is preserved; users
          # migrating from another trash implementation must move it aside
          # before this symlink takes effect.
          "/home/${owner}/.local/share/Trash".L.argument = cfg.trashPath;
        };
      };
    };
in
{
  flake.nixosModules.apps.rip = ripModule;
}
