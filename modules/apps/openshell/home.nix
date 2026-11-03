_: {
  flake.homeManagerModules.apps.openshell =
    {
      osConfig,
      lib,
      pkgs,
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [ "programs" "openshell" "extended" "enable" ] false osConfig;
      gateway = lib.getExe osConfig.programs.openshell.extended.gatewayPackage;
      tlsDir = "%h/.local/state/openshell/tls";

      # upstream deploy/rpm/gateway.toml.default
      configFile = (pkgs.formats.toml { }).generate "openshell-gateway.toml" {
        openshell = {
          version = 2;
          gateway.compute_driver = "podman";
          drivers.podman.health_check_interval_secs = 10;
        };
      };
    in
    {
      config = lib.mkIf nixosEnabled {
        systemd.user.services.openshell-gateway = {
          Unit = {
            Description = "OpenShell gateway";
            Documentation = "https://docs.nvidia.com/openshell/latest/";
            Wants = [ "podman.socket" ];
            After = [ "podman.socket" ];
          };
          Service = {
            Type = "simple";
            StateDirectory = "openshell/gateway";
            Environment = [
              "OPENSHELL_GATEWAY_CONFIG=${configFile}"
              "OPENSHELL_LOCAL_TLS_DIR=${tlsDir}"
            ];
            ExecStartPre = [
              "${gateway} config preflight"
              "${gateway} generate-certs --output-dir ${tlsDir} --server-san host.openshell.internal"
            ];
            ExecStart = gateway;
            Restart = "on-failure";
            RestartSec = "5s";
            PrivateTmp = true;
            UMask = "0077";
          };
          Install.WantedBy = [ "default.target" ];
        };
      };
    };
}
