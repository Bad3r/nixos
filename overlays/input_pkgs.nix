inputs: final: _prev: {
  # When applied, the stable nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.stable'
  stable = import inputs.nixpkgs-stable {
    system = final.system;
    config.allowUnfree = true;
  };

  # When applied, the master nixpkgs set (declared in the flake inputs) will
  # be accessible through 'pkgs.master'
  master = import inputs.nixpkgs-master {
    system = final.system;
    config.allowUnfree = true;
  };

}
