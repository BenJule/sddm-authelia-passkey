/*
 * pam_authelia_passkey.so - auth module.
 *
 * Sole consumer of the single-use, TTL-bound Authelia device-
 * authorization approval marker written by the broker
 * (/run/sddm-authelia-passkey/approved-<user>). A pam_exec(8) child
 * process cannot set PAM_AUTHTOK for its parent PAM stack (see
 * docs/architecture.md), so this native module exists specifically to
 * make optional KWallet auto-unlock possible; without that feature it
 * would functionally be a pam_exec(8) + shell script, as in a minimal
 * password-only smartphone-login deployment.
 *
 * On a valid approval:
 *   - the login decision is final and unconditional (PAM_SUCCESS) -
 *     nothing below this point can turn a valid approval into a failed
 *     login;
 *   - if kwallet_auto_unlock=true in the config, as a SEPARATE, best-
 *     effort step, it mints a short-lived hand-off marker and asks
 *     kwallet-secretd for a KWallet-unlock secret. If that fails for any
 *     reason (secretd down, credential missing, timeout), PAM_AUTHTOK is
 *     simply left unset - KWallet falls back to its own manual prompt.
 *
 * On no/invalid/expired marker: returns PAM_IGNORE, so the auth stack
 * falls through unchanged to the normal password path.
 *
 * Never runs a shell, never calls system()/popen(), never logs secret
 * material, never touches argv/env with it. Reads one config file and
 * talks to one fixed, hardcoded local socket path.
 */

#define _GNU_SOURCE
#include <security/pam_appl.h>
#include <security/pam_modules.h>
#include <security/pam_ext.h>

#include <sys/socket.h>
#include <sys/un.h>
#include <sys/prctl.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <stdio.h>
#include <pwd.h>
#include <string.h>
#include <stdlib.h>
#include <errno.h>
#include <time.h>
#include <poll.h>

#define CONFIG_PATH "/etc/sddm-authelia-passkey/config.conf"
#define SOCK_PATH "/run/sddm-authelia-passkey/kwallet-secret.sock"
#define MARKER_DIR "/run/sddm-authelia-passkey"
#define DEFAULT_APPROVAL_TTL_SECONDS 30
#define MIN_UID 1000
#define IO_TIMEOUT_MS 2000
#define MAX_SECRET 512
#define MAX_LINE 512

struct module_config {
    int kwallet_auto_unlock;
    long approval_ttl_seconds;
};

/* Minimal KEY=VALUE parser matching config/examples/config.conf.example.
 * Only reads the two fields this module needs; unknown keys are ignored
 * (the broker/secretd own the rest of the file). Missing file or missing
 * keys fall back to safe defaults (auto-unlock off, default TTL). */
static void load_module_config(struct module_config *cfg) {
    cfg->kwallet_auto_unlock = 0;
    cfg->approval_ttl_seconds = DEFAULT_APPROVAL_TTL_SECONDS;

    FILE *f = fopen(CONFIG_PATH, "r");
    if (!f) return;

    char line[MAX_LINE];
    while (fgets(line, sizeof(line), f)) {
        char *nl = strchr(line, '\n');
        if (nl) *nl = '\0';
        char *p = line;
        while (*p == ' ' || *p == '\t') p++;
        if (*p == '#' || *p == '\0') continue;

        char *eq = strchr(p, '=');
        if (!eq) continue;
        *eq = '\0';
        char *key = p;
        char *val = eq + 1;

        if (strcmp(key, "kwallet_auto_unlock") == 0) {
            cfg->kwallet_auto_unlock = (strcmp(val, "true") == 0 || strcmp(val, "1") == 0 || strcmp(val, "yes") == 0);
        } else if (strcmp(key, "approval_ttl_seconds") == 0) {
            char *end = NULL;
            long v = strtol(val, &end, 10);
            if (end != val && v > 0) cfg->approval_ttl_seconds = v;
        }
    }
    fclose(f);
}

static void wipe(void *p, size_t n) {
    if (!p || !n) return;
    volatile unsigned char *vp = (volatile unsigned char *)p;
    while (n--) *vp++ = 0;
}

/* Atomically consume (single-use) the approval marker for `user`, then
 * verify its age is within TTL. Returns 1 if the login is smartphone-approved,
 * 0 otherwise. The marker is gone either way once this returns. */
/* Extracts the value of "KEY=" from a small, fixed-format marker buffer
 * (one KEY=VALUE per line). Returns 0/false if the key is absent or the
 * value would not fit - never partial-copies. */
