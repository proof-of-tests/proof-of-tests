{
  inputs = {
    crane.url = "github:ipetkov/crane";
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    utils.url = "github:numtide/flake-utils";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = {
    self,
    nixpkgs,
    utils,
    crane,
    rust-overlay,
  }:
    utils.lib.eachDefaultSystem (
      system: let
        pkgs = import nixpkgs {
          inherit system;
          overlays = [(import rust-overlay)];
        };
        rustToolchain = pkgs.rust-bin.fromRustupToolchainFile ./rust-toolchain.toml;

        # Initialize crane with our custom toolchain
        craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

        rustWasi = rustToolchain.override {
          targets = ["wasm32-wasip1"];
        };
        craneLibWasi = (crane.mkLib pkgs).overrideToolchain rustWasi;

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

        # List of example apps to build
        exampleApps = [
          "hello_pot"
          "fail_randomly"
          "rgeometry-pot"
        ];

        # Function to build a WASM file for an example
        buildWasm = name: let
          exampleSrc = pkgs.lib.cleanSourceWith {
            src = ./examples + "/${name}";
            filter = craneLib.filterCargoSources;
          };
        in
          craneLibWasi.buildPackage {
            src = exampleSrc;
            pname = name;
            version = "0.1.0";
            CARGO_BUILD_TARGET = "wasm32-wasip1";
            doCheck = false;
            cargoArtifacts = null;
            nativeBuildInputs = [pkgs.llvmPackages_latest.lld];
            buildInputs = pkgs.lib.optionals pkgs.stdenv.isDarwin [
              pkgs.darwin.apple_sdk.frameworks.SystemConfiguration
            ];
          };

        # Build all example WASM files
        wasmFiles = pkgs.lib.genAttrs exampleApps buildWasm;

        # Helper function to get the path to a WASM file
        getWasmPath = name: "${wasmFiles.${name}}/lib/${builtins.replaceStrings ["-"] ["_"] name}.wasm";

        # Main crate build
        crate = craneLib.buildPackage commonArgs;

        # Function to verify a WASM file matches the test copy
        verifyWasm = name:
          pkgs.runCommand "verify-${name}-wasm" {
            nativeBuildInputs = [crate];
          } ''
            pot-cli info ${getWasmPath name}
            mkdir -p $out
          '';
      in {
        checks =
          {
            inherit crate;
          }
          // pkgs.lib.genAttrs exampleApps verifyWasm;

        packages =
          {
            default = crate;
            wasm = pkgs.symlinkJoin {
              name = "pot-examples-wasm";
              paths = map getWasmPath exampleApps;
            };
          }
          // wasmFiles;
      }
    );
}
