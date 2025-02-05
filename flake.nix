{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    utils.url = "github:numtide/flake-utils";
    pot-cli = {
      url = "path:./pot-cli";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    pot-web = {
      url = "path:./pot-web";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = {
    self,
    nixpkgs,
    utils,
    pot-cli,
    pot-web,
    rust-overlay,
  }:
    utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import rust-overlay)];
        };
      in {
        packages = {
          pot-cli = pot-cli.packages.${system}.default;
          pot-web = pot-web.packages.${system}.default;
          default = self.packages.${system}.pot-cli;
        };
        devShell = with pkgs;
          mkShell {
            buildInputs = [cargo rustc rustfmt pre-commit rustPackages.clippy lld wasm-pack wasm-bindgen-cli tailwindcss binaryen];
            RUST_SRC_PATH = rustPlatform.rustLibSrc;
          };
      }
    );
}
