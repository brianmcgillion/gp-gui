{
  pkgs,
  crane,
}:

let
  # Rust toolchain
  rustToolchain = pkgs.rust-bin.stable.latest.default.override {
    extensions = [ "rust-src" ];
  };

  # Crane lib for building Rust projects with better caching
  craneLib = (crane.mkLib pkgs).overrideToolchain rustToolchain;

  # Build gp-gui with craneLib
  gp-gui = pkgs.callPackage ./gp-gui {
    inherit craneLib;
  };

in
{
  inherit gp-gui;
}
