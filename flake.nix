{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
    pot-cli.url = "path:./pot-cli";
    pot-web.url = "path:./pot-web";
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, utils, pot-cli, pot-web, rust-overlay }:
    utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [ (import rust-overlay) ];
        };
      in {
        packages = {
          pot-cli = pot-cli.packages.${system}.default;
          pot-web = pot-web.packages.${system}.default;
          default = self.packages.${system}.pot-cli;
        };
        devShell = with pkgs; mkShell {
          buildInputs = [ cargo rustc rustfmt pre-commit rustPackages.clippy lld wasm-pack wasm-bindgen-cli tailwindcss ];
          RUST_SRC_PATH = rustPlatform.rustLibSrc;
        };
      }
    );
}
