{
  # Avoid setting a global IdentityAgent so SSH respects SSH_AUTH_SOCK.
  # User-level config (Home Manager) pins the 1Password agent only while its GUI is enabled.
  flake.nixosModules.base = { };
}
