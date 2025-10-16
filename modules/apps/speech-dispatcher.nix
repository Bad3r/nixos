{
  flake.nixosModules.apps."speech-dispatcher" =
    { pkgs, ... }:
    {
      environment.systemPackages = [ pkgs.speechd ];
    };
}
