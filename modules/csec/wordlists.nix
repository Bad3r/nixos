/*
  csec.wordlists

  Materializes Kali-style wordlist symlinks under /usr/share/wordlists/ for
  packages that ship wordlists in their own share/ subtree, so tutorials,
  scripts, and tools that hardcode the canonical paths "just work" on this
  host.

  Built-in links (matching Kali Linux paths under /usr/share/wordlists/):

  - Every top-level entry under ${pkgs.wordlists}/share/wordlists/ is
    linked at activation time, so anything the upstream nixpkgs `wordlists`
    meta-package adds (e.g. seclists, wfuzz, nmap.lst, rockyou.txt at the
    time of writing) is exposed automatically without realizing the package
    during evaluation.
  - Plus the entries declared in `csec.wordlists.manualLinks`, defaulting
    to enabled packages that ship their wordlists outside the meta-package:
      * dirbuster   -> ${pkgs.dirbuster}/share/dirbuster when
                       programs.dirbuster.extended.enable is true
      * metasploit  -> ${pkgs.metasploit}/share/msf/data/wordlists when
                       programs.metasploit.extended.enable is true
      * john.lst    -> ${pkgs.john}/share/john/password.lst when
                       programs.john.extended.enable is true (single file
                       rather than a directory, intentional Kali parity)

  Hosts that do not need the heavier defaults (metasploit alone is
  ~800 MB) can drop them with `csec.wordlists.manualLinks = { }` or
  override individual entries by name. Add unrelated symlinks via
  `csec.wordlists.extraLinks`; entries in `extraLinks` win over both
  package-provided and manual links when names collide. Hosts opt in by
  importing flake.csec.wordlists and setting csec.wordlists.enable = true.

  Future csec feature modules should export their own
  flake.csec.<name> entry (declared in modules/meta/flake-output.nix as
  attrsOf deferredModule) so each is opt-in independently.

  Note: the package layout checks live in `system.checks`. Upstream layout
  drift fails the system build without forcing package outputs during
  evaluation.
*/
{
  flake.csec.wordlists =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.csec.wordlists;
      wordlistsRoot = "${pkgs.wordlists}/share/wordlists";
      appEnabled =
        name:
        lib.attrByPath [
          "programs"
          name
          "extended"
          "enable"
        ] false config;
      defaultManualLinks =
        lib.optionalAttrs (appEnabled "dirbuster") {
          dirbuster = "${pkgs.dirbuster}/share/dirbuster";
        }
        // lib.optionalAttrs (appEnabled "metasploit") {
          metasploit = "${pkgs.metasploit}/share/msf/data/wordlists";
        }
        // lib.optionalAttrs (appEnabled "john") {
          "john.lst" = "${pkgs.john}/share/john/password.lst";
        };
      linkActivationEntry =
        name: target:
        let
          renderedTarget = toString target;
        in
        ''
          link_name=${lib.escapeShellArg name}
          link_target=${lib.escapeShellArg renderedTarget}
          ln -sfnT "$link_target" "$target_root/$link_name"
        '';
      linksCheck =
        let
          checkEntry =
            name: target:
            let
              renderedTarget = toString target;
            in
            ''
              if [ ! -e ${lib.escapeShellArg renderedTarget} ]; then
                printf '%s\n' ${lib.escapeShellArg "csec.wordlists.manualLinks target does not exist: ${name} -> ${renderedTarget}"} >&2
                missing=1
              fi
            '';
        in
        pkgs.runCommandLocal "csec-wordlists-links-check" { } ''
          missing=0
          if [ ! -d ${lib.escapeShellArg wordlistsRoot} ]; then
            printf '%s\n' ${lib.escapeShellArg "csec.wordlists expected pkgs.wordlists to expose ${wordlistsRoot}"} >&2
            missing=1
          fi
          ${lib.concatStringsSep "\n" (lib.mapAttrsToList checkEntry cfg.manualLinks)}
          if [ "$missing" -ne 0 ]; then
            exit 1
          fi
          touch "$out"
        '';
    in
    {
      options.csec.wordlists = {
        enable = lib.mkEnableOption "Kali-style wordlist symlinks under /usr/share/wordlists/";

        path = lib.mkOption {
          type = lib.types.path;
          default = "/usr/share/wordlists";
          description = ''
            Filesystem path under which wordlist symlinks are created.

            Two contracts apply:

            - The parent directory of `cfg.path` must already exist
              (always true for the default `/usr/share`); this module
              never adjusts permissions of anything outside `cfg.path`
              itself.
            - The directory at `cfg.path` is enforced as
              `0755 root:root` on every activation, so pointing this option
              at a user-owned path such as `/home/<user>/wordlists` will have
              ownership reclaimed by root. Use a system-managed location
              (the default `/usr/share/wordlists`, `/var/lib/wordlists`, etc.)
              unless that behaviour is acceptable.
          '';
        };

        manualLinks = lib.mkOption {
          type = lib.types.attrsOf (lib.types.either lib.types.path lib.types.str);
          default = defaultManualLinks;
          defaultText = lib.literalExpression ''
            lib.optionalAttrs config.programs.dirbuster.extended.enable {
              dirbuster = "''${pkgs.dirbuster}/share/dirbuster";
            } // lib.optionalAttrs config.programs.metasploit.extended.enable {
              metasploit = "''${pkgs.metasploit}/share/msf/data/wordlists";
            } // lib.optionalAttrs config.programs.john.extended.enable {
              "john.lst" = "''${pkgs.john}/share/john/password.lst";
            }
          '';
          description = ''
            Manual name -> store-path mappings for tools whose wordlists
            live outside the `pkgs.wordlists` meta-package. Each target is
            checked by a `system.checks` derivation, so upstream layout changes
            fail when the system is built without forcing package outputs
            during evaluation. Default package-specific links are included only
            when their matching `programs.<name>.extended` app is enabled. Set
            to `{ }` to opt out of the default heavyweight packages (notably
            `metasploit`, ~800 MB).
          '';
        };

        extraLinks = lib.mkOption {
          type = lib.types.attrsOf (lib.types.either lib.types.path lib.types.str);
          default = { };
          example = lib.literalExpression ''
            {
              rockyou = "''${pkgs.rockyou}/share/wordlists/rockyou.txt";
            }
          '';
          description = ''
            Extra name -> source mappings layered on top of the
            automatically linked wordlists and manual links. Each entry creates
            `<path>/<name>` as a symlink to the given target. Names already
            provided by `manualLinks` or the `wordlists` package are overridden
            by entries here.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        system.checks = [ linksCheck ];

        system.activationScripts."csec-wordlists" = {
          supportsDryActivation = true;
          text = ''
            if [ "''${NIXOS_ACTION:-}" != dry-activate ]; then
              target_root=${lib.escapeShellArg (toString cfg.path)}
              wordlists_root=${lib.escapeShellArg wordlistsRoot}
              if [ -e "$target_root" ] && [ ! -d "$target_root" ]; then
                printf '%s\n' "csec.wordlists path exists but is not a directory: $target_root" >&2
                exit 1
              fi

              mkdir -p "$target_root"
              chown root:root "$target_root"
              chmod 0755 "$target_root"

              for source in "$wordlists_root"/*; do
                [ -e "$source" ] || continue
                link_name="''${source##*/}"
                ln -sfnT "$source" "$target_root/$link_name"
              done

              ${lib.concatStringsSep "\n" (lib.mapAttrsToList linkActivationEntry cfg.manualLinks)}
              ${lib.concatStringsSep "\n" (lib.mapAttrsToList linkActivationEntry cfg.extraLinks)}
            fi
          '';
        };
      };
    };
}
