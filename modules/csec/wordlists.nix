/*
  csec.wordlists

  Materializes Kali-style wordlist symlinks under /usr/share/wordlists/ for
  packages that ship wordlists in their own share/ subtree, so tutorials,
  scripts, and tools that hardcode the canonical paths "just work" on this
  host.

  Built-in links (matching Kali Linux paths under /usr/share/wordlists/):

  - Every top-level entry under ${pkgs.wordlists}/share/wordlists/ is
    discovered at evaluation time via builtins.readDir, so anything the
    upstream nixpkgs `wordlists` meta-package adds (e.g. seclists, wfuzz,
    nmap.lst, rockyou.txt at the time of writing) is exposed
    automatically.
  - Plus the entries declared in `csec.wordlists.manualLinks`, defaulting
    to packages that ship their wordlists outside the meta-package:
      * dirbuster   -> ${pkgs.dirbuster}/share/dirbuster
      * metasploit  -> ${pkgs.metasploit}/share/msf/data/wordlists
      * john.lst    -> ${pkgs.john}/share/john/password.lst (single file
                       rather than a directory, intentional Kali parity)

  Hosts that do not need the heavier defaults (metasploit alone is
  ~800 MB) can drop them with `csec.wordlists.manualLinks = { }` or
  override individual entries by name. Add unrelated symlinks via
  `csec.wordlists.extraLinks`; entries in `extraLinks` win over both
  auto-discovered and manual links when names collide. Hosts opt in by
  importing flake.csec.wordlists and setting csec.wordlists.enable = true.

  Future csec feature modules should export their own
  flake.csec.<name> entry (declared in modules/meta/flake-output.nix as
  attrsOf deferredModule) so each is opt-in independently.

  Note: this module relies on import-from-derivation. `builtins.readDir`
  realises the `pkgs.wordlists` store path during evaluation, and each
  declared `manualLinks` target is checked with `builtins.pathExists` so
  upstream layout drift surfaces as an assertion failure rather than a
  silent dangling symlink.
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
      wordlistsAutoLinks = lib.mapAttrs (name: _type: "${wordlistsRoot}/${name}") (
        builtins.readDir wordlistsRoot
      );
      links = wordlistsAutoLinks // cfg.manualLinks // cfg.extraLinks;
      dirEntry = {
        mode = "0755";
        user = "root";
        group = "root";
      };
      missingManualTargets = lib.filter (name: !builtins.pathExists (toString cfg.manualLinks.${name})) (
        lib.attrNames cfg.manualLinks
      );
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
              `0755 root:root` on every boot via the systemd-tmpfiles
              `d` rule, so pointing this option at a user-owned path
              such as `/home/<user>/wordlists` will have ownership
              reclaimed by root on each activation. Use a
              system-managed location (the default
              `/usr/share/wordlists`, `/var/lib/wordlists`, etc.)
              unless that behaviour is acceptable.
          '';
        };

        manualLinks = lib.mkOption {
          type = lib.types.attrsOf (lib.types.either lib.types.path lib.types.str);
          default = {
            dirbuster = "${pkgs.dirbuster}/share/dirbuster";
            metasploit = "${pkgs.metasploit}/share/msf/data/wordlists";
            "john.lst" = "${pkgs.john}/share/john/password.lst";
          };
          defaultText = lib.literalExpression ''
            {
              dirbuster = "''${pkgs.dirbuster}/share/dirbuster";
              metasploit = "''${pkgs.metasploit}/share/msf/data/wordlists";
              "john.lst" = "''${pkgs.john}/share/john/password.lst";
            }
          '';
          description = ''
            Manual name -> store-path mappings for tools whose wordlists
            live outside the `pkgs.wordlists` meta-package. Each target
            is checked with `builtins.pathExists` at evaluation time, so
            upstream layout changes fail loudly. Set to `{ }` to opt
            out of the default heavyweight packages (notably
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
            auto-discovered and manual links. Each entry creates
            `<path>/<name>` as a symlink to the given target. Names
            already provided by `manualLinks` or auto-discovery are
            overridden by entries here.
          '';
        };
      };

      # Use systemd.tmpfiles.settings (structured interface) so paths and
      # symlink targets containing spaces or special characters are quoted
      # and C-escaped by NixOS rather than interpolated into a space-delimited
      # rule string.
      config = lib.mkIf cfg.enable {
        assertions = [
          {
            assertion = missingManualTargets == [ ];
            message = ''
              csec.wordlists.manualLinks references targets that do not
              exist in the Nix store:
              ${lib.concatMapStringsSep "\n" (
                name: "  - ${name} -> ${toString cfg.manualLinks.${name}}"
              ) missingManualTargets}
              An upstream package layout likely changed; update the
              affected entries (or remove them) in
              `csec.wordlists.manualLinks`.
            '';
          }
        ];

        systemd.tmpfiles.settings."10-csec-wordlists" = {
          "${cfg.path}".d = dirEntry;
        }
        // lib.mapAttrs' (
          name: target:
          lib.nameValuePair "${cfg.path}/${name}" {
            "L+".argument = toString target;
          }
        ) links;
      };
    };
}
