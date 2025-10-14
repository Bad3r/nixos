{
  flake.nixosModules.apps."command-not-found" =
    { pkgs, ... }:
    let
      perl = pkgs.perl.withPackages (p: [
        p.DBDSQLite
        p.StringShellQuote
      ]);
      commandNotFound = pkgs.replaceVarsWith {
        name = "command-not-found";
        dir = "bin";
        src = "${pkgs.path}/nixos/modules/programs/command-not-found/command-not-found.pl";
        isExecutable = true;
        replacements = {
          dbPath = "/nix/var/nix/profiles/per-user/root/channels/nixos/programs.sqlite";
          inherit perl;
        };
      };
    in
    {
      environment.systemPackages = [ commandNotFound ];
    };
}
