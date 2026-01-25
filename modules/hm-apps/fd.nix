/*
  Package: fd
  Description: Simple, fast and user-friendly alternative to find.
  Homepage: https://github.com/sharkdp/fd
  Documentation: https://github.com/sharkdp/fd#readme
  Repository: https://github.com/sharkdp/fd

  Summary:
    * Provides blazing fast recursive file search with smart case matching, regex support, and parallel traversal.
    * Integrates with fdignore/gitignore, advanced filtering, and command execution hooks for pairing with other tools.

  Options:
    --extension <ext>: Restrict matches to a file extension (e.g., `rs`, `md`).
    --type f|d|x: Filter by file, directory, or executable type.
    --exec <cmd> {} \;: Run a command for each match.
    --hidden --no-ignore: Include hidden files and disable ignore rules.

  Example Usage:
    * `fd config ~/.config` -- Quickly locate configuration files under a directory tree.
    * `fd --extension rs --exec rustfmt {}` -- Format all Rust files discovered by fd.
    * `fd '^Dockerfile$' --hidden --strip-cwd-prefix` -- Find Dockerfiles anywhere in the repo while producing clean paths.
*/

{
  flake.homeManagerModules.apps.fd =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.fd.extended;
    in
    {
      options.programs.fd.extended = {
        enable = lib.mkEnableOption "Simple, fast and user-friendly alternative to find.";
      };

      config = lib.mkIf cfg.enable {
        home.packages = [ pkgs.fd ];
      };
    };
}