static int marker_field(const char *buf, size_t buflen, const char *key,
                         char *out, size_t outcap) {
    size_t keylen = strlen(key);
    size_t i = 0;
    while (i < buflen) {
        size_t line_start = i;
        while (i < buflen && buf[i] != '\n') i++;
        size_t line_len = i - line_start;
        if (line_len > keylen && memcmp(buf + line_start, key, keylen) == 0) {
            size_t vlen = line_len - keylen;
            if (vlen == 0 || vlen >= outcap) return 0;
            memcpy(out, buf + line_start + keylen, vlen);
            out[vlen] = '\0';
            return 1;
        }
        i++; /* skip the newline */
    }
    return 0;
}

static int consume_login_approval(const char *user, uid_t expected_uid, long ttl_seconds) {
    char marker[256], tmp[300];
    int n = snprintf(marker, sizeof(marker), MARKER_DIR "/approved-%s", user);
    if (n <= 0 || (size_t)n >= sizeof(marker)) return 0;
    n = snprintf(tmp, sizeof(tmp), "%s.consuming.%d", marker, (int)getpid());
    if (n <= 0 || (size_t)n >= sizeof(tmp)) return 0;

    if (rename(marker, tmp) != 0) {
        return 0; /* no marker, or already consumed concurrently */
    }

    int ok = 0;
    int fd = open(tmp, O_RDONLY | O_NOFOLLOW | O_CLOEXEC);
    if (fd >= 0) {
        struct stat st;
        if (fstat(fd, &st) == 0) {
            /* Defense in depth: the real boundary is markerDir's own mode
             * (0700, root-owned - see docs/threat-model.md), which already
             * makes it impossible for a non-root process to place a file
             * here at all. Still verify ownership/mode on the file itself
             * so a future regression that loosens the directory's
             * permissions doesn't silently become a local privilege
             * escalation - fail closed rather than trust path/name alone. */
            int owned_by_root = (st.st_uid == 0 && st.st_gid == 0);
            int mode_is_0600 = ((st.st_mode & 07777) == 0600);
            int is_regular = S_ISREG(st.st_mode);
            if (owned_by_root && mode_is_0600 && is_regular) {
                time_t now = time(NULL);
                long age = (long)(now - st.st_mtime);
                int fresh = (age >= 0 && age <= ttl_seconds);

                char buf[512];
                ssize_t got = read(fd, buf, sizeof(buf) - 1);
                if (fresh && got > 0) {
                    buf[got] = '\0';
                    char version[8], uidbuf[16];
                    /* v2 format required: VERSION=2, and the marker's own
                     * embedded UID must match a UID we resolved via NSS
                     * for `user` *right now* - this is what catches an
                     * account that was deleted and recreated (same
                     * username, different UID) between the broker minting
                     * the marker and PAM consuming it. */
                    if (marker_field(buf, (size_t)got, "VERSION=", version, sizeof(version)) &&
                        strcmp(version, "2") == 0 &&
                        marker_field(buf, (size_t)got, "UID=", uidbuf, sizeof(uidbuf))) {
                        char expected[16];
                        snprintf(expected, sizeof(expected), "%lu", (unsigned long)expected_uid);
                        ok = (strcmp(uidbuf, expected) == 0);
                    }
                }
                wipe(buf, sizeof(buf));
            }
        }
        close(fd);
    }
    unlink(tmp);
    return ok;
}

/* Mints a short-lived, single-use hand-off marker authorizing exactly one
 * secret release by kwallet-secretd, separate from the login-decision
 * marker above (which is already consumed by the time we get here). */
static void mint_kwallet_handoff(const char *user, uid_t uid) {
    char path[256], tmp[300], content[64];
    int n = snprintf(path, sizeof(path), MARKER_DIR "/kwallet-ready-%s", user);
    if (n <= 0 || (size_t)n >= sizeof(path)) return;
    n = snprintf(tmp, sizeof(tmp), "%s.tmp.%d", path, (int)getpid());
    if (n <= 0 || (size_t)n >= sizeof(tmp)) return;
    int clen = snprintf(content, sizeof(content), "UID=%lu\n", (unsigned long)uid);
    if (clen <= 0 || (size_t)clen >= sizeof(content)) return;

    int fd = open(tmp, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW, 0600);
    if (fd < 0) return;
    ssize_t w = write(fd, content, (size_t)clen);
    close(fd);
    if (w != clen || rename(tmp, path) != 0) {
        unlink(tmp);
    }
}

/* connect+send+recv with a hard timeout; returns 0 and fills out/outlen on
 * success ("OK <secret>"), -1 on any failure (never partial/garbage). */
