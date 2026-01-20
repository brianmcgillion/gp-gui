{
  config,
  lib,
  pkgs,
  ...
}:

with lib;

let
  cfg = config.programs.gp-gui;

  # Default packages - will be overridden if gp-gui is in pkgs
  defaultGpGui =
    pkgs.gp-gui
      or (throw "gp-gui package not found in pkgs. Please ensure the gp-gui overlay is applied.");
  defaultGpGuiWrapper =
    pkgs.gp-gui-wrapper
      or (throw "gp-gui-wrapper package not found in pkgs. Please ensure the gp-gui overlay is applied.");
  defaultGpclientWrapper =
    pkgs.gpclient-wrapper
      or (throw "gpclient-wrapper package not found in pkgs. Please ensure the gp-gui overlay is applied.");
in
{
  options.programs.gp-gui = {
    enable = mkEnableOption "GlobalProtect VPN GUI";

    package = mkOption {
      type = types.package;
      default = defaultGpGui;
      defaultText = literalExpression "pkgs.gp-gui";
      description = "The gp-gui package to use.";
    };

    wrapperPackage = mkOption {
      type = types.package;
      default = defaultGpGuiWrapper;
      defaultText = literalExpression "pkgs.gp-gui-wrapper";
      description = "The gp-gui-wrapper package to use for setuid wrapper.";
    };

    gpclientWrapperPackage = mkOption {
      type = types.package;
      default = defaultGpclientWrapper;
      defaultText = literalExpression "pkgs.gpclient-wrapper";
      description = "The gpclient-wrapper package to use for setuid wrapper.";
    };

    allowedGroup = mkOption {
      type = types.nullOr types.str;
      default = null;
      example = "vpnusers";
      description = ''
        Optional group name whose members are allowed to execute gp-gui.
        If set, only users in this group (and root) can run the setuid wrapper.
        If null (default), all users can execute it.
      '';
    };
  };

  config = mkIf cfg.enable {
    # Install the main package and its runtime dependencies
    environment.systemPackages = [ cfg.package ] ++ (cfg.package.runtimeDeps or [ ]);

    # Create setuid wrappers for both gp-gui and gpclient
    # Both need root: gp-gui for lock file, gpclient for TUN device creation
    security.wrappers = {
      gp-gui = {
        source = "${cfg.wrapperPackage}/bin/gp-gui-wrapper";
        owner = "root";
        group = if cfg.allowedGroup != null then cfg.allowedGroup else "root";
        setuid = true;
        # If allowedGroup is set, restrict to root and that group (u+rxs,g+rx,o=)
        # Otherwise, allow all users (u+rxs,g+rx,o+rx)
        permissions = if cfg.allowedGroup != null then "u+rx,g+rx,o=" else "u+rx,g+rx,o+rx";
      };

      # gpclient needs root to create TUN devices (called by gp-gui)
      gpclient = {
        source = "${cfg.gpclientWrapperPackage}/bin/gpclient-wrapper";
        owner = "root";
        group = if cfg.allowedGroup != null then cfg.allowedGroup else "root";
        setuid = true;
        permissions = if cfg.allowedGroup != null then "u+rx,g+rx,o=" else "u+rx,g+rx,o+rx";
      };

      # openconnect needs root for TUN device creation (called by gpclient)
      openconnect = {
        source = "${pkgs.openconnect}/bin/openconnect";
        owner = "root";
        group = if cfg.allowedGroup != null then cfg.allowedGroup else "root";
        setuid = true;
        # Restrict openconnect by default (u+rxs,g+rx,o=) to prevent accidental misuse
        permissions = "u+rx,g+rx,o=";
      };
    };

  };

  meta.maintainers = with maintainers; [ ];
}
