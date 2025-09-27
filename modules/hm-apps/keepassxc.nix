/*
  Package: keepassxc
  Description: Cross-platform password manager compatible with KeePass.
  Homepage: https://keepassxc.org/
  Documentation: https://keepassxc.org/docs/
  Repository: https://github.com/keepassxreboot/keepassxc

  Summary:
    * Provides an offline, encrypted vault supporting KDBX files, key files, YubiKey challenge-response, and browser integration.
    * Offers SSH agent, passkey, auto-type, and secret service support for seamless credential workflows across platforms.

  Options:
    --pw-stdin: Read the database password from stdin for scripting.
    --config <file>: Load a custom configuration file.
    --browser: Enable the KeePassXC-Browser integration handshake.
    --version: Show the installed version and exit (useful for CI workflows).

  Example Usage:
    * `keepassxc` — Unlock and manage passwords in an encrypted KDBX database.
    * `keepassxc --pw-stdin ~/vault.kdbx < ~/.config/vault-password` — Automate vault unlock in scripts.
    * `keepassxc-cli show -q -a password ~/vault.kdbx "Web/Example"` — Retrieve a specific entry’s secret via CLI.
*/

{
  flake.homeManagerModules.apps.keepassxc =
    { pkgs, ... }:
    {
      home.packages = [ pkgs.keepassxc ];
    };
}
