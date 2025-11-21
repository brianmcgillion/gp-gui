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

  # Build the setuid wrapper for gp-gui
  gp-gui-wrapper = pkgs.callPackage ./wrapper {
    inherit gp-gui;
    binaryName = "gp-gui";
    binaryPath = "${gp-gui}/bin/gp-gui";
  };

  # Build the setuid wrapper for gpclient
  gpclient-wrapper = pkgs.callPackage ./wrapper {
    gp-gui = pkgs.gpclient; # Use gpclient package
    binaryName = "gpclient";
    binaryPath = "${pkgs.gpclient}/bin/gpclient";
  };

in
{
  inherit gp-gui gp-gui-wrapper gpclient-wrapper;
}
