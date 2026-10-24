_: {
  flake.homeManagerModules.apps.podman =
    { osConfig, lib, ... }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "podman" "extended" "enable" ] false osConfig;
    in
    {
      config = lib.mkIf nixosEnabled {
        systemd.user = {
          services.podman-prune = {
            Unit.Description = "Prune rootless Podman resources";
            Service = {
              Type = "oneshot";
              ExecStart = "${lib.getExe osConfig.virtualisation.podman.package} system prune --force --filter until=168h";
            };
          };

          timers.podman-prune = {
            Unit.Description = "Prune rootless Podman resources timer";
            Timer = {
              OnCalendar = "weekly";
              Persistent = true;
              RandomizedDelaySec = 1800;
            };
            Install.WantedBy = [ "timers.target" ];
          };
        };
      };
    };
}
