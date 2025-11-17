{
  pkgs,
  craneLib,
}:

let
  # Include both Cargo sources and gui directory for frontend
  src = pkgs.lib.sourceFilesBySuffices ./../../. [
    ".rs"
    ".toml"
    ".lock" # Rust files
    ".ts"
    ".tsx"
    ".js"
    ".jsx"
    ".json"
    ".html"
    ".css"
    ".svg" # Frontend files
    ".png"
    ".ico"
    ".icns" # Icon files for Tauri
  ];

  # Build npm dependencies separately (offline, reproducible)
  npmDeps = pkgs.fetchNpmDeps {
    src = ./../../gui;
    hash = "sha256-8tKOFI6/qDQ2vzOsrrmQz0nGQ3Wb3ayrUaPpr/8QBZI=";
  };

  # Common arguments for crane (Rust only)
  commonArgs = {
    inherit src;
    strictDeps = true;
    pname = "gp-gui";
    version = "1.0.0";

    # Cargo.toml is in gui/src-tauri subdirectory
    cargoRoot = "gui/src-tauri";

    nativeBuildInputs = with pkgs; [
      pkg-config
      makeWrapper
    ];

    buildInputs = with pkgs; [
      openssl
      # GTK3 with WebKitGTK (required by Rust tauri bindings)
      gtk3
      webkitgtk_4_1
      libsoup_3
      glib
      glib-networking
      gsettings-desktop-schemas
      cairo
      pango
      gdk-pixbuf
      atk
      # Wayland support (primary)
      wayland
      wayland-protocols
      # X11 libraries (for compatibility)
      xorg.libX11
      xorg.libXcomposite
      xorg.libXdamage
      xorg.libXext
      xorg.libXfixes
      xorg.libXrandr
      # Runtime dependencies (ensure they're built before this package)
      gpauth
      gpclient
      openconnect
    ];
  };

  # Build dependencies only (cached separately)
  # Build Rust dependencies first
  # Create minimal dist folder for tauri-build during deps phase
  cargoArtifacts = craneLib.buildDepsOnly (
    commonArgs
    // {
      preBuild = ''
              # Create minimal dist for tauri-build during deps-only phase
              mkdir -p gui/dist/assets
              cat > gui/dist/index.html << 'EOF'
        <!doctype html>
        <html><head><title>Placeholder</title></head><body><div id="root"></div><script type="module" src="/assets/main.js"></script></body></html>
        EOF
              echo "// placeholder" > gui/dist/assets/main.js
      '';
    }
  );

in
craneLib.buildPackage (
  commonArgs
  // {
    inherit cargoArtifacts;

    # Force rebuild of gp-gui binary to ensure tauri-build re-runs with real assets
    # Without this, Cargo reuses the cached build from deps phase with placeholder assets
    CARGO_INCREMENTAL = "0";
    CARGO_BUILD_INCREMENTAL = "false";

    # Add npm-specific build inputs for final build only
    nativeBuildInputs =
      commonArgs.nativeBuildInputs
      ++ (with pkgs; [
        nodejs
        npmHooks.npmConfigHook
      ]);

    # Provide offline npm cache for final build
    inherit npmDeps;
    npmRoot = "gui";

    # Build frontend before Cargo runs (we're in /build/source)
    preBuild = ''
      cd gui
      npm run build
      cd ..

      # Touch build.rs to force Cargo to re-run tauri-build with the real assets
      # This ensures the final binary embeds the actual frontend, not placeholders from deps phase
      touch gui/src-tauri/build.rs
    '';

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
            pkgs.gtk3
            pkgs.webkitgtk_4_1
            pkgs.glib
            pkgs.glib-networking
            pkgs.gsettings-desktop-schemas
            pkgs.cairo
            pkgs.pango
            pkgs.gdk-pixbuf
            pkgs.atk
            pkgs.libsoup_3
            pkgs.wayland
            pkgs.xorg.libX11
            pkgs.xorg.libXcomposite
            pkgs.xorg.libXdamage
            pkgs.xorg.libXext
            pkgs.xorg.libXfixes
            pkgs.xorg.libXrandr
          ]
        } \
        --prefix XDG_DATA_DIRS : "${pkgs.gsettings-desktop-schemas}/share:${pkgs.gtk3}/share" \
        --set WEBKIT_DISABLE_DMABUF_RENDERER "1"
    '';

    # Expose dependencies for inspection and ensure they're built
    passthru = {
      # Runtime dependencies required for VPN functionality
      runtimeDeps = [
        pkgs.gpauth
        pkgs.gpclient
        pkgs.openconnect
      ];
      # Frontend dependencies
      inherit npmDeps;
      # Rust dependencies artifacts
      inherit cargoArtifacts;
    };

    meta = with pkgs.lib; {
      description = "GUI client for GlobalProtect VPN";
      homepage = "https://github.com/brianmcgillion/gp-gui";
      license = licenses.gpl3Only;
      platforms = platforms.linux;
      mainProgram = "gp-gui";
    };
  }
)
