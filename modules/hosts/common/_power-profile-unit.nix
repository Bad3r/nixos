# Shared "force power-profiles-daemon to performance" oneshot unit for hosts
# whose power stack is powerprofilesctl-driven. Not for hosts with their own
# vendor daemon (e.g. system76-power), which need a different ExecStart and
# dependency chain.
pkgs: {
  description = "Force power-profiles-daemon profile to performance";
  wantedBy = [ "graphical.target" ];
  wants = [ "power-profiles-daemon.service" ];
  after = [ "power-profiles-daemon.service" ];
  startLimitBurst = 3;
  startLimitIntervalSec = 3600;
  serviceConfig = {
    Type = "oneshot";
    ExecStart = "${pkgs.power-profiles-daemon}/bin/powerprofilesctl set performance";
    RemainAfterExit = true;
    Restart = "on-failure";
    RestartSec = 3;
  };
}
