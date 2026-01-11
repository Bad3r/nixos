/*
  Package: gopls
  Description: Go language server providing IDE features backed by the Go toolchain.
  Homepage: https://pkg.go.dev/golang.org/x/tools/gopls
  Documentation: https://pkg.go.dev/golang.org/x/tools/gopls#section-readme
  Repository: https://cs.opensource.google/go/x/tools/+/refs/heads/master:gopls/

  Summary:
    * Supplies IDE capabilities such as auto-completion, diagnostics, code navigation, and refactoring hints for Go projects.
    * Integrates with editors via the Language Server Protocol to reuse the standard Go build cache and module metadata.

  Example Usage:
    * `gopls serve` — Start the language server (normally launched by the editor).
    * `gopls check ./...` — Run static analysis against all Go packages in the workspace.
*/
_:
let
  GoplsModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.gopls.extended;
    in
    {
      options.programs.gopls.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable gopls.";
        };

        package = lib.mkPackageOption pkgs "gopls" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.gopls = GoplsModule;
}
