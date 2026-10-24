# /data/agents is the TMPDIR agents utilize instead of /tmp.
{ metaOwner, ... }:
{
  flake.nixosModules.hosts-common = {
    systemd.tmpfiles.settings."10-agents-scratch"."/data/agents".d = {
      user = metaOwner.username;
      group = "users";
      mode = "0700";
    };
  };
}
