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
    e2e = {
      url = "path:./e2e";
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
    e2e,
  }:
    utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import rust-overlay)];
        };
        pkgs-unstable = import nixpkgs-unstable {
          inherit system;
        };

        # Only define e2e-test for non-Darwin systems
        e2e-test =
          if (!pkgs.stdenv.isDarwin)
          then
            pkgs.runCommand "e2e-test" {
              nativeBuildInputs = [pkgs.geckodriver];
            } ''
              # Start the web service
              ${self.packages.${system}.pot-web}/bin/pot-web &

              # Start geckodriver
              HOME=$(mktemp -d) geckodriver &

              # Run the tests
              ${self.packages.${system}.e2e}/bin/e2e

              # If we get here, the tests passed
              touch $out
            ''
          else pkgs.runCommand "e2e-test-disabled" {} "echo 'E2E tests are disabled on Darwin' > $out";
      in {
        packages = {
          pot-cli = pot-cli.packages.${system}.default;
          pot-web = pot-web.packages.${system}.default;
          e2e = e2e.packages.${system}.default;
          default = self.packages.${system}.pot-cli;
        };
        devShell = with pkgs;
          mkShell {
            buildInputs =
              [
                cargo
                rustc
                rustfmt
                pre-commit
                rustPackages.clippy
                lld
                wasm-pack
                wasm-bindgen-cli
                tailwindcss
                binaryen
              ]
              ++ lib.optional (!stdenv.isDarwin) geckodriver
              ++ lib.optional (!stdenv.isDarwin) firefox;
            RUST_SRC_PATH = rustPlatform.rustLibSrc;
          };
        checks.e2e = e2e-test;
      }
    );
}
