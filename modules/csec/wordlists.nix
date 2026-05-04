/*
  csec.wordlists

  Materializes Kali-style wordlist symlinks under /usr/share/wordlists/ for
  packages that ship wordlists in their own share/ subtree, so tutorials,
  scripts, and tools that hardcode the canonical paths "just work" on this
  host.

  Built-in links (matching Kali Linux paths under /usr/share/wordlists/):

  - Every top-level entry under ${pkgs.wordlists}/share/wordlists/ is
    discovered at evaluation time via builtins.readDir, so anything the
    upstream nixpkgs `wordlists` meta-package adds (currently seclists,
    wfuzz, nmap.lst, rockyou.txt) is exposed automatically.
  - Plus three manual entries pointing at packages outside the meta-package:
      * dirbuster   -> ${pkgs.dirbuster}/share/dirbuster
      * metasploit  -> ${pkgs.metasploit}/share/msf/data/wordlists
      * john.lst    -> ${pkgs.john}/share/john/password.lst

  Add more via csec.wordlists.extraLinks; explicit entries override the
  auto-discovered ones if names collide. Hosts opt in by importing
  flake.csec.wordlists and setting csec.wordlists.enable = true.

  Future csec feature modules should export their own
  flake.csec.<name> entry (declared in modules/meta/flake-output.nix as
  attrsOf deferredModule) so each is opt-in independently.

  Note: this module relies on import-from-derivation to read the wordlists
  store path at evaluation time.
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
      manualLinks = {
        dirbuster = "${pkgs.dirbuster}/share/dirbuster";
        metasploit = "${pkgs.metasploit}/share/msf/data/wordlists";
        "john.lst" = "${pkgs.john}/share/john/password.lst";
      };
      builtinLinks = wordlistsAutoLinks // manualLinks;
      links = builtinLinks // cfg.extraLinks;
      dirEntry = {
        mode = "0755";
        user = "root";
        group = "root";
      };
    in
    {
      options.csec.wordlists = {
        enable = lib.mkEnableOption "Kali-style wordlist symlinks under /usr/share/wordlists/";

        path = lib.mkOption {
          type = lib.types.path;
          default = "/usr/share/wordlists";
          description = ''
            Filesystem path under which wordlist symlinks are created.
            The parent directory must already exist (it does for the
            default `/usr/share`); this module never adjusts permissions
            of any directory outside `cfg.path` itself, so configuring a
            user-owned location such as `/home/<user>/wordlists` is safe.
          '';
        };

        extraLinks = lib.mkOption {
          type = lib.types.attrsOf lib.types.path;
          default = { };
          example = lib.literalExpression ''
            {
              rockyou = "''${pkgs.rockyou}/share/wordlists/rockyou.txt";
            }
          '';
          description = ''
            Extra name -> source mappings. Each entry creates
            <path>/<name> as a symlink to the given target. Built-in
            links may be overridden by setting the same attribute name.
          '';
        };
      };

      # Use systemd.tmpfiles.settings (structured interface) so paths and
      # symlink targets containing spaces or special characters are quoted
      # and C-escaped by NixOS rather than interpolated into a space-delimited
      # rule string.
      config = lib.mkIf cfg.enable {
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
