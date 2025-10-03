{
  config,
  lib,
  ...
}:
let
  owner = config.flake.lib.meta.owner.username;
  rootPath = builtins.toString (config._module.args.rootPath or ../..);
  logseqUpdater = "/home/vx/dotfiles/.local/bin/sss-update-logseq";
  ghqRootModule =
    let
      nixosModules = (config.flake or { }).nixosModules or { };
    in
    lib.attrByPath [ "git" "ghq-root" ] null nixosModules;
  mirrorRepos = [
    "NixOS/nixpkgs"
    "NixOS/nixos-hardware"
    "nix-community/home-manager"
    "nix-community/stylix"
    "nix-community/nixvim"
    "logseq/logseq"
    "cachix/git-hooks.nix"
    "mightyiam/files"
    "Mic92/sops-nix"
    "numtide/treefmt-nix"
    "vic/import-tree"
  ];
in
{
  configurations.nixos.system76.module =
    _:
    let
      base = {
        imports = lib.optional (ghqRootModule != null) ghqRootModule;

        home-manager.users.${owner} = {
          programs.ghqMirror.repos = lib.mkForce mirrorRepos;

          systemd.user.services."logseq-build" = {
            Unit = {
              Description = "Nightly Logseq build";
              After = [ "ghq-mirror.service" ];
              Wants = [ "ghq-mirror.service" ];
            };
            Service = {
              Type = "oneshot";
              Environment = [
                "NIX_CONFIG=experimental-features = nix-command flakes pipe-operators\nabort-on-warn = false\nallow-import-from-derivation = false\naccept-flake-config = true\n"
              ];
              ExecStart = "${lib.escapeShellArg "/run/current-system/sw/bin/nix"} develop ${lib.escapeShellArg rootPath}#logseq --command ${lib.escapeShellArg logseqUpdater}";
            };
          };

          systemd.user.timers."logseq-build" = {
            Unit.Description = "Nightly Logseq rebuild";
            Timer = {
              OnCalendar = "03:30";
              Persistent = true;
            };
            Install.WantedBy = [ "timers.target" ];
          };
        };
      };

      gitCfg = if ghqRootModule != null then { git.ghqRoot.enable = true; } else { };
    in
    base // gitCfg;
}
