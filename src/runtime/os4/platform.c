/* os4/platform.c - libboing's platform layer (platform.h) on AmigaOS 4.1 / newlib
 *
 * Console and files go through newlib (stdio, dirent, unistd map onto dos.library),
 * MsgBox/InputBox use the requesters of the forms layer (bb_ui_msgbox / bb_ui_inputbox),
 * sleeps use timer.device (never Delay(1), see amiga_mcp's CLAUDE.md).
 */
#include "../platform.h"
#include "../bb_forms.h"
#include "../bb_sys.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <errno.h>
#include <time.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/time.h>

#include <proto/exec.h>
#include <proto/dos.h>
#include <devices/timer.h>
#include <proto/timer.h>
#include <dos/dos.h>

char *bb_plat_stack_limit(char *here)
{
    struct Task *t = IExec->FindTask(NULL);
    char *lo = (char *)t->tc_SPLower, *hi = (char *)t->tc_SPUpper;
    if (here <= lo || here > hi || hi - lo < 64 * 1024) return NULL;
    return lo + 24 * 1024;
}

void bb_plat_init(int argc, char **argv) { (void)argc; (void)argv; }
static struct MsgPort *ec_port;           /* bb_plat_seconds' EClock timer, freed at exit */
static struct TimeRequest *ec_tr;
static struct TimerIFace *ec_itimer;
static int ec_open;

void bb_plat_shutdown(void)
{
    fflush(stdout);
    if (ec_itimer) { IExec->DropInterface((struct Interface *)ec_itimer); ec_itimer = NULL; }
    if (ec_open) { IExec->CloseDevice((struct IORequest *)ec_tr); ec_open = 0; }
    if (ec_tr) { IExec->FreeSysObject(ASOT_IOREQUEST, ec_tr); ec_tr = NULL; }
    if (ec_port) { IExec->FreeSysObject(ASOT_PORT, ec_port); ec_port = NULL; }     /* its signal bit */
}

int bb_plat_break(void)
{
    return (IExec->SetSignal(0, SIGBREAKF_CTRL_C) & SIGBREAKF_CTRL_C) != 0;
}

void bb_plat_write(const char *p, size_t n) { fwrite(p, 1, n, stdout); }
void bb_plat_write_err(const char *p, size_t n) { fflush(stdout); fwrite(p, 1, n, stderr); fflush(stderr); }
void bb_plat_flush(void) { fflush(stdout); }

int bb_plat_read_line(char **line, size_t *len)
{
    size_t cap = 256, n = 0;
    char *b = (char *)malloc(cap);
    int c;
    fflush(stdout);
    if (!b) return 0;
    while ((c = getchar()) != EOF && c != '\n') {
        if (n + 1 >= cap) {
            char *nb = (char *)realloc(b, cap * 2);
            if (!nb) break;
            b = nb;
            cap *= 2;
        }
        b[n++] = (char)c;
    }
    if (c == EOF && n == 0) { free(b); return 0; }
    while (n > 0 && b[n - 1] == '\r') n--;
    b[n] = 0;
    *line = b;
    *len = n;
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

/* monotonic, EClock resolution (timer.device's ReadEClock) */
double bb_plat_seconds(void)
{
    static int tried;
    struct EClockVal ev;
    uint32 freq;
    if (!tried) {
        tried = 1;
        ec_port = (struct MsgPort *)IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
        if (ec_port) ec_tr = (struct TimeRequest *)IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Size, sizeof(struct TimeRequest),
                                                                             ASOIOR_ReplyPort, ec_port, TAG_DONE);
        if (ec_tr && IExec->OpenDevice(TIMERNAME, UNIT_ECLOCK, (struct IORequest *)ec_tr, 0) == 0) {
            ec_open = 1;
            ec_itimer = (struct TimerIFace *)IExec->GetInterface((struct Library *)ec_tr->Request.io_Device, "main", 1, NULL);
        }
    }
    if (ec_itimer) {
        freq = ec_itimer->ReadEClock(&ev);
        if (freq) return ((double)ev.ev_hi * 4294967296.0 + (double)ev.ev_lo) / (double)freq;
    }
    {
        struct timeval tv;
        gettimeofday(&tv, NULL);
        return (double)tv.tv_sec + tv.tv_usec / 1e6;
    }
}