static int fetch_secret(const char *user, uid_t uid, char *out, size_t outcap, size_t *outlen) {
    int fd = socket(AF_UNIX, SOCK_STREAM | SOCK_CLOEXEC, 0);
    if (fd < 0) return -1;

    struct sockaddr_un addr;
    memset(&addr, 0, sizeof(addr));
    addr.sun_family = AF_UNIX;
    strncpy(addr.sun_path, SOCK_PATH, sizeof(addr.sun_path) - 1);

    if (connect(fd, (struct sockaddr *)&addr, sizeof(addr)) != 0) {
        close(fd);
        return -1;
    }

    char req[320];
    int reqlen = snprintf(req, sizeof(req), "GET %s %lu\n", user, (unsigned long)uid);
    if (reqlen <= 0 || (size_t)reqlen >= sizeof(req)) { close(fd); return -1; }

    struct pollfd pfd = { .fd = fd, .events = POLLOUT };
    if (poll(&pfd, 1, IO_TIMEOUT_MS) <= 0 || !(pfd.revents & POLLOUT)) {
        close(fd);
        return -1;
    }
    if (write(fd, req, (size_t)reqlen) != reqlen) {
        close(fd);
        return -1;
    }

    char buf[MAX_SECRET + 16];
    size_t got = 0;
    for (;;) {
        pfd.events = POLLIN;
        int pr = poll(&pfd, 1, IO_TIMEOUT_MS);
        if (pr <= 0 || !(pfd.revents & POLLIN)) { wipe(buf, sizeof(buf)); close(fd); return -1; }
        ssize_t r = read(fd, buf + got, sizeof(buf) - 1 - got);
        if (r < 0) { wipe(buf, sizeof(buf)); close(fd); return -1; }
        if (r == 0) break;
        got += (size_t)r;
        if (got >= sizeof(buf) - 1) break;
        if (memchr(buf, '\n', got)) break;
    }
    close(fd);

    if (got < 4 || strncmp(buf, "OK ", 3) != 0) {
        wipe(buf, sizeof(buf));
        return -1;
    }
    char *nl = memchr(buf, '\n', got);
    size_t paylen = nl ? (size_t)(nl - (buf + 3)) : (got - 3);
    if (paylen == 0 || paylen >= outcap) {
        wipe(buf, sizeof(buf));
        return -1;
    }
    memcpy(out, buf + 3, paylen);
    out[paylen] = '\0';
    *outlen = paylen;
    wipe(buf, sizeof(buf));
    return 0;
}

PAM_EXTERN int pam_sm_authenticate(pam_handle_t *pamh, int flags,
                                    int argc, const char **argv) {
    (void)flags; (void)argc; (void)argv;

    prctl(PR_SET_DUMPABLE, 0);

    struct module_config cfg;
    load_module_config(&cfg);

    const char *user = NULL;
    if (pam_get_user(pamh, &user, NULL) != PAM_SUCCESS || !user || !*user) {
        return PAM_IGNORE;
    }

    struct passwd pwbuf, *pw = NULL;
    char pwtmp[4096];
    if (getpwnam_r(user, &pwbuf, pwtmp, sizeof(pwtmp), &pw) != 0 || !pw) {
        return PAM_IGNORE;
    }
    if (pw->pw_uid < MIN_UID) {
        /* never for system/root accounts */
        return PAM_IGNORE;
    }

    /* This is the ONLY gate for the login decision. Once a valid approval
     * is consumed, the smartphone login is authoritative-successful no matter
     * what happens below. */
    if (!consume_login_approval(user, pw->pw_uid, cfg.approval_ttl_seconds)) {
        return PAM_IGNORE;
    }

    if (!cfg.kwallet_auto_unlock) {
        return PAM_SUCCESS;
    }

    /* Best-effort from here on: KWallet auto-unlock must never be able to
     * fail the login that was already decided above. */
    mint_kwallet_handoff(user, pw->pw_uid);

    char secret[MAX_SECRET];
    if (mlock(secret, sizeof(secret)) != 0) {
        /* proceed anyway; mlock is best-effort hardening, not a hard requirement */
    }
    size_t seclen = 0;
    int rc = fetch_secret(user, pw->pw_uid, secret, sizeof(secret), &seclen);
    if (rc == 0) {
        pam_set_item(pamh, PAM_AUTHTOK, secret); /* best-effort; ignore failure here too */
    }
    wipe(secret, sizeof(secret));
    munlock(secret, sizeof(secret));

    return PAM_SUCCESS;
}

PAM_EXTERN int pam_sm_setcred(pam_handle_t *pamh, int flags,
                               int argc, const char **argv) {
    (void)pamh; (void)flags; (void)argc; (void)argv;
    return PAM_SUCCESS;
}
