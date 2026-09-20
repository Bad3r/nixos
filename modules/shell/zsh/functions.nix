{
  flake.homeManagerModules.zsh =
    { lib, ... }:
    let
      functionsDir = ./functions;
    in
    {
      programs.zsh = {
        # Each file under ./functions is one autoloaded function, named after the file.
        siteFunctions = lib.mapAttrs (name: _: builtins.readFile (functionsDir + "/${name}")) (
          builtins.readDir functionsDir
        );

        # d's select prompt.
        localVariables.PS3 = "❯ ";

        initContent = lib.mkMerge [
          (lib.mkOrder 1000 ''
            cp() { rsync -lav -HAX -hhh --progress "$@" }
            cpv() { rsync -av -HAX -hhh --out-format="[%t] %o: '%n', size %''''b, Last Modified: %M" "$@" }
            mv() { if (( $# == 1 )); then command mv -vi "$1" .; else command mv -vi "$@"; fi }
            compdef _files cp cpv
          '')

          ''
            set_win_title() { print -Pn "\e]0; %n@%m:%~ \a" }
            precmd_functions+=(set_win_title)
          ''
        ];
      };
    };
}