void bb_plat_sleep_ms(long ms)
{
    struct MsgPort *port;
    struct TimeRequest *tr;
    if (ms <= 0) return;
    port = (struct MsgPort *)IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    if (!port) return;
    tr = (struct TimeRequest *)IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Size, sizeof(struct TimeRequest),
                                                         ASOIOR_ReplyPort, port, TAG_DONE);
    if (tr && IExec->OpenDevice(TIMERNAME, UNIT_MICROHZ, (struct IORequest *)tr, 0) == 0) {
        tr->Request.io_Command = TR_ADDREQUEST;
        tr->Time.Seconds = (uint32)(ms / 1000);
        tr->Time.Microseconds = (uint32)((ms % 1000) * 1000);
        IExec->DoIO((struct IORequest *)tr);
        IExec->CloseDevice((struct IORequest *)tr);
    }
    if (tr) IExec->FreeSysObject(ASOT_IOREQUEST, tr);
    IExec->FreeSysObject(ASOT_PORT, port);
}

static int err_of(int e, int notfound)
{
    switch (e) {
    case ENOENT: return notfound;
    case EEXIST: return 58;
    case EACCES: case EPERM: return 70;
    case ENOSPC: return 61;
    default: return 75;
    }
}

/* "DH1:/name" -> "DH1:name": in AmigaDOS a "/" right after the volume means its parent (there is
   none), but VB code builds paths as App.Path & "/" & name, and App.Path is "DH1:" for a
   program at a volume root. Every path the runtime hands to the OS goes through this. */
const char *bb_os4_path(const char *p, char *buf, size_t n)
{
    const char *c = p ? strchr(p, ':') : NULL;
    size_t k;
    if (!c || c[1] != '/') return p;
    k = (size_t)(c - p) + 1;
    if (k + strlen(c + 2) + 1 > n) return p;
    memcpy(buf, p, k);
    strcpy(buf + k, c + 2);
    return buf;
}

FILE *bb_plat_fopen(const char *path, const char *mode)
{
    char nb[1024];
#undef fopen
    return fopen(bb_os4_path(path, nb, sizeof nb), mode);
}

int bb_plat_remove(const char *path) { char nb[1024]; return remove(bb_os4_path(path, nb, sizeof nb)) == 0 ? 0 : err_of(errno, 53); }
int bb_plat_rename(const char *a, const char *b) { int e = bb_sys_rename(a, b); return e; }
int bb_plat_mkdir(const char *path) { return bb_sys_mkdir(path); }
int bb_plat_rmdir(const char *path) { return bb_sys_rmdir(path); }
int bb_plat_chdir(const char *path) { return bb_sys_chdir(path); }

int bb_plat_getcwd(char *buf, size_t n)
{
    char *d = bb_sys_curdir();
    if (!d) return 76;
    snprintf(buf, n, "%s", d);
    free(d);
    return 0;
}

int bb_plat_file_size(const char *path, long *size)
{
    struct stat st;
    char nb[1024];
    path = bb_os4_path(path, nb, sizeof nb);
    if (stat(path, &st) != 0) return 53;
    *size = (long)st.st_size;
    return 0;
}

int bb_plat_is_dir(const char *path)
{
    struct stat st;
    char nb[1024];
    path = bb_os4_path(path, nb, sizeof nb);
    return stat(path, &st) == 0 && S_ISDIR(st.st_mode);
}

typedef struct pdir { DIR *d; char path[1024]; } pdir;

void *bb_plat_dir_open(const char *dir)
{
    pdir *h;
    char nb[1024];
    dir = bb_os4_path(dir, nb, sizeof nb);
    DIR *d = opendir(dir && *dir && strcmp(dir, ".") ? dir : "");
    if (!d) return NULL;
    h = (pdir *)malloc(sizeof *h);
    h->d = d;
    snprintf(h->path, sizeof h->path, "%s", dir && strcmp(dir, ".") ? dir : "");
    return h;
}

const char *bb_plat_dir_next(void *hh, int *is_dir)
{
    pdir *h = (pdir *)hh;
    struct dirent *e = readdir(h->d);
    char full[2048];
    size_t n;
    if (!e) return NULL;
    n = strlen(h->path);
    if (n && h->path[n - 1] != '/' && h->path[n - 1] != ':') snprintf(full, sizeof full, "%s/%s", h->path, e->d_name);
    else snprintf(full, sizeof full, "%s%s", h->path, e->d_name);
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

static char *env_value;
const char *bb_plat_getenv(const char *name)
{
    free(env_value);
    env_value = bb_sys_environ(name);
    return env_value;
}

const char *bb_plat_env_at(int index) { (void)index; return NULL; }

int bb_plat_system(const char *cmd) { return (int)bb_sys_shell(cmd, 1); }
void bb_plat_beep(void) { bb_sys_beep(); }

long bb_plat_msgbox(const char *prompt, long buttons, const char *title)
{
    return bb_ui_msgbox(prompt, (int)buttons, title && *title ? title : NULL);
}

char *bb_plat_inputbox(const char *prompt, const char *title, const char *def)
{
    return bb_ui_inputbox(prompt, title && *title ? title : NULL, def);
}
