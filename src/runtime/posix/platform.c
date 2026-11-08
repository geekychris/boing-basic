/* posix/platform.c - platform layer for macOS / Linux */
#define _POSIX_C_SOURCE 200809L
#define _DEFAULT_SOURCE
#define _DARWIN_C_SOURCE
#include "../platform.h"
#include <sys/resource.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <signal.h>

extern char **environ;

static volatile sig_atomic_t brk;
static void on_sigint(int s) { (void)s; brk = 1; }
char *bb_plat_stack_limit(char *here)
{
    struct rlimit rl;
    uintptr_t size = 8u << 20, margin = 256u << 10, h = (uintptr_t)here;
    if (getrlimit(RLIMIT_STACK, &rl) == 0 && rl.rlim_cur != RLIM_INFINITY && rl.rlim_cur < ((rlim_t)1 << 30))
        size = (uintptr_t)rl.rlim_cur;
    if (size < 2 * margin || h < size) return NULL;
    return (char *)(h - size + margin);
}

void bb_plat_init(int argc, char **argv) { (void)argc; (void)argv; signal(SIGINT, on_sigint); }
int bb_plat_break(void) { int b = brk; brk = 0; return b; }
void bb_plat_shutdown(void) { fflush(stdout); }

void bb_plat_write(const char *p, size_t n) { fwrite(p, 1, n, stdout); }
void bb_plat_write_err(const char *p, size_t n) { fflush(stdout); fwrite(p, 1, n, stderr); fflush(stderr); }
void bb_plat_flush(void) { fflush(stdout); }

int bb_plat_read_line(char **line, size_t *len)
{
    size_t cap = 0;
    ssize_t n;
    char *l = NULL;
    fflush(stdout);
    n = getline(&l, &cap, stdin);
    if (n < 0) { free(l); return 0; }
    while (n > 0 && (l[n - 1] == '\n' || l[n - 1] == '\r')) l[--n] = 0;
    *line = l;
    *len = (size_t)n;
    return 1;
}

void bb_plat_localtime(bb_tm *tm)
{
    struct timeval tv;
    struct tm t;
    time_t s;
    gettimeofday(&tv, NULL);
    s = tv.tv_sec;
    localtime_r(&s, &t);
    tm->year = t.tm_year + 1900;
    tm->month = t.tm_mon + 1;
    tm->day = t.tm_mday;
    tm->hour = t.tm_hour;
    tm->minute = t.tm_min;
    tm->second = t.tm_sec;
    tm->msec = (int)(tv.tv_usec / 1000);
}

double bb_plat_seconds(void)
{
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (double)ts.tv_sec + ts.tv_nsec / 1e9;
}

void bb_plat_sleep_ms(long ms)
{
    struct timespec ts;
    ts.tv_sec = ms / 1000;
    ts.tv_nsec = (ms % 1000) * 1000000L;
    nanosleep(&ts, NULL);
}

static int err_of(int e, int notfound)
{
    switch (e) {
    case ENOENT: return notfound;
    case EEXIST: return 58;
    case EACCES: case EPERM: return 70;
    case ENOSPC: return 61;
    case ENOTEMPTY: return 75;
    default: return 75;
    }
}

int bb_plat_remove(const char *path) { return unlink(path) == 0 ? 0 : err_of(errno, 53); }
int bb_plat_rename(const char *a, const char *b) { return rename(a, b) == 0 ? 0 : err_of(errno, 53); }
int bb_plat_mkdir(const char *path) { return mkdir(path, 0777) == 0 ? 0 : err_of(errno, 76); }
int bb_plat_rmdir(const char *path) { return rmdir(path) == 0 ? 0 : err_of(errno, 76); }
int bb_plat_chdir(const char *path) { return chdir(path) == 0 ? 0 : err_of(errno, 76); }
int bb_plat_getcwd(char *buf, size_t n) { return getcwd(buf, n) ? 0 : 76; }

int bb_plat_file_size(const char *path, long *size)
{
    struct stat st;
    if (stat(path, &st) != 0) return 53;
    *size = (long)st.st_size;
    return 0;
}

int bb_plat_is_dir(const char *path)
{
    struct stat st;
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

typedef struct pdir { DIR *d; char path[1024]; } pdir;

void *bb_plat_dir_open(const char *dir)
{
    pdir *h;
    DIR *d = opendir(dir && *dir ? dir : ".");
    if (!d) return NULL;
    h = (pdir *)malloc(sizeof *h);
    h->d = d;
    snprintf(h->path, sizeof h->path, "%s", dir && *dir ? dir : ".");
    return h;
}

const char *bb_plat_dir_next(void *hh, int *is_dir)
{
    pdir *h = (pdir *)hh;
    struct dirent *e = readdir(h->d);
    char full[2048];
    if (!e) return NULL;
    snprintf(full, sizeof full, "%s/%s", h->path, e->d_name);
    *is_dir = bb_plat_is_dir(full);
    return e->d_name;
}

void bb_plat_dir_close(void *hh)
{
    pdir *h = (pdir *)hh;
    closedir(h->d);
    free(h);
}

char bb_plat_path_sep(void) { return '/'; }

const char *bb_plat_getenv(const char *name) { return getenv(name); }

const char *bb_plat_env_at(int index)
{
    int i;
    for (i = 1; environ[i - 1]; i++) if (i == index) return environ[i - 1];
    return NULL;
}

int bb_plat_system(const char *cmd) { return system(cmd); }
void bb_plat_beep(void) { fputc('\a', stdout); fflush(stdout); }

long bb_plat_msgbox(const char *prompt, long buttons, const char *title)
{
    long kind = buttons & 7;
    char *line = NULL;
    size_t n;
    if (title && *title) printf("[%s] %s\n", title, prompt); else printf("%s\n", prompt);
    fflush(stdout);
    if (kind == 0) return 1;                    /* vbOK */
    if (kind == 4 || kind == 3) {               /* Yes/No(/Cancel) */
        printf("(y/n) ");
        if (!bb_plat_read_line(&line, &n)) return kind == 3 ? 2 : 7;
        if (line[0] == 'y' || line[0] == 'Y') { free(line); return 6; }
        if (kind == 3 && (line[0] == 'c' || line[0] == 'C')) { free(line); return 2; }
        free(line);
        return 7;
    }
    if (kind == 1) {                            /* OK/Cancel */
        printf("(ok/cancel) ");
        if (!bb_plat_read_line(&line, &n)) return 2;
        if (line[0] == 'c' || line[0] == 'C') { free(line); return 2; }
        free(line);
        return 1;
    }
    return 1;
}

char *bb_plat_inputbox(const char *prompt, const char *title, const char *def)
{
    char *line = NULL;
    size_t n;
    if (title && *title) printf("[%s] ", title);
    printf("%s ", prompt);
    fflush(stdout);
    if (!bb_plat_read_line(&line, &n)) return def ? strdup(def) : NULL;
    if (n == 0 && def && *def) { free(line); return strdup(def); }
    return line;
}
