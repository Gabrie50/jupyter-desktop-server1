#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <stdbool.h>
#include <limits.h>
#include <locale.h>
#include <getopt.h>
#include <signal.h>
#include <errno.h>
#include <unistd.h>

#include <sys/types.h>
#include <sys/stat.h>
#include <sys/utsname.h>
#include <fcntl.h>

#include <fcft/fcft.h>

#define LOG_MODULE "main"
#define LOG_ENABLE_DBG 0
#include "log.h"

#include "config.h"
#include "fdm.h"
#include "foot-features.h"
#include "key-binding.h"
#include "macros.h"
#include "reaper.h"
#include "render.h"
#include "server.h"
#include "shm.h"
#include "terminal.h"
#include "util.h"
#include "xmalloc.h"
#include "xsnprintf.h"

#if !defined(__STDC_UTF_32__) || !__STDC_UTF_32__
 #error "char32_t does not use UTF-32"
#endif

static bool
fdm_sigint(struct fdm *fdm, int signo, void *data)
{
    *(volatile sig_atomic_t *)data = true;
    return true;
}

static void
print_usage(const char *prog_name)
{
    static const char options[] =
        "\nOptions:\n"
        "  -c,--config=PATH                         load configuration from PATH ($XDG_CONFIG_HOME/foot/foot.ini)\n"
        "  -C,--check-config                        verify configuration, exit with 0 if ok, otherwise exit with 1\n"
        "  -o,--override=[section.]key=value        override configuration option\n"
        "  -f,--font=FONT                           comma separated list of fonts in fontconfig format (monospace)\n"
        "  -t,--term=TERM                           value to set the environment variable TERM to (" FOOT_DEFAULT_TERM ")\n"
        "  -T,--title=TITLE                         initial window title (foot)\n"
        "  -a,--app-id=ID                           window application ID (foot)\n"
        "  -m,--maximized                           start in maximized mode\n"
        "  -F,--fullscreen                          start in fullscreen mode\n"
        "  -L,--login-shell                         start shell as a login shell\n"
        "  --pty=PATH                               display an existing PTY instead of creating one\n"
        "  -D,--working-directory=DIR               directory to start in (CWD)\n"
        "  -w,--window-size-pixels=WIDTHxHEIGHT     initial width and height, in pixels\n"
        "  -W,--window-size-chars=WIDTHxHEIGHT      initial width and height, in characters\n"
        "  -s,--server[=PATH]                       run as a server (use 'footclient' to start terminals).\n"
        "                                           Without PATH, $XDG_RUNTIME_DIR/foot-$WAYLAND_DISPLAY.sock will be used.\n"
        "  -H,--hold                                remain open after child process exits\n"
        "  -p,--print-pid=FILE|FD                   print PID to file or FD (only applicable in server mode)\n"
        "  -d,--log-level={info|warning|error|none} log level (warning)\n"
        "  -l,--log-colorize=[{never|always|auto}]  enable/disable colorization of log output on stderr\n"
        "  -S,--log-no-syslog                       disable syslog logging (only applicable in server mode)\n"
        "  -v,--version                             show the version number and quit\n"
        "  -e                                       ignored (for compatibility with xterm -e)\n";

    printf("Usage: %s [OPTIONS...]\n", prog_name);
    printf("Usage: %s [OPTIONS...] command [ARGS...]\n", prog_name);
    puts(options);
}

bool
locale_is_utf8(void)
{
    static const char u8[] = u8"ö";
    xassert(strlen(u8) == 2);

    char32_t w;
    if (mbrtoc32(&w, u8, 2, &(mbstate_t){0}) != 2)
        return false;

    return w == U'ö';
}

struct shutdown_context {
    struct terminal **term;
    int exit_code;
};

static void
term_shutdown_cb(void *data, int exit_code)
{
    struct shutdown_context *ctx = data;
    *ctx->term = NULL;
    ctx->exit_code = exit_code;
}

