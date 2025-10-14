{
  flake.nixosModules.apps."ld-library-path" =
    { pkgs, ... }:
    let
      script = pkgs.writeShellScriptBin "ld-library-path" ''
        if [ -z "$LD_LIBRARY_PATH" ]; then
          printf 'LD_LIBRARY_PATH is not set\n'
        else
          printf '%s\n' "$LD_LIBRARY_PATH"
        fi
      '';
    in
    {
      environment.systemPackages = [ script ];
    };
}
