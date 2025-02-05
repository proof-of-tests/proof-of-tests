{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixpkgs-unstable";
    utils.url = "github:numtide/flake-utils";
    worker-build.url = "github:lemmih/nix-flakes?dir=worker-build";
    worker-build.inputs.nixpkgs.follows = "nixpkgs";
    wrangler.url = "github:ryand56/wrangler";
    wrangler.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    alejandra.url = "github:kamadorueda/alejandra/3.1.0";
    alejandra.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    utils,
    worker-build,
    wrangler,
    rust-overlay,
    alejandra,
  }:
    utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import rust-overlay)];
        };
        worker-build-bin = worker-build.packages.${system}.default;
        wrangler-bin = wrangler.packages.${system}.default;

        # Create a derivation for building the client-side Wasm
        pot-web-client = pkgs.stdenv.mkDerivation {
          name = "pot-web-client";
          src = ./.;

          nativeBuildInputs = with pkgs; [
            (rust-bin.stable.latest.default.override {
              targets = ["wasm32-unknown-unknown"];
            })
            wasm-pack
            pkg-config
            cacert
          ];

          buildPhase = ''
            # Set up temporary directories and environment
            export TMPDIR=$PWD/tmp
            export HOME=$TMPDIR/home

            # Set SSL certificate path
            export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

            # Build client-side wasm
            wasm-pack build --out-dir pkg --no-typescript --release --target web --out-name client --features hydrate --no-default-features
          '';

          installPhase = ''
            mkdir -p $out
            cp -r pkg $out/
          '';
        };

        # Create a derivation for building the server-side Wasm
        pot-web-server = pkgs.stdenv.mkDerivation {
          name = "pot-web-server";
          src = ./.;

          nativeBuildInputs = with pkgs; [
            (rust-bin.stable.latest.default.override {
              targets = ["wasm32-unknown-unknown"];
            })
            worker-build-bin
            pkg-config
            cacert
          ];

          buildPhase = ''
            # Set up temporary directories and environment
            export TMPDIR=$PWD/tmp
            export HOME=$TMPDIR/home

            # Set SSL certificate path
            export SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt
            export NIX_SSL_CERT_FILE=${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt

            # Build server-side wasm
            worker-build --release --features ssr --no-default-features
          '';

          installPhase = ''
            mkdir -p $out
            cp -r build $out/
          '';
        };

        # Create the main pot-web derivation that combines everything
        pot-web = pkgs.stdenv.mkDerivation {
          name = "pot-web";
          src = ./.;

          nativeBuildInputs = with pkgs; [
            tailwindcss
          ];

          buildPhase = ''
            # Generate CSS
            tailwindcss --minify -i $src/style/tailwind.css -o style.css
          '';

          installPhase = ''
            # Create the output directory structure
            mkdir -p $out/assets

            # Copy static files
            cp -r $src/public/* $out/assets/

            # Copy generated CSS
            cp style.css $out/assets/style.css

            # Copy wasm build outputs from other derivations
            cp -r ${pot-web-client}/pkg $out/assets/
            cp -r ${pot-web-server}/build $out/
          '';
        };

        # Create a development environment with a script to run wrangler
        pot-web-dev = pkgs.writeScriptBin "pot-web-dev" ''
          #!${pkgs.bash}/bin/bash

          # Create a temporary directory for the development environment
          WORK_DIR=$(mktemp -d)

          # Link the necessary directories
          ln -s ${pot-web}/assets $WORK_DIR/assets
          ln -s ${pot-web}/build $WORK_DIR/build

          # Copy the wrangler configuration
          cp ${./wrangler.toml} $WORK_DIR/wrangler.toml

          # Change to the work directory
          cd $WORK_DIR

          # Run wrangler in development mode
          exec ${wrangler-bin}/bin/wrangler dev --env prebuilt --live-reload false
        '';
      in {
        packages = {
          inherit pot-web pot-web-client pot-web-server;
          default = pot-web;
        };

        # Add the development app
        apps.default = {
          type = "app";
          program = "${pot-web-dev}/bin/pot-web-dev";
        };

        formatter = alejandra.packages.${system}.default;
      }
    );
}