static bool
print_pid(const char *pid_file, bool *unlink_at_exit)
{
    LOG_DBG("printing PID to %s", pid_file);

    errno = 0;
    char *end;
    int pid_fd = strtoul(pid_file, &end, 10);

    if (errno != 0 || *end != '\0') {
        if ((pid_fd = open(pid_file,
                           O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC,
                           S_IRUSR | S_IWUSR | S_IRGRP | S_IROTH)) < 0) {
            LOG_ERRNO("%s: failed to open", pid_file);
            return false;
        } else
            *unlink_at_exit = true;
    }

    if (pid_fd >= 0) {
        char pid[32];
        size_t n = xsnprintf(pid, sizeof(pid), "%u\n", getpid());

        ssize_t bytes = write(pid_fd, pid, n);
        close(pid_fd);

        if (bytes < 0) {
            LOG_ERRNO("failed to write PID to FD=%u", pid_fd);
            return false;
        }

        LOG_DBG("wrote %zd bytes to FD=%d", bytes, pid_fd);
        return true;
    } else
        return false;
}

static void
sanitize_signals(void)
{
    sigset_t mask;
    sigemptyset(&mask);
    sigprocmask(SIG_SETMASK, &mask, NULL);

    struct sigaction dfl = {.sa_handler = SIG_DFL};
    sigemptyset(&dfl.sa_mask);

    for (int i = 1; i < SIGRTMAX; i++)
        sigaction(i, &dfl, NULL);
}

enum {
    PTY_OPTION = CHAR_MAX + 1,
};

