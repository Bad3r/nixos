{
  # Avoid setting a global IdentityAgent so SSH respects SSH_AUTH_SOCK.
  # User-level config (Home Manager) pins the 1Password agent only while its GUI is enabled.
  flake.nixosModules.base =
    { config, lib, ... }:
    {
      # nixpkgs exports SSH_ASKPASS through environment.variables only, which never
      # reaches the user manager; the session variable carries the same value there.
      environment.sessionVariables.SSH_ASKPASS = lib.mkIf config.programs.ssh.enableAskPassword config.programs.ssh.askPassword;
    };
}
