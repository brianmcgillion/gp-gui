/*
 * gp-gui-wrapper: A minimal setuid wrapper for gp-gui
 *
 * This wrapper allows unprivileged users to run gp-gui, which needs root
 * privileges to manage VPN connections via gpclient.
 *
 * Security considerations:
 * - Escalates privileges to root using setuid(0)/setgid(0) before exec
 * - gp-gui runs as root to manage VPN connections (requires CAP_NET_ADMIN)
 * - Only executes the specific gp-gui binary at compile-time fixed path
 * - Sanitizes environment to prevent LD_PRELOAD and similar attacks
 * - Sets minimal safe PATH before privilege escalation
 * - No user-controlled paths or arguments processed
 * - Privileges are NOT dropped; the entire gp-gui process runs as root
 *
 * CAUTION: This wrapper grants full root privileges. Ensure gp-gui is
 * audited and handles user input safely.
 */

#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>
#include <errno.h>
#include <string.h>

/* This path will be substituted at build time by Nix */
#ifndef GP_GUI_PATH
#error "GP_GUI_PATH must be defined at compile time"
#endif

int main(int argc, char *argv[]) {
    /* Sanitize environment using allowlist approach before privilege escalation */
    /* Step 1: Snapshot required variables */
    const char *allowlist_vars[] = {
        "DISPLAY",
        "WAYLAND_DISPLAY",
        "XDG_RUNTIME_DIR",
        "HOME",
        "USER",
        "LOGNAME",
        NULL
    };

    #define ALLOWLIST_SIZE 6 /* Number of non-NULL entries in allowlist_vars */
    char *saved_values[ALLOWLIST_SIZE] = {NULL};

    for (int i = 0; i < ALLOWLIST_SIZE && allowlist_vars[i] != NULL; i++) {
        const char *value = getenv(allowlist_vars[i]);
        if (value != NULL) {
            saved_values[i] = strdup(value);
            if (saved_values[i] == NULL) {
                fprintf(stderr, "gp-gui-wrapper: Failed to save environment variable %s\n",
                        allowlist_vars[i]);
                return 1;
            }
        }
    }

    /* Step 2: Clear entire environment */
    if (clearenv() != 0) {
        fprintf(stderr, "gp-gui-wrapper: Failed to clear environment: %s\n", strerror(errno));
        /* Free saved values before exit */
        for (int i = 0; i < ALLOWLIST_SIZE; i++) {
            free(saved_values[i]);
        }
        return 1;
    }

    /* Step 3: Restore only allowlisted variables */
    for (int i = 0; i < ALLOWLIST_SIZE && allowlist_vars[i] != NULL; i++) {
        if (saved_values[i] != NULL) {
            if (setenv(allowlist_vars[i], saved_values[i], 1) != 0) {
                fprintf(stderr, "gp-gui-wrapper: Failed to restore %s: %s\n",
                        allowlist_vars[i], strerror(errno));
                /* Free saved values before exit */
                for (int j = 0; j < ALLOWLIST_SIZE; j++) {
                    free(saved_values[j]);
                }
                return 1;
            }
            free(saved_values[i]);
        }
    }

    /* Step 4: Set a minimal, safe PATH */
    if (setenv("PATH", "/run/current-system/sw/bin:/usr/sbin:/usr/bin:/sbin:/bin", 1) != 0) {
        fprintf(stderr, "gp-gui-wrapper: Failed to set PATH: %s\n", strerror(errno));
        return 1;
    }

    /* Set GID before UID to avoid permission issues */
    /* Set real, effective, and saved GID to root */
    if (setgid(0) != 0) {
        fprintf(stderr, "gp-gui-wrapper: Failed to set GID to root: %s\n", strerror(errno));
        return 1;
    }

    /* Set real, effective, and saved UID to root */
    if (setuid(0) != 0) {
        fprintf(stderr, "gp-gui-wrapper: Failed to set UID to root: %s\n", strerror(errno));
        return 1;
    }

    /* Execute the actual gp-gui binary with the same arguments */
    execv(GP_GUI_PATH, argv);

    /* If we reach here, execv failed */
    fprintf(stderr, "gp-gui-wrapper: Failed to execute %s: %s\n", GP_GUI_PATH, strerror(errno));
    return 1;
}
