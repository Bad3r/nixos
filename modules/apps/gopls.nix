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

{
  flake.nixosModules.apps.gopls =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gopls ];
    };

}
