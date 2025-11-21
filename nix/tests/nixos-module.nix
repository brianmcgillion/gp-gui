# SPDX-FileCopyrightText: 2025 gp-gui contributors
# SPDX-License-Identifier: GPL-3.0-only
#
# NixOS VM test for gp-gui module
# Tests that the module properly configures the setuid wrapper

{ pkgs, self, ... }:

# Create a test with pkgs that has our overlay applied
let
  # Ensure our overlay is applied to pkgs used in the test
  pkgsWithOverlay = import pkgs.path {
    inherit (pkgs.stdenv.hostPlatform) system;
    overlays = [ self.overlays.default ];
  };
in

pkgsWithOverlay.testers.nixosTest {
  name = "gp-gui-module";

  nodes.machine =
    { ... }:
    {
      # Use the pkgs with our overlay already applied
      nixpkgs.pkgs = pkgsWithOverlay;

      imports = [ self.nixosModules.gp-gui ];

      # Enable the gp-gui module
      programs.gp-gui = {
        enable = true;
        # Package will be auto-detected from pkgs.gp-gui via overlay
      };

      # Minimal system configuration
      users.users.testuser = {
        isNormalUser = true;
        uid = 1000;
      };
    };

  testScript = ''
    machine.wait_for_unit("multi-user.target")

    # Test 1: Verify setuid wrapper exists
    machine.succeed("test -f /run/wrappers/bin/gp-gui")
    print("✓ Setuid wrapper exists at /run/wrappers/bin/gp-gui")

    # Test 2: Verify wrapper has setuid permissions (NixOS sets 4511 or 4555)
    output = machine.succeed("stat -c '%a %U' /run/wrappers/bin/gp-gui")
    # NixOS wrappers typically have 4511 (u+rxs,g+x,o+x) or similar
    assert "root" in output, f"Expected root ownership, got: {output}"
    # Check that setuid bit is set (first digit should be 4)
    perms = output.strip().split()[0]
    assert perms.startswith('4'), f"Expected setuid bit to be set (4xxx), got: {perms}"
    print(f"✓ Wrapper has setuid bit ({perms}) and root ownership")

    # Test 3: Verify wrapper is executable by regular user
    machine.succeed("su - testuser -c 'test -x /run/wrappers/bin/gp-gui'")
    print("✓ Wrapper is executable by regular user")

    # Test 4: Verify wrapper can be found in PATH
    machine.succeed("su - testuser -c 'which gp-gui'")
    print("✓ Wrapper is in PATH")

    # Test 5: Verify the wrapper target exists
    wrapper_target = machine.succeed("readlink -f /run/wrappers/bin/gp-gui").strip()
    print(f"✓ Wrapper target: {wrapper_target}")

    # Test 6: Verify gpclient and gpauth are available
    machine.succeed("which gpclient")
    machine.succeed("which gpauth")
    print("✓ Required dependencies (gpclient, gpauth) are available")

    # Test gpclient wrapper
    print("\n=== Testing gpclient wrapper ===")
    machine.succeed("test -x /run/wrappers/bin/gpclient")
    print("✓ gpclient wrapper exists and is executable")

    machine.succeed("su - testuser -c 'test -x /run/wrappers/bin/gpclient'")
    print("✓ gpclient wrapper is executable by regular user")

    gpclient_target = machine.succeed("readlink -f /run/wrappers/bin/gpclient").strip()
    print(f"✓ gpclient wrapper target: {gpclient_target}")

    print("✓ All NixOS module tests passed!")
  '';
}
