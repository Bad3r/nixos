/*
  Package: 1password-cli
  Description: 1Password command-line tool.
  Homepage: https://developer.1password.com/docs/cli/
  Documentation: https://developer.1password.com/docs/cli/reference/
  Repository: nil

  Summary:
    * Provides the `op` command for account, vault, item, and secret-reference workflows.
    * Supports automation through JSON output, shell completion, and `op://` secret references.

  Options:
    account: Manage accounts configured for the CLI.
    item: Create, edit, list, get, and delete vault items.
    read: Resolve an `op://` secret reference and print its value.
    run: Start a command with environment variables populated from secret references.

  Notes:
    * Uses nixpkgs package `pkgs._1password-cli`; the app key omits the leading underscore for repo module discovery.
    * Delegates runtime wrapper setup to nixpkgs' `programs._1password` module.
*/
_:
let
  OnePasswordCliModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."1password-cli".extended;
    in
    {
      options.programs."1password-cli".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable 1password-cli.";
        };

        package = lib.mkPackageOption pkgs "_1password-cli" { };
      };

      config = lib.mkIf cfg.enable {
        programs._1password = {
          enable = true;
          inherit (cfg) package;
        };

        environment.interactiveShellInit = lib.mkAfter ''
          export OP_PLUGIN_ALIASES_SOURCED=1
          alias cachix="op plugin run -- cachix"
          alias gh="op plugin run -- gh"
          alias glab="op plugin run -- glab"
          alias wrangler="op plugin run -- wrangler"
        '';
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "1password-cli" ];
  flake.nixosModules.apps."1password-cli" = OnePasswordCliModule;
}
