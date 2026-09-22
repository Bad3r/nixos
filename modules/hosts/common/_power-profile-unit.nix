# Shared "force power-profiles-daemon to performance" oneshot unit for hosts
# whose power stack is powerprofilesctl-driven. A host running a vendor power
# daemon instead needs its own ExecStart and dependency chain.
# profile/command are reused by the resume hooks and the i3 power-profile menu.
pkgs:
let
  profile = "performance";
  command = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set ${profile}";
in
{
  inherit profile command;
  unit = {
    description = "Force power-profiles-daemon profile to performance";
    wantedBy = [ "graphical.target" ];
    wants = [ "power-profiles-daemon.service" ];
    after = [ "power-profiles-daemon.service" ];
    startLimitBurst = 3;
    startLimitIntervalSec = 3600;
    serviceConfig = {
      Type = "oneshot";
      ExecStart = command;
      RemainAfterExit = true;
      Restart = "on-failure";
      RestartSec = 3;
    };
  };
}
