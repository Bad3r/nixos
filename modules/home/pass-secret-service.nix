{
  flake.homeManagerModules.passGpgBootstrap =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      repoGpg = lib.attrByPath [ "home" "repoGpg" ] { } config;
      keyFingerprint = repoGpg.fingerprint or "";
      keySecret = lib.attrByPath [ "sops" "secrets" "gpg/vx-secret-key" ] null config;
      keyPath = if keySecret == null then null else keySecret.path;
      haveKeyPath = (repoGpg.available or false) && keyPath != null && keyFingerprint != "";
      passGpgBootstrap = pkgs."sss-pass-gpg-bootstrap";
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
