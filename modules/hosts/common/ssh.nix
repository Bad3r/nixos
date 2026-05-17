_:
let
  body = {
    services.openssh.settings = {
      # `flake.nixosModules.ssh` sets PasswordAuthentication to lib.mkDefault
      # false; override at default priority to enable password auth on shared
      # hosts (matches the prior per-host behavior).
      PasswordAuthentication = true;
      PermitRootLogin = "no";
    };
  };
in
{
  flake.nixosModules.hosts-common.imports = [ body ];
}
