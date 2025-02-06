{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    utils.url = "github:numtide/flake-utils";
    worker-build.url = "github:lemmih/nix-flakes?dir=worker-build";
    worker-build.inputs.nixpkgs.follows = "nixpkgs";
    wrangler.url = "github:ryand56/wrangler";
    wrangler.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    alejandra.url = "github:kamadorueda/alejandra/3.1.0";
    alejandra.inputs.nixpkgs.follows = "nixpkgs";
    crane.url = "github:ipetkov/crane";
  };

  outputs = {
    self,
    nixpkgs,
    utils,
    worker-build,
    wrangler,
    rust-overlay,
    alejandra,
    crane,
  }:
    utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import rust-overlay)];
        };
        pinned-wasm-bindgen-cli = pkgs.wasm-bindgen-cli.override {
          version = "0.2.100";
          hash = "sha256-3RJzK7mkYFrs7C/WkhW9Rr4LdP5ofb2FdYGz1P7Uxog=";
          cargoHash = "sha256-tD0OY2PounRqsRiFh8Js5nyknQ809ZcHMvCOLrvYHRE=";
        };
        worker-build-bin = worker-build.packages.${system}.default;
        wrangler-bin = wrangler.packages.${system}.default;

        # Initialize crane with our custom toolchain
        craneLib = (crane.mkLib pkgs).overrideToolchain (p:
          p.rust-bin.stable.latest.default.override {
            targets = ["wasm32-unknown-unknown"];
          });

        pot-web-client-deps = craneLib.buildDepsOnly {
          src = ./.;
          cargoExtraArgs = "--target wasm32-unknown-unknown --features hydrate --no-default-features";
          doCheck = false;
        };

        # Create a derivation for building the client-side Wasm using crane
        pot-web-client = craneLib.buildPackage {
          src = ./.;
          cargoArtifacts = pot-web-client-deps;
          buildPhaseCargoCommand = "HOME=$PWD/tmp wasm-pack build --out-dir pkg --mode no-install --no-typescript --release --target web --out-name client --features hydrate --no-default-features";
          doNotPostBuildInstallCargoBinaries = true;
          installPhaseCommand = ''
            mkdir -p $out/pkg
            cp -r pkg/* $out/pkg/
          '';
          doCheck = false;

          nativeBuildInputs = with pkgs; [
            wasm-pack
            pinned-wasm-bindgen-cli
            binaryen
          ];
        };

        pot-web-server-deps = craneLib.buildDepsOnly {
          src = ./.;
          cargoExtraArgs = "--target wasm32-unknown-unknown --features ssr --no-default-features";
          doCheck = false;
        };

        # Create a derivation for building the server-side Wasm using crane
        pot-web-server = craneLib.buildPackage {
          src = ./.;
          cargoArtifacts = pot-web-server-deps;
          buildPhaseCargoCommand = "HOME=$PWD/tmp worker-build --release --features ssr --no-default-features";
          doNotPostBuildInstallCargoBinaries = true;
          doCheck = false;
          installPhaseCommand = ''
            mkdir -p $out/build
            cp -r build/* $out/build/
          '';

          nativeBuildInputs = with pkgs; [
            worker-build-bin
            pinned-wasm-bindgen-cli
            binaryen
            esbuild
          ];
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
            cp -r ${pot-web-client}/* $out/assets/
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
