/*
  Package: gopass
  Description: Password manager for teams built on top of the `pass` ecosystem with Git and GPG integration.
  Homepage: https://www.gopass.pw/
  Documentation: https://www.gopass.pw/docs/
  Repository: https://github.com/gopasspw/gopass

  Summary:
    * Stores secrets encrypted with GPG and synchronized via Git, providing interactive prompts and templating features for shared credential stores.
    * Supports mounts, OTP generation, YAML entry structures, and integrations with browsers or CI pipelines.

  Options:
    gopass init [--storage fs/git]: Initialize or import password stores with chosen backends.
    gopass show <path>: Display or copy secrets (with `-c` to copy to clipboard).
    gopass insert <path>: Add or update secrets interactively.
    gopass otp <path>: Generate one-time passwords for entries that include OTP seeds.
    gopass sync: Synchronize remote Git repositories for mounted stores.

  Example Usage:
    * `gopass init --store personal` — Initialize a new password store using your GPG key.
    * `gopass insert accounts/github` — Add credentials for GitHub under the specified path.
    * `gopass show -c accounts/github` — Copy the GitHub password to the clipboard without printing it.
*/

{
  flake.nixosModules.apps.gopass =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gopass ];
    };

  flake.nixosModules.base =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.gopass ];
    };
}
