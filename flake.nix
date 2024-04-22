{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=master";
    systems.url = "github:nix-systems/default";
    devenv.url = "github:cachix/devenv";
    devenv.inputs.nixpkgs.follows = "nixpkgs";
    nix-filter.url = "github:numtide/nix-filter";
    nix-utils.url = "github:smunix/nix-utils";
    llvm-codegen.url =
      "github:luc-tielen/llvm-codegen?rev=83b04cb576208ea74ddd62016e4fa03f0df138ac";
    llvm-codegen.flake = false;
    souffle-haskell.url =
      "github:luc-tielen/souffle-haskell?rev=e441c84f1d64890e31c92fbb278c074ae8bcaff5";
    souffle-haskell.flake = false;
    diagnose.url =
      "github:luc-tielen/diagnose?rev=24a1d7a2b716d74c1fe44d47941a76c9f5a90c23";
    diagnose.flake = false;
  };

  nixConfig = {
    extra-trusted-public-keys =
      "devenv.cachix.org-1:w1cLUi8dv3hnoSPGAuibQv+f9TZLr6cv/Hm9XgU50cw=";
    extra-substituters = "https://devenv.cachix.org";
  };

  outputs = { self, nixpkgs, devenv, systems, ... }@inputs:
    with inputs.nix-filter.lib;
    with inputs.nix-utils.lib;
    let forEachSystem = nixpkgs.lib.genAttrs (import systems);
    in {
      packages = forEachSystem (system: {
        devenv-up = self.devShells.${system}.default.config.procfileScript;
      });

      devShells = forEachSystem (system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config = { allowBroken = true; };
          };
          llvmVersion = 18;
          llvm = pkgs."llvmPackages_${toString llvmVersion}";
          hpkgs = fast pkgs.haskell.packages.ghc98 [
            {
              modifiers = with pkgs.haskell.lib; [
                dontCheck
                dontHaddock
                disableLibraryProfiling
              ];
              extension = with pkgs.haskell.lib;
                hf: hp:
                with hf; {
                  souffle-haskell = with pkgs;
                    overrideCabal (dontCheck (callCabal2nix "souffle-haskell"
                      (filter {
                        root = inputs.souffle-haskell;
                        exclude = [ (matchExt "cabal") ];
                      }) { })) {
                        postPatch = ''
                          ${pkgs.git}/bin/git apply ${inputs.self}/patches/01-cbits-souffle-haskell.patch
                          ${pkgs.git}/bin/git apply ${inputs.self}/patches/02-lib-souffle-haskell.patch
                          substituteInPlace lib/Language/Souffle/Interpreted.hs \
                            --replace-fail "_locateSouffle_" "pure $ Just \"${souffle}/bin/souffle\""
                        '';
                      };
                  eclair-lang = appendConfigureFlags
                    (callCabal2nix "eclair-lang" (filter {
                      root = inputs.self;
                      exclude = [ (matchExt "cabal") ("cabal.project") ];
                    }) { }) [
                      "--ghc-option=-optl=-L${llvm.libllvm.lib}/lib"
                      "--ghc-option=-optl=-I${llvm.llvm.dev}/include"
                      "--ghc-option=-optl=-lLLVM-${toString llvmVersion}"
                    ];
                };
            }
            {
              modifiers = with pkgs.haskell.lib; [
                doCheck
                dontHaddock
                disableLibraryProfiling
              ];
              extension = with pkgs.haskell.lib;
                hf: hp:
                with hf; {
                  diagnose = callCabal2nix "diagnose" (filter {
                    root = inputs.diagnose;
                    exclude = [ "Setup.hs" ];
                  }) { };

                  llvm-codegen = appendConfigureFlags
                    (callCabal2nix "llvm-codegen" (filter {
                      root = inputs.llvm-codegen;
                      exclude = [ "Setup.hs" ];
                    }) { llvm-config = llvm.llvm; }) [
                      "--ghc-option=-optl=-L${llvm.libllvm.lib}/lib"
                      "--ghc-option=-optl=-I${llvm.llvm.dev}/include"
                      "--ghc-option=-optl=-lLLVM-${toString llvmVersion}"
                    ];
                };
            }
          ];
        in {
          default = devenv.lib.mkShell {
            inherit inputs pkgs;
            modules = [{
              env = with pkgs; { SOUFFLE_BIN = "${souffle}/bin/souffle"; };
              packages = with hpkgs;
                with pkgs; [
                  hello
                  fourmolu
                  git
                  souffle
                  (ghcWithPackages (p:
                    with p; [
                      cabal-install
                      diagnose
                      eclair-lang
                      ghcid
                      hspec-discover
                      llvm-codegen
                      haskell-language-server
                      implicit-hie
                      souffle-haskell
                    ]))
                ];

              enterShell = ''
                rm cabal.project
                gen-hie --cabal &> hie.yaml
                hpack -f package.yaml
              '';

              processes.run.exec = "hello";
            }];
          };
        });
    };
}
