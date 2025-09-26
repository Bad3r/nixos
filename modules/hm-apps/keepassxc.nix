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
    keepassxc: Launch the desktop GUI for vault management.
    keepassxc --pw-stdin: Read the database password from stdin for scripting.
    keepassxc --config <file>: Load a custom configuration file.
    keepassxc --browser: Enable the KeePassXC-Browser integration handshake.
    keepassxc-cli <command>: Use the CLI toolkit for operations like `ls`, `show`, and `diceware`.

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
