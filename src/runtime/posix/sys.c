/* bb_sys.h on POSIX hosts (macOS, Linux): what `make test` runs on the Mac. */
#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE
#define _DARWIN_C_SOURCE
#include "../bb_sys.h"

#include <dirent.h>
#include <errno.h>
#include <fnmatch.h>
#include <limits.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <sys/stat.h>
#include <sys/wait.h>
#include <unistd.h>

static char *command, *app_path, *exename, *clip;

static char *xstrdup(const char *s)
{
    char *o = malloc(strlen(s) + 1);
    if (o) strcpy(o, s);
    return o;
}

static char *dir_of(const char *p)
{
    char buf[PATH_MAX];
    if (!realpath(p, buf)) snprintf(buf, sizeof buf, "%s", p);
    char *s = strrchr(buf, '/');
    if (s && s != buf) *s = 0;
    else if (s) s[1] = 0;
    else strcpy(buf, ".");
    return xstrdup(buf);
}

void bb_sys_init(int argc, char **argv, const char *app_dir)
{
    size_t len = 1;
    for (int i = 1; i < argc; i++) len += strlen(argv[i]) + 3;
    free(command);
    command = calloc(1, len);
    for (int i = 1; i < argc; i++) {
        if (i > 1) strcat(command, " ");
        int q = strchr(argv[i], ' ') != NULL;
        if (q) strcat(command, "\"");
        strcat(command, argv[i]);
        if (q) strcat(command, "\"");
    }
    free(app_path);
    if (app_dir) {
        char buf[PATH_MAX];
        app_path = xstrdup(realpath(app_dir, buf) ? buf : app_dir);
    } else
        app_path = dir_of(argc > 0 ? argv[0] : ".");
    free(exename);
    const char *p = argc > 0 && argv[0] ? argv[0] : "";
    const char *s = strrchr(p, '/');
    exename = xstrdup(s ? s + 1 : p);
    char *dot = strrchr(exename, '.');
    if (dot && !strcasecmp(dot, ".bas")) *dot = 0;
}

const char *bb_sys_command(void) { return command ? command : ""; }
const char *bb_sys_app_path(void) { return app_path ? app_path : ""; }
const char *bb_sys_app_exename(void) { return exename ? exename : ""; }

long bb_sys_shell(const char *cmd, int wait)
{
    if (wait) {
        int r = system(cmd);
        return r == -1 ? -1 : WIFEXITED(r) ? WEXITSTATUS(r) : -1;
    }
    pid_t pid = fork();
    if (pid < 0) return 0;
    if (pid == 0) {
        execl("/bin/sh", "sh", "-c", cmd, (char *)NULL);
        _exit(127);
    }
    return (long)pid;
}

char *bb_sys_environ(const char *name)
{
    const char *v = getenv(name);
    return v ? xstrdup(v) : NULL;
}

void bb_sys_beep(void)
{
    fputc('\a', stderr);
    fflush(stderr);
}

/* a process-local clipboard: tests must not touch the user's real one */
char *bb_sys_clipboard_get(void) { return xstrdup(clip ? clip : ""); }

int bb_sys_clipboard_set(const char *text)
{
    free(clip);
    clip = xstrdup(text);
    return 0;
}

/* --- Dir ---------------------------------------------------------------------------------- */

static DIR *dir;
static char *dir_path, *dir_pat;
static int dir_attrs;

static void dir_end(void)
{
    if (dir) closedir(dir);
    dir = NULL;
    free(dir_path);
    free(dir_pat);
    dir_path = dir_pat = NULL;
}

static int is_dir(const char *dirp, const char *name)
{
    char buf[PATH_MAX];
    struct stat st;
    snprintf(buf, sizeof buf, "%s/%s", dirp, name);
    return stat(buf, &st) == 0 && S_ISDIR(st.st_mode);
}

