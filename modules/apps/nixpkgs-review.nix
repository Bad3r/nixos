/*
  Package: nixpkgs-review
  Description: Review Nixpkgs pull requests by evaluating and building changed packages.
  Homepage: nil
  Documentation: nil
  Repository: https://github.com/Mic92/nixpkgs-review

  Summary:
    * Builds packages changed by Nixpkgs pull requests and opens a test shell with successful builds.
    * Supports local commit, work-in-progress, subset, report, and GitHub-integrated review workflows.

  Options:
    pr: Review one or more pull requests by number or URL.
    rev: Review a local commit or branch without a pull request.
    wip: Review uncommitted changes; add `--staged` to review staged changes only.
    --post-result: Post a formatted review report as a pull request comment.
    --print-result: Print the review report to the terminal.
    --no-shell: Run non-interactively after builds instead of opening the test shell.
    -p, --package: Limit the review to selected package attributes.
*/
_:
let
  NixpkgsReviewModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs."nixpkgs-review".extended;
    in
    {
      options.programs."nixpkgs-review".extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable nixpkgs-review.";
        };

        package = lib.mkPackageOption pkgs "nixpkgs-review" { };
      };

      config = lib.mkIf cfg.enable {
        environment.systemPackages = [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps."nixpkgs-review" = NixpkgsReviewModule;
}
