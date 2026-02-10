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
      vtSecretFile = "${secretsRoot}/virustotal.yaml";
      homeDirectory = "/home/${metaOwner.username}";
    in
    {
      config = lib.mkIf (builtins.pathExists vtSecretFile) {
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
      };
    };
}
