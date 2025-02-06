{
  inputs = {
    crane.url = "github:ipetkov/crane";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    utils.url = "github:numtide/flake-utils";
  };

  outputs = {
    self,
    nixpkgs,
    utils,
    crane,
  }:
    utils.lib.eachDefaultSystem (
      system: let
        pkgs = nixpkgs.legacyPackages.${system};
        craneLib = crane.mkLib pkgs;

        # Create a filtered source with WAT and WASM files included
        src = pkgs.lib.cleanSourceWith {
          src = ./.;
          filter = path: type:
            (craneLib.filterCargoSources path type)
            || (type == "regular" && builtins.match ".*\\.wat$" path != null)
            || (type == "regular" && builtins.match ".*\\.wasm$" path != null);
        };

        commonArgs = {
          inherit src;
        };

        crate = craneLib.buildPackage commonArgs;
      in {
        checks = {
          inherit crate;
        };
        packages = {
          default = crate;
        };
      }
    );
}
