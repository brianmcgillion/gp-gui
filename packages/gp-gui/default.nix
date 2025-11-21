{
  pkgs,
  craneLib,
}:

let
  # Include only Rust sources (no frontend)
  src = pkgs.lib.sourceFilesBySuffices ./../../. [
    ".rs"
    ".toml"
    ".lock"
  ];

  # Common arguments for crane
  commonArgs = {
    inherit src;
    strictDeps = true;
    pname = "gp-gui";
    version = "1.0.0";

    nativeBuildInputs = with pkgs; [
      pkg-config
      makeWrapper
    ];

    buildInputs = with pkgs; [
      # Iced dependencies
      wayland
      wayland-protocols
      libxkbcommon
      vulkan-loader
      # X11 libraries (for compatibility)
      xorg.libX11
      xorg.libXcursor
      xorg.libXi
      xorg.libXrandr
      # Runtime dependencies
      gpauth
      gpclient
      openconnect
    ];
  };

  # Build dependencies only (cached separately)
  cargoArtifacts = craneLib.buildDepsOnly commonArgs;

in
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;

    postInstall = ''
      # Wrap the GUI to ensure it can find gpauth, gpclient, and openconnect
      wrapProgram $out/bin/gp-gui \
        --prefix PATH : ${
          pkgs.lib.makeBinPath [
            pkgs.gpauth
            pkgs.gpclient
            pkgs.openconnect
          ]
        } \
        --prefix LD_LIBRARY_PATH : ${
          pkgs.lib.makeLibraryPath [
            pkgs.wayland
            pkgs.libxkbcommon
            pkgs.vulkan-loader
            pkgs.xorg.libX11
            pkgs.xorg.libXcursor
            pkgs.xorg.libXi
            pkgs.xorg.libXrandr
          ]
        }
    '';

    # Expose dependencies for inspection
    passthru = {
      runtimeDeps = [
        pkgs.gpauth
        pkgs.gpclient
        pkgs.openconnect
      ];
      inherit cargoArtifacts;
    };

    meta = with pkgs.lib; {
      description = "GUI client for GlobalProtect VPN (Iced UI)";
      homepage = "https://github.com/brianmcgillion/gp-gui";
      license = licenses.gpl3Only;
      platforms = platforms.linux;
      mainProgram = "gp-gui";
    };
  }
)
