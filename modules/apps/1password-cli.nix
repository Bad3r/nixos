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
      pluginAliasLines = lib.concatMapStringsSep "\n" (
        tool: ''alias ${tool}="op plugin run -- ${tool}"''
      ) cfg.pluginAliases;
    in
    {
      options.programs."1password-cli".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable 1password-cli.";
        };

        package = lib.mkPackageOption pkgs "_1password-cli" { };

        pluginAliases = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          example = [
            "cachix"
            "gh"
            "glab"
            "wrangler"
          ];
          description = ''
            Tools to alias to `op plugin run -- <tool>`. Each entry must
            have already been initialised on this host with
            `op plugin init <tool>`; otherwise every invocation exits
            non-zero with "no plugin configured". Default is empty so a
            fresh checkout does not silently break interactive shells.
          '';
        };
      };

      config = lib.mkIf cfg.enable {
        programs._1password = {
          enable = true;
          inherit (cfg) package;
        };

        environment.interactiveShellInit = lib.mkIf (cfg.pluginAliases != [ ]) (
          lib.mkAfter ''
            export OP_PLUGIN_ALIASES_SOURCED=1
            ${pluginAliasLines}
          ''
        );
      };
    };
in
{
  nixpkgs.allowedUnfreePackages = [ "1password-cli" ];
  flake.nixosModules.apps."1password-cli" = OnePasswordCliModule;
}