char *bb_sys_dir_next(void)
{
    struct dirent *e;
    while (dir && (e = readdir(dir))) {
        if (!strcmp(e->d_name, ".") || !strcmp(e->d_name, "..")) continue;
        if (fnmatch(dir_pat, e->d_name, 0)) continue;
        if (is_dir(dir_path, e->d_name) && !(dir_attrs & 16)) continue;
        return xstrdup(e->d_name);
    }
    dir_end();
    return NULL;
}

char *bb_sys_dir_first(const char *pattern, int attributes)
{
    dir_end();
    const char *s = strrchr(pattern, '/');
    dir_path = s ? (s == pattern ? xstrdup("/") : strndup(pattern, s - pattern)) : xstrdup(".");
    dir_pat = xstrdup(s ? s + 1 : pattern);
    if (!*dir_pat) {
        free(dir_pat);
        dir_pat = xstrdup("*");
    }
    dir_attrs = attributes;
    /* no wildcards: a single file */
    if (!strpbrk(dir_pat, "*?[")) {
        struct stat st;
        if (stat(pattern, &st) || (S_ISDIR(st.st_mode) && !(attributes & 16))) {
            dir_end();
            return NULL;
        }
        char *r = xstrdup(dir_pat);
        dir_end();
        return r;
    }
    dir = opendir(dir_path);
    return bb_sys_dir_next();
}

/* --- files -------------------------------------------------------------------------------- */

static int vb_err(int e)
{
    switch (e) {
    case ENOENT: return 53;
    case ENOTDIR: return 76;
    case EEXIST: return 58;
    case EACCES:
    case EPERM:
    case EROFS: return 70;
    case ENOSPC: return 61;
    default: return 75;
    }
}

int bb_sys_kill(const char *pattern)
{
    char *name = bb_sys_dir_first(pattern, 0);
    if (!name) return 53;
    const char *s = strrchr(pattern, '/');
    size_t dl = s ? (size_t)(s - pattern + 1) : 0;
    int e = 0;
    while (name) {
        char buf[PATH_MAX];
        snprintf(buf, sizeof buf, "%.*s%s", (int)dl, pattern, name);
        if (unlink(buf)) e = vb_err(errno);
        free(name);
        name = bb_sys_dir_next();
    }
    return e;
}

int bb_sys_mkdir(const char *path) { return mkdir(path, 0777) ? vb_err(errno) : 0; }
int bb_sys_rmdir(const char *path) { return rmdir(path) ? (errno == ENOENT ? 76 : vb_err(errno)) : 0; }
int bb_sys_chdir(const char *path) { return chdir(path) ? 76 : 0; }

char *bb_sys_curdir(void)
{
    char buf[PATH_MAX];
    return xstrdup(getcwd(buf, sizeof buf) ? buf : "");
}

int bb_sys_rename(const char *from, const char *to)
{
    struct stat st;
    if (stat(from, &st)) return 53;
    if (!stat(to, &st)) return 58;
    return rename(from, to) ? vb_err(errno) : 0;
}

int bb_sys_filecopy(const char *from, const char *to)
{
    FILE *in = fopen(from, "rb");
    if (!in) return 53;
    FILE *out = fopen(to, "wb");
    if (!out) {
        fclose(in);
        return vb_err(errno);
    }
    char buf[65536];
    size_t n;
    int e = 0;
    while ((n = fread(buf, 1, sizeof buf, in)) > 0)
        if (fwrite(buf, 1, n, out) != n) e = 61;
    fclose(in);
    if (fclose(out)) e = 61;
    return e;
}

long bb_sys_filelen(const char *path)
{
    struct stat st;
    if (stat(path, &st)) return -1;
    return S_ISDIR(st.st_mode) ? 0 : (long)st.st_size;
}

int bb_sys_getattr(const char *path)
{
    struct stat st;
    if (stat(path, &st)) return -1;
    int a = S_ISDIR(st.st_mode) ? 16 : 0;
    if (access(path, W_OK)) a |= 1;
    return a;
}
