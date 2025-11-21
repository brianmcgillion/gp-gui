# SPDX-FileCopyrightText: 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  ...
}:
{
  flake.overlays.default = final: _prev: {
    gp-gui =
      let
        systemPkgs = self.packages.${final.stdenv.hostPlatform.system} or self.packages.x86_64-linux;
      in
      systemPkgs.gp-gui;

    gp-gui-wrapper =
      let
        systemPkgs = self.packages.${final.stdenv.hostPlatform.system} or self.packages.x86_64-linux;
      in
      systemPkgs.gp-gui-wrapper;

    gpclient-wrapper =
      let
        systemPkgs = self.packages.${final.stdenv.hostPlatform.system} or self.packages.x86_64-linux;
      in
      systemPkgs.gpclient-wrapper;
  };
}
