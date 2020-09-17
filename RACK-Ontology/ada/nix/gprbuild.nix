{ sources ? import ./nix/sources.nix {}
, nixpkgs ? import sources.nixpkgs {}
}:
let
  xmlada-source = import ./xmlada-source.nix { inherit sources nixpkgs; };
  gprbuild-bootstrap = import ./gprbuild-bootstrap.nix { inherit nixpkgs sources; };
  xmlada-bootstrap = import ./xmlada-bootstrap.nix { inherit nixpkgs sources; };
in
nixpkgs.callPackage ./gprbuild {
  inherit
    gprbuild-bootstrap
    nixpkgs
    sources
    xmlada-bootstrap
    xmlada-source;
}
