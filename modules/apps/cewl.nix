/*
  Package: cewl
  Description: Custom wordlist generator for spidering sites and extracting words, emails, and document metadata.
  Homepage: https://digi.ninja/projects/cewl.php/
  Documentation: https://digi.ninja/projects/cewl.php/
  Repository: https://github.com/digininja/CeWL

  Summary:
    * Crawls a target site to build custom wordlists for password auditing and content analysis.
    * Can also extract email addresses and author metadata from pages and linked documents.

  Options:
    -d <x>: Set crawl depth; defaults to 2.
    -m <x>: Set the minimum word length included in the output list.
    -w <file>: Write the generated wordlist to a file instead of stdout.
    -a: Include author and document metadata discovered during crawling.
    --allowed: Restrict followed paths to URLs matching a regular expression.
    --with-numbers: Keep words that contain digits instead of letters only.

  Notes:
    * Adds a local overlay so `pkgs.cewl` includes the `getoptlong` gem missing from the pinned nixpkgs package.
    * The overlay reuses the pinned nixpkgs CeWL package directory as the Bundler gemdir and fails explicitly if nixpkgs moves it.
*/
_:
let
  CewlModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.programs.cewl.extended;

      gemfile = builtins.toFile "cewl-Gemfile" ''
        source 'https://rubygems.org'
        gem 'getoptlong'
        gem 'mime'
        gem 'mime-types', ">=3.3.1"
        gem 'mini_exiftool'
        gem 'nokogiri'
        gem 'rexml'
        gem 'rubyzip'
        gem 'spider'
      '';

      lockfile = builtins.toFile "cewl-Gemfile.lock" ''
        GEM
          remote: https://rubygems.org/
          specs:
            getoptlong (0.2.1)
            logger (1.7.0)
            mime (0.4.4)
            mime-types (3.7.0)
              logger
              mime-types-data (~> 3.2025, >= 3.2025.0507)
            mime-types-data (3.2025.0924)
            mini_exiftool (2.14.0)
              ostruct (>= 0.6.0)
              pstore (>= 0.1.3)
            mini_portile2 (2.8.9)
            nokogiri (1.18.10)
              mini_portile2 (~> 2.8.2)
              racc (~> 1.4)
            ostruct (0.6.3)
            pstore (0.2.0)
            racc (1.8.1)
            rexml (3.4.4)
            rubyzip (3.2.2)
            spider (0.7.0)

        PLATFORMS
          ruby

        DEPENDENCIES
          getoptlong
          mime
          mime-types (>= 3.3.1)
          mini_exiftool
          nokogiri
          rexml
          rubyzip
          spider

        BUNDLED WITH
           2.7.2
      '';

      gemset = builtins.toFile "cewl-gemset.nix" ''
        {
          getoptlong = {
            groups = [ "default" ];
            platforms = [ ];
            source = {
              remotes = [ "https://rubygems.org" ];
              sha256 = "198vy9dxyzibqdbw9jg8p2ljj9iknkyiqlyl229vz55rjxrz08zx";
              type = "gem";
            };
            version = "0.2.1";
          };
          logger = {
            groups = [ "default" ];
            platforms = [ ];
            source = {
              remotes = [ "https://rubygems.org" ];
              sha256 = "00q2zznygpbls8asz5knjvvj2brr3ghmqxgr83xnrdj4rk3xwvhr";
              type = "gem";
            };
            version = "1.7.0";
          };
          mime = {
            groups = [ "default" ];
            platforms = [ ];
            source = {
              remotes = [ "https://rubygems.org" ];
              sha256 = "0nskys7brz2bylhxiknl0z9i19w3wb1knf0h93in6mjq70jdw5cr";
              type = "gem";
            };
            version = "0.4.4";
          };
          mime-types = {
            dependencies = [
              "logger"
              "mime-types-data"
            ];
            groups = [ "default" ];
            platforms = [ ];
            source = {
              remotes = [ "https://rubygems.org" ];
              sha256 = "0mjyxl7c0xzyqdqa8r45hqg7jcw2prp3hkp39mdf223g4hfgdsyw";
              type = "gem";
            };
            version = "3.7.0";
          };
          mime-types-data = {
            groups = [ "default" ];
            platforms = [ ];
            source = {
              remotes = [ "https://rubygems.org" ];
              sha256 = "0a27k4jcrx7pvb0p59fn1frh14iy087c2aygrdkmgwsrbshvqxpj";
              type = "gem";
            };
            version = "3.2025.0924";
          };
          mini_exiftool = {
            dependencies = [
              "ostruct"
              "pstore"
            ];
            groups = [ "default" ];
            platforms = [ ];
            source = {
              remotes = [ "https://rubygems.org" ];
              sha256 = "0b9k99l0k2jl1jgbhrpr4q6ws366gm4zkzzyvvpxv25isxbdwnf5";
              type = "gem";
            };
            version = "2.14.0";
          };
          mini_portile2 = {
            groups = [ "default" ];
            platforms = [ ];
            source = {
              remotes = [ "https://rubygems.org" ];
              sha256 = "12f2830x7pq3kj0v8nz0zjvaw02sv01bqs1zwdrc04704kwcgmqc";
              type = "gem";
            };
            version = "2.8.9";
          };
          nokogiri = {
            dependencies = [
              "mini_portile2"
              "racc"
            ];
            groups = [ "default" ];
            platforms = [ ];
            source = {
              remotes = [ "https://rubygems.org" ];
              sha256 = "1hcwwr2h8jnqqxmf8mfb52b0dchr7pm064ingflb78wa00qhgk6m";
              type = "gem";
            };
            version = "1.18.10";
          };
          ostruct = {
            groups = [ "default" ];
            platforms = [ ];
            source = {
              remotes = [ "https://rubygems.org" ];
              sha256 = "04nrir9wdpc4izqwqbysxyly8y7hsfr4fsv69rw91lfi9d5fv8lm";
              type = "gem";
            };
            version = "0.6.3";
          };
          pstore = {
            groups = [ "default" ];
            platforms = [ ];
            source = {
              remotes = [ "https://rubygems.org" ];
              sha256 = "1a3lrq8k62n8bazhxgdmjykni9wv0mcjks5vi1g274i3wblcgrfn";
              type = "gem";
            };
            version = "0.2.0";
          };
          racc = {
            groups = [ "default" ];
            platforms = [ ];
            source = {
              remotes = [ "https://rubygems.org" ];
              sha256 = "0byn0c9nkahsl93y9ln5bysq4j31q8xkf2ws42swighxd4lnjzsa";
              type = "gem";
            };
            version = "1.8.1";
          };
          rexml = {
            groups = [ "default" ];
            platforms = [ ];
            source = {
              remotes = [ "https://rubygems.org" ];
              sha256 = "0hninnbvqd2pn40h863lbrn9p11gvdxp928izkag5ysx8b1s5q0r";
              type = "gem";
            };
            version = "3.4.4";
          };
          rubyzip = {
            groups = [ "default" ];
            platforms = [ ];
            source = {
              remotes = [ "https://rubygems.org" ];
              sha256 = "0g2vx9bwl9lgn3w5zacl52ax57k4zqrsxg05ixf42986bww9kvf0";
              type = "gem";
            };
            version = "3.2.2";
          };
          spider = {
            groups = [ "default" ];
            platforms = [ ];
            source = {
              remotes = [ "https://rubygems.org" ];
              sha256 = "0v9pshmv9k19pld2a57c9zarab5gjdd239xa9b1qr0x8ndf2c3bb";
              type = "gem";
            };
            version = "0.7.0";
          };
        }
      '';
    in
    {
      options.programs.cewl.extended = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to enable cewl.";
        };

        package = lib.mkPackageOption pkgs "cewl" { };
      };

      config = {
        # Overlay is unconditional so `pkgs.cewl` resolves to the fixed runtime
        # for package-option consumers and ad-hoc host package access.
        nixpkgs.overlays = [
          (
            _final: prev:
            let
              cewlGemdir = prev.path + "/pkgs/by-name/ce/cewl";
              rubyEnv = prev.bundlerEnv {
                name = "cewl-ruby-env";
                gemdir =
                  if builtins.pathExists cewlGemdir then
                    cewlGemdir
                  else
                    throw "cewl overlay: expected nixpkgs CeWL package directory at ${toString cewlGemdir}";
                inherit gemfile lockfile gemset;
              };
            in
            {
              cewl = prev.cewl.overrideAttrs (_: {
                buildInputs = [ rubyEnv.wrappedRuby ];
              });
            }
          )
        ];

        environment.systemPackages = lib.mkIf cfg.enable [ cfg.package ];
      };
    };
in
{
  flake.nixosModules.apps.cewl = CewlModule;
}
