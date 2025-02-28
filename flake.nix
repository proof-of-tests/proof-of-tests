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

        e2e-test = pkgs.writeShellScriptBin "e2e-test" ''
          # Start the web service
          ${pot-web.apps.${system}.default.program} &
          WEB_PID=$!

          ${pkgs.geckodriver}/bin/geckodriver --port 4444 &
          GECKO_PID=$!

          # Run the tests
          ${self.packages.${system}.e2e}/bin/e2e
          TEST_EXIT=$?

          # Clean up
          kill $WEB_PID
          kill $GECKO_PID
          exit $TEST_EXIT
        '';
      in {
        packages = {
          pot-cli = pot-cli.packages.${system}.default;
          pot-web = pot-web.packages.${system}.default;
          e2e = e2e.packages.${system}.default;
          default = self.packages.${system}.pot-cli;
        };
        devShell = with pkgs;
          mkShell {
            buildInputs = [
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
              geckodriver
            ];
            RUST_SRC_PATH = rustPlatform.rustLibSrc;
          };
        apps = {
          e2e-test = {
            type = "app";
            program = "${e2e-test}/bin/e2e-test";
          };
        };
      }
    );
}