int
main(int argc, char *const *argv)
{
    /* Custom exit code, to enable users to differentiate between foot
     * itself failing, and the client application failing */
    static const int foot_exit_failure = -26;
    int ret = foot_exit_failure;

    sanitize_signals();

    /* XDG startup notifications */
    const char *token = getenv("XDG_ACTIVATION_TOKEN");
    unsetenv("XDG_ACTIVATION_TOKEN");

    /* Startup notifications; we don't support it, but must ensure we
     * don't pass this on to programs launched by us */
    unsetenv("DESKTOP_STARTUP_ID");

    const char *const prog_name = argc > 0 ? argv[0] : "<nullptr>";

    static const struct option longopts[] =  {
        {"config",                 required_argument, NULL, 'c'},
        {"check-config",           no_argument,       NULL, 'C'},
        {"override",               required_argument, NULL, 'o'},
        {"term",                   required_argument, NULL, 't'},
        {"title",                  required_argument, NULL, 'T'},
        {"app-id",                 required_argument, NULL, 'a'},
        {"login-shell",            no_argument,       NULL, 'L'},
        {"working-directory",      required_argument, NULL, 'D'},
        {"font",                   required_argument, NULL, 'f'},
        {"window-size-pixels",     required_argument, NULL, 'w'},
        {"window-size-chars",      required_argument, NULL, 'W'},
        {"server",                 optional_argument, NULL, 's'},
        {"hold",                   no_argument,       NULL, 'H'},
        {"maximized",              no_argument,       NULL, 'm'},
        {"fullscreen",             no_argument,       NULL, 'F'},
        {"presentation-timings",   no_argument,       NULL, 'P'}, /* Undocumented */
        {"pty",                    required_argument, NULL, PTY_OPTION},
        {"print-pid",              required_argument, NULL, 'p'},
        {"log-level",              required_argument, NULL, 'd'},
        {"log-colorize",           optional_argument, NULL, 'l'},
        {"log-no-syslog",          no_argument,       NULL, 'S'},
        {"version",                no_argument,       NULL, 'v'},
        {"help",                   no_argument,       NULL, 'h'},
        {NULL,                     no_argument,       NULL,   0},
    };

    bool check_config = false;
    const char *conf_path = NULL;
    const char *custom_cwd = NULL;
    const char *pty_path = NULL;
    bool as_server = false;
    const char *conf_server_socket_path = NULL;
    bool presentation_timings = false;
    bool hold = false;
    bool unlink_pid_file = false;
    const char *pid_file = NULL;
    enum log_class log_level = LOG_CLASS_WARNING;
    enum log_colorize log_colorize = LOG_COLORIZE_AUTO;
    bool log_syslog = true;
    user_notifications_t user_notifications = tll_init();
    config_override_t overrides = tll_init();

    while (true) {
        int c = getopt_long(argc, argv, "+c:Co:t:T:a:LD:f:w:W:s::HmFPp:d:l::Sveh", longopts, NULL);

        if (c == -1)
            break;

        switch (c) {
        case 'c':
            conf_path = optarg;
            break;

        case 'C':
            check_config = true;
            break;

        case 'o':
            tll_push_back(overrides, xstrdup(optarg));
            break;

        case 't':
            tll_push_back(overrides, xstrjoin("term=", optarg));
            break;

        case 'L':
            tll_push_back(overrides, xstrdup("login-shell=yes"));
            break;

        case 'T':
            tll_push_back(overrides, xstrjoin("title=", optarg));
            break;

        case 'a':
            tll_push_back(overrides, xstrjoin("app-id=", optarg));
            break;

        case 'D': {
            struct stat st;
            if (stat(optarg, &st) < 0 || !(st.st_mode & S_IFDIR)) {
                fprintf(stderr, "error: %s: not a directory\n", optarg);
                return ret;
            }
            custom_cwd = optarg;
            break;
        }

        case 'f': {
            char *font_override = xstrjoin("font=", optarg);
            tll_push_back(overrides, font_override);
            break;
        }

        case 'w': {
            unsigned width, height;
            if (sscanf(optarg, "%ux%u", &width, &height) != 2 || width == 0 || height == 0) {
                fprintf(stderr, "error: invalid window-size-pixels: %s\n", optarg);
                return ret;
            }

            tll_push_back(
                overrides, xasprintf("initial-window-size-pixels=%ux%u",
                                     width, height));
            break;
        }

        case 'W': {
            unsigned width, height;
            if (sscanf(optarg, "%ux%u", &width, &height) != 2 || width == 0 || height == 0) {
                fprintf(stderr, "error: invalid window-size-chars: %s\n", optarg);
                return ret;
            }

            tll_push_back(
                overrides, xasprintf("initial-window-size-chars=%ux%u",
                                     width, height));
            break;
        }

        case 's':
            as_server = true;
            if (optarg != NULL)
                conf_server_socket_path = optarg;
            break;

        case PTY_OPTION:
            pty_path = optarg;
            break;

        case 'P':
            presentation_timings = true;
            break;

        case 'H':
            hold = true;
            break;

        case 'm':
            tll_push_back(overrides, xstrdup("initial-window-mode=maximized"));
            break;

        case 'F':
            tll_push_back(overrides, xstrdup("initial-window-mode=fullscreen"));
            break;

        case 'p':
            pid_file = optarg;
            break;

        case 'd': {
            int lvl = log_level_from_string(optarg);
            if (unlikely(lvl < 0)) {
                fprintf(
                    stderr,
                    "-d,--log-level: %s: argument must be one of %s\n",
                    optarg,
                    log_level_string_hint());
                return ret;
            }
            log_level = lvl;
            break;
        }

        case 'l':
            if (optarg == NULL || streq(optarg, "auto"))
                log_colorize = LOG_COLORIZE_AUTO;
            else if (streq(optarg, "never"))
                log_colorize = LOG_COLORIZE_NEVER;
            else if (streq(optarg, "always"))
                log_colorize = LOG_COLORIZE_ALWAYS;
            else {
                fprintf(stderr, "%s: argument must be one of 'never', 'always' or 'auto'\n", optarg);
                return ret;
            }
            break;

        case 'S':
            log_syslog = false;
            break;

        case 'v':
            print_version_and_features("foot ");
            return EXIT_SUCCESS;

        case 'h':
            print_usage(prog_name);
            return EXIT_SUCCESS;

        case 'e':
            break;

        case '?':
            return ret;
        }
    }

    if (as_server && pty_path) {
        fputs("error: --pty is incompatible with server mode\n", stderr);
        return ret;
    }

    log_init(log_colorize, as_server && log_syslog,
             as_server ? LOG_FACILITY_DAEMON : LOG_FACILITY_USER, log_level);

    if (argc > 0) {
        argc -= optind;
        argv += optind;
    }

    LOG_INFO("%s", version_and_features);

    {
        struct utsname name;
        if (uname(&name) < 0)
            LOG_ERRNO("uname() failed");
        else
            LOG_INFO("arch: %s %s/%zu-bit",
                     name.sysname, name.machine, sizeof(void *) * 8);
    }

    srand(time(NULL));

    const char *locale = setlocale(LC_CTYPE, "");
    if (locale == NULL) {
        /*
         * If the user has configured an invalid locale, or a name of a locale
         * that does not exist on this system, then the above call may return
         * NULL. We should just continue with the fallback method below.
         */
        LOG_ERR("setlocale() failed. The most common cause is that the "
                "configured locale is not available, or has been misspelled");
    }

    LOG_INFO("locale: %s", locale != NULL ? locale : "<invalid>");

    bool bad_locale = locale == NULL || !locale_is_utf8();
    if (bad_locale) {
        static const char fallback_locales[][12] = {
            "C.UTF-8",
            "en_US.UTF-8",
        };
        char *saved_locale = locale != NULL ? xstrdup(locale) : NULL;

        /*
         * Try to force an UTF-8 locale. If we succeed, launch the
         * user's shell as usual, but add a user-notification saying
         * the locale has been changed.
         */
        for (size_t i = 0; i < ALEN(fallback_locales); i++) {
            const char *const fallback_locale = fallback_locales[i];

            if (setlocale(LC_CTYPE, fallback_locale) != NULL) {
                if (saved_locale != NULL) {
                    LOG_WARN(
                        "'%s' is not a UTF-8 locale, falling back to '%s'",
                        saved_locale, fallback_locale);

                    user_notification_add_fmt(
                        &user_notifications, USER_NOTIFICATION_WARNING,
                        "'%s' is not a UTF-8 locale, falling back to '%s'",
                        saved_locale, fallback_locale);

                } else {
                    LOG_WARN(
                        "invalid locale, falling back to '%s'", fallback_locale);
                    user_notification_add_fmt(
                        &user_notifications, USER_NOTIFICATION_WARNING,
                        "invalid locale, falling back to '%s'", fallback_locale);
                }

                bad_locale = false;
                break;
            }
        }

        if (bad_locale) {
            if (saved_locale != NULL) {
                LOG_ERR(
                    "'%s' is not a UTF-8 locale, and failed to find a fallback",
                    saved_locale);

                user_notification_add_fmt(
                    &user_notifications, USER_NOTIFICATION_ERROR,
                    "'%s' is not a UTF-8 locale, and failed to find a fallback",
                    saved_locale);
            } else {
                LOG_ERR("invalid locale, and failed to find a fallback");

                user_notification_add_fmt(
                    &user_notifications, USER_NOTIFICATION_ERROR,
                    "invalid locale, and failed to find a fallback");
            }
        }
        free(saved_locale);
    }

    struct config conf = {NULL};
    bool conf_successful = config_load(
        &conf, conf_path, &user_notifications, &overrides, check_config, as_server);

    tll_free_and_free(overrides, free);
    if (!conf_successful) {
        config_free(&conf);
        return ret;
    }

    if (check_config) {
        config_free(&conf);
        return EXIT_SUCCESS;
    }

    _Static_assert((int)LOG_CLASS_ERROR == (int)FCFT_LOG_CLASS_ERROR,
                   "fcft log level enum offset");
    _Static_assert((int)LOG_COLORIZE_ALWAYS == (int)FCFT_LOG_COLORIZE_ALWAYS,
                   "fcft colorize enum mismatch");
    fcft_init(
        (enum fcft_log_colorize)log_colorize,
        as_server && log_syslog,
        (enum fcft_log_class)log_level);

    if (conf_server_socket_path != NULL) {
        free(conf.server_socket_path);
        conf.server_socket_path = xstrdup(conf_server_socket_path);
    }
    conf.presentation_timings = presentation_timings;
    conf.hold_at_exit = hold;

    if (conf.tweak.font_monospace_warn && conf.fonts[0].count > 0) {
        check_if_font_is_monospaced(
            conf.fonts[0].arr[0].pattern, &conf.notifications);
    }


    if (bad_locale) {
        static char *const bad_locale_fake_argv[] = {"/bin/sh", "-c", "", NULL};
        argc = 1;
        argv = bad_locale_fake_argv;
        conf.hold_at_exit = true;
    }

    struct fdm *fdm = NULL;
    struct reaper *reaper = NULL;
    struct key_binding_manager *key_binding_manager = NULL;
    struct wayland *wayl = NULL;
    struct renderer *renderer = NULL;
    struct terminal *term = NULL;
    struct server *server = NULL;
    struct shutdown_context shutdown_ctx = {.term = &term, .exit_code = foot_exit_failure};

    const char *cwd = custom_cwd;
    char *_cwd = NULL;

    if (cwd == NULL) {
        size_t buf_len = 1024;
        do {
            _cwd = xrealloc(_cwd, buf_len);
            errno = 0;
            if (getcwd(_cwd, buf_len) == NULL && errno != ERANGE) {
                LOG_ERRNO("failed to get current working directory");
                goto out;
            }
            buf_len *= 2;
        } while (errno == ERANGE);
        cwd = _cwd;
    }

    const char *pwd = getenv("PWD");
    if (pwd != NULL) {
        char *resolved_path_cwd = realpath(cwd, NULL);
        char *resolved_path_pwd = realpath(pwd, NULL);

        if (resolved_path_cwd != NULL &&
            resolved_path_pwd != NULL &&
            streq(resolved_path_cwd, resolved_path_pwd))
        {
            /*
             * The resolved path of $PWD matches the resolved path of
             * the *actual* working directory - use $PWD.
             *
             * This makes a difference when $PWD refers to a symlink.
             */
            cwd = pwd;
        }

        free(resolved_path_cwd);
        free(resolved_path_pwd);
    }

    shm_set_max_pool_size(conf.tweak.max_shm_pool_size);

    if ((fdm = fdm_init()) == NULL)
        goto out;

    if ((reaper = reaper_init(fdm)) == NULL)
        goto out;

    if ((key_binding_manager = key_binding_manager_new()) == NULL)
        goto out;

    if ((wayl = wayl_init(
             fdm, key_binding_manager, conf.presentation_timings)) == NULL)
    {
        goto out;
    }

    if ((renderer = render_init(fdm, wayl)) == NULL)
        goto out;

    if (!as_server && (term = term_init(
                           &conf, fdm, reaper, wayl, "foot", cwd, token, pty_path,
                           argc, argv, NULL,
                           &term_shutdown_cb, &shutdown_ctx)) == NULL) {
        goto out;
    }
    free(_cwd);
    _cwd = NULL;

    if (as_server && (server = server_init(&conf, fdm, reaper, wayl)) == NULL)
        goto out;

    volatile sig_atomic_t aborted = false;
    if (!fdm_signal_add(fdm, SIGINT, &fdm_sigint, (void *)&aborted) ||
        !fdm_signal_add(fdm, SIGTERM, &fdm_sigint, (void *)&aborted))
    {
        goto out;
    }

    struct sigaction sig_ign = {.sa_handler = SIG_IGN};
    sigemptyset(&sig_ign.sa_mask);
    if (sigaction(SIGHUP, &sig_ign, NULL) < 0 ||
        sigaction(SIGPIPE, &sig_ign, NULL) < 0)
    {
        LOG_ERRNO("failed to ignore SIGHUP+SIGPIPE");
        goto out;
    }

    if (as_server)
        LOG_INFO("running as server; launch terminals by running footclient");

    if (as_server && pid_file != NULL) {
        if (!print_pid(pid_file, &unlink_pid_file))
            goto out;
    }

    ret = EXIT_SUCCESS;
    while (likely(!aborted && (as_server || tll_length(wayl->terms) > 0))) {
        if (unlikely(!fdm_poll(fdm))) {
            ret = foot_exit_failure;
            break;
        }
    }

out:
    free(_cwd);
    server_destroy(server);
    term_destroy(term);

    shm_fini();
    render_destroy(renderer);
    wayl_destroy(wayl);
    key_binding_manager_destroy(key_binding_manager);
    reaper_destroy(reaper);
    fdm_signal_del(fdm, SIGTERM);
    fdm_signal_del(fdm, SIGINT);
    fdm_destroy(fdm);

    config_free(&conf);

    if (unlink_pid_file)
        unlink(pid_file);

    LOG_INFO("goodbye");
    fcft_fini();
    log_deinit();
    return ret == EXIT_SUCCESS && !as_server ? shutdown_ctx.exit_code : ret;
}

UNITTEST
{
    char *s = xstrjoin("foo", "bar");
    xassert(streq(s, "foobar"));
    free(s);

    s = xstrjoin3("foo", " ", "bar");
    xassert(streq(s, "foo bar"));
    free(s);

    s = xstrjoin3("foo", ",", "bar");
    xassert(streq(s, "foo,bar"));
    free(s);

    s = xstrjoin3("foo", "bar", "baz");
    xassert(streq(s, "foobarbaz"));
    free(s);
}
