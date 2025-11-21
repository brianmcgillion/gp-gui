{
  pkgs,
  gp-gui,
  binaryName ? "gp-gui",
  binaryPath ? "${gp-gui}/bin/gp-gui",
}:

pkgs.stdenv.mkDerivation {
  pname = "${binaryName}-wrapper";
  inherit (gp-gui) version;

  src = ./.;

  buildInputs = [ pkgs.gcc ];

  buildPhase = ''
    gcc -O2 -Wall -Wextra \
      -DGP_GUI_PATH=\"${binaryPath}\" \
      -o ${binaryName}-wrapper \
      wrapper.c
  '';

  installPhase = ''
    mkdir -p $out/bin
    cp ${binaryName}-wrapper $out/bin/

    # The actual setuid bit will be set by the NixOS module
    # or by the system administrator after installation
    chmod 755 $out/bin/${binaryName}-wrapper
  '';

  meta = with pkgs.lib; {
    description = "Setuid wrapper for ${binaryName} to allow unprivileged execution";
    license = licenses.asl20;
    platforms = platforms.linux;
    maintainers = with maintainers; [ ];
  };
}
