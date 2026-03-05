{
  # Home-Manager sops declarations for VirusTotal API key
  #
  # Generates ~/.vt.toml with the API key from encrypted secrets.
  # Keep this separate from base HM modules so home-manager checks
  # do not fail when sops is not present in the synthetic check environment.
  flake.homeManagerModules.virustotalSecrets =
    {
      config,
      lib,
      metaOwner,
      secretsRoot,
      ...
    }:
    let
      cfg = config.home.virustotalSecrets;
      vtSecretFile = "${secretsRoot}/virustotal.yaml";
      vtSecretExists = builtins.pathExists vtSecretFile;
      homeDirectory = "/home/${metaOwner.username}";
    in
    {
      options.home.virustotalSecrets.enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to provision Home Manager VirusTotal API key secret.";
      };

      config = lib.mkMerge [
        (lib.mkIf (cfg.enable && vtSecretExists) {
          sops.secrets."virustotal/api-key" = {
            sopsFile = vtSecretFile;
            key = "virustotal_api_key";
          };

          sops.templates.".vt.toml" = {
            content = ''
              apikey="${config.sops.placeholder."virustotal/api-key"}"
            '';
            path = "${homeDirectory}/.vt.toml";
            mode = "0600";
          };
        })

        (lib.mkIf (cfg.enable && !vtSecretExists) {
          warnings = [
            "home.virustotalSecrets.enable is true but ${vtSecretFile} is missing; skipping VirusTotal secret."
          ];
        })
      ];
    };
}
