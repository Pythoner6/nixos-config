{
  description = "nixos flake";
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    lanzaboote = {
      #url = "github:nix-community/lanzaboote/v0.3.0";
      url = "github:nix-community/lanzaboote/v0.4.1";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.crane.follows = "crane";
      inputs.rust-overlay.follows = "rust-overlay";
    };
    nixos-cosmic = {
      url = "github:lilyinstarlight/nixos-cosmic";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.nixpkgs-stable.follows = "nixpkgs";
    };
    crane = {
      url = "github:ipetkov/crane";
    };
    rust-overlay = {
      url = "github:oxalica/rust-overlay";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };
  outputs = { self, nixpkgs, lanzaboote, nixos-cosmic, crane, rust-overlay }: {
    #packages.x86_64-linux.cosmic-askpass = nixpkgs.legacyPackages.x86_64-linux.callPackage ./cosmic-askpass {};
    packages.x86_64-linux.cosmic-askpass = ((crane.mkLib (import nixpkgs {system = "x86_64-linux"; overlays=[(import rust-overlay)];})).overrideToolchain (p: p.rust-bin.stable.latest.default)).buildPackage {
      src = ./cosmic-askpass;
      nativeBuildInputs = [ nixos-cosmic.packages.x86_64-linux.libcosmicAppHook ];
    };
    devShells.x86_64-linux.default = nixpkgs.legacyPackages.x86_64-linux.mkShell {
      buildInputs = with nixpkgs.legacyPackages.x86_64-linux; [ cargo ];
    };
    nixosConfigurations = {
      laptop = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./configuration.nix
	  ({ ... }: { nix.registry.nixpkgs.flake = nixpkgs; })
          lanzaboote.nixosModules.lanzaboote
          nixos-cosmic.nixosModules.default
          ({ pkgs, lib, ... }: {
            environment.systemPackages = [ pkgs.sbctl ];
            boot.loader.systemd-boot.enable = lib.mkForce false;
            boot.lanzaboote = {
              enable = true;
              pkiBundle = "/etc/secureboot";
            };
          })
        ];
      };
    };
  };
}
