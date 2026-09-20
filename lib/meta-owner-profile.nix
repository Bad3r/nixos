let
  fleetSshPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHxTLwyGcLkZ0oxOw9lA/bMgwG/9N0YgJR+jGj2jQxsL ssh@unsigned.sh";
in
{
  username = "vx";
  email = "bad3r@unsigned.sh";
  name = "Bad3r";
  matrix = "@bad3r:matrix.org";

  # Git identity (separate from general email for privacy)
  git = {
    name = "Bad3r";
    email = "25513724+Bad3r@users.noreply.github.com";
  };

  inherit fleetSshPublicKey;
  sshKeys = [ fleetSshPublicKey ];
  gitSigningPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJDNTENPappbhPz4AqjvRmWBO0m2oS/mkej/pgN0F6fM";
}
