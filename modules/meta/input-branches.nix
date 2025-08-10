# Module: meta/input-branches.nix
# Purpose: Manage flake input branches and patches
# Namespace: flake.inputBranches
# Pattern: Golden standard input management
# Reference: Simplified from mightyiam/infra/modules/meta/input-branches.nix

{ lib, config, inputs, ... }:
{
  options.flake.inputBranches = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule {
      options = {
        url = lib.mkOption {
          type = lib.types.str;
          description = "Input URL or branch specification";
        };
        patches = lib.mkOption {
          type = lib.types.listOf lib.types.path;
          default = [];
          description = "Patches to apply to this input";
        };
        branch = lib.mkOption {
          type = lib.types.str;
          default = "main";
          description = "Branch to track";
        };
        shallow = lib.mkOption {
          type = lib.types.bool;
          default = false;
          description = "Whether to use shallow cloning";
        };
      };
    });
    default = {};
    description = "Flake input branch management from golden standard";
  };
  
  config.flake.inputBranches = {
    # Define input branches for core inputs
    nixpkgs = {
      url = "github:NixOS/nixpkgs";
      branch = "nixpkgs-unstable";
      patches = [];
      shallow = true;
    };
    
    stable = {
      url = "github:NixOS/nixpkgs";
      branch = "nixos-24.05";
      patches = [];
      shallow = true;
    };
    
    home-manager = {
      url = "github:nix-community/home-manager";
      branch = "master";
      patches = [];
      shallow = false;
    };
    
    stylix = {
      url = "github:danth/stylix";
      branch = "master";
      patches = [];
      shallow = false;
    };
    
    # Additional inputs can be configured here
    flake-parts = {
      url = "github:hercules-ci/flake-parts";
      branch = "main";
      patches = [];
      shallow = false;
    };
  };
  
  # Provide metadata about configured input branches
  config.flake.inputBranchesMetadata = {
    totalBranches = lib.length (lib.attrNames config.flake.inputBranches);
    branchNames = lib.attrNames config.flake.inputBranches;
    patchedInputs = lib.filterAttrs (name: cfg: cfg.patches != []) config.flake.inputBranches;
  };
}