{
  flake.homeManagerModules.passGpgBootstrap =
    {
      config,
      lib,
      osConfig ? { },
      ...
    }:
    let
      nixosEnabled = lib.attrByPath [
        "programs"
        "sss-pass-gpg-bootstrap"
        "extended"
        "enable"
      ] false osConfig;
      passGpgBootstrap = lib.attrByPath [
        "programs"
        "sss-pass-gpg-bootstrap"
        "extended"
        "package"
      ] null osConfig;
      repoGpg = lib.attrByPath [ "home" "repoGpg" ] { } config;
      keyFingerprint = repoGpg.fingerprint or "";
      keySecret = lib.attrByPath [ "sops" "secrets" "gpg/vx-secret-key" ] null config;
      keyPath = if keySecret == null then null else keySecret.path;
      bootstrapReady = nixosEnabled && passGpgBootstrap != null;
      haveKeyPath =
        bootstrapReady && (repoGpg.available or false) && keyPath != null && keyFingerprint != "";
    in
    {
      home.activation.importPassGpgKey = lib.mkIf haveKeyPath (
        lib.hm.dag.entryAfter [ "writeBoundary" ] ''
          ${lib.getExe passGpgBootstrap} import-key ${lib.escapeShellArg keyPath} ${lib.escapeShellArg keyFingerprint}
        ''
      );

      home.activation.initPassStore = lib.mkIf haveKeyPath (
        lib.hm.dag.entryAfter [ "importPassGpgKey" ] ''
          ${lib.getExe passGpgBootstrap} init-store ${lib.escapeShellArg keyFingerprint}
        ''
      );
    };
}
