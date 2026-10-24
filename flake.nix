{
  description = "MyLSM database and development environment";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    bend = {
      url = "github:bendlang/bend/295e996574573e3a88827b1cf7045b437333c8f0";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    bolt = {
      url = "github:Emerging-Patterns/bolt/71d0cf2bdf1898824868bf65351c405a51766520";
      flake = false;
    };
    ez = {
      url = "github:Emerging-Patterns/ez/166a23c54b1c5a7bf587abd3d906332bd73a856b";
      flake = false;
    };
  };

  outputs =
    inputs@{ self, nixpkgs, ... }:
    let
      systems = [
        "aarch64-darwin"
        "aarch64-linux"
        "x86_64-linux"
      ];
      eachSystem = nixpkgs.lib.genAttrs systems;
      systemOutputs = eachSystem (
        system:
        let
          pkgs = nixpkgs.legacyPackages.${system};
          bend = inputs.bend.packages.${system}.default;
          ez = import "${inputs.ez}/nix/lib.nix" { inherit pkgs bend; };
          bendLib = ez.bendLib ./ez.lock.toml;
          mylsm = pkgs.callPackage ./nix/package.nix {
            inherit bend bendLib;
            bendLicense = "${inputs.bend}/LICENSE";
          };
          bolt =
            (ez.mkPackage {
              inherit bend;
              src = inputs.bolt;
              version = inputs.bolt.shortRev;
              wrapFlags = [
                "+RTS"
                "--gpu"
                "off"
                "-RTS"
              ];
            }).overrideAttrs
              (_: {
                CC = "${pkgs.clang}/bin/clang";
              });
          nixfmt = pkgs.writeShellApplication {
            name = "nixfmt";
            meta.mainProgram = "nixfmt";
            text = ''
              exec ${pkgs.nixfmt}/bin/nixfmt --width=200 "$@"
            '';
          };
          formatter = pkgs.nixfmt-tree.override { nixfmtPackage = nixfmt; };
          application = {
            type = "app";
            program = "${mylsm}/bin/mylsm";
            meta.description = "Run MyLSM";
          };
        in
        {
          inherit formatter;
          packages = {
            inherit bend bolt mylsm;
            default = mylsm;
          };
          apps = {
            default = application;
            mylsm = application;
          };
          checks = {
            installation = pkgs.callPackage ./nix/check-installation.nix { inherit mylsm; };
            formatting = formatter.check self;
          };
          devShells.default = (pkgs.mkShell.override { stdenv = pkgs.clangStdenv; }) {
            inputsFrom = [ mylsm ];
            BEND_LIB = bendLib;
            packages =
              with pkgs;
              [
                bend
                bolt
                nixfmt
                formatter
                lefthook
                bashInteractive
                git
                coreutils
                findutils
                gnugrep
                gnused
                gawk
                ripgrep
                curl
                cacert
                python3
                nodejs
                bun
              ]
              ++ lib.optional stdenv.hostPlatform.isLinux util-linux;
          };
        }
      );
    in
    {
      packages = eachSystem (system: systemOutputs.${system}.packages);
      apps = eachSystem (system: systemOutputs.${system}.apps);
      checks = eachSystem (system: systemOutputs.${system}.checks);
      devShells = eachSystem (system: systemOutputs.${system}.devShells);
      formatter = eachSystem (system: systemOutputs.${system}.formatter);
    };
}
