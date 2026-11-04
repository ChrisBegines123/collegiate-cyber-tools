{
  description = "Bash unit testing environment";

  inputs = {
    nixpkgs.url = "https://channels.nixos.org/nixpkgs-unstable/nixexprs.tar.zst";
  };

  outputs = inputs: {
    devShells = builtins.mapAttrs (system: pkgs: {
      default = pkgs.mkShell {
        packages = with pkgs; [
          bats
          python3
          python3Packages.pytest
        ];
      };
    }) inputs.nixpkgs.legacyPackages;
  };
}
