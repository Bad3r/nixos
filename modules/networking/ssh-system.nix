{
  # Avoid setting a global IdentityAgent so SSH respects SSH_AUTH_SOCK.
  # User-level config (Home Manager) sets the stable gpg-agent symlink.
  flake.nixosModules.base = { };
}
