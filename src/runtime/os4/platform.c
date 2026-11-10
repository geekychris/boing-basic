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
#include <strings.h>
#include <errno.h>
#include <time.h>
#include <proto/locale.h>
#include <unistd.h>
#include <dirent.h>
#include <sys/stat.h>
#include <sys/time.h>

#include <proto/exec.h>
#include <proto/dos.h>
#include <devices/timer.h>
#include <proto/timer.h>
#include <dos/dos.h>
#include <dos/var.h>

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

/* minutes local time is ahead of UTC: locale.library's time zone (loc_GMTOffset is minutes
   west of Greenwich, so the sign flips). The Amiga clock runs on local time. */
int bb_plat_utc_offset(void)
{
    struct Library *lb = IExec->OpenLibrary("locale.library", 50);
    int off = 0;
    if (lb) {
        struct LocaleIFace *IL = (struct LocaleIFace *)IExec->GetInterface(lb, "main", 1, NULL);
        if (IL) {
            struct Locale *loc = IL->OpenLocale(NULL);
            if (loc) {
                off = -(int)loc->loc_GMTOffset;
                IL->CloseLocale(loc);
            }
            IExec->DropInterface((struct Interface *)IL);
        }
        IExec->CloseLibrary(lb);
    }
    return off;
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

static void tm_of(time_t s, bb_tm *tm)
{
    struct tm t;
    localtime_r(&s, &t);
    tm->year = t.tm_year + 1900;
    tm->month = t.tm_mon + 1;
    tm->day = t.tm_mday;
    tm->hour = t.tm_hour;
    tm->minute = t.tm_min;
    tm->second = t.tm_sec;
    tm->msec = 0;
}

/* AmigaOS protection bits: R W E D are set when the action is NOT allowed; A (archive) is set
   when the file has been backed up, the opposite of VB's vbArchive ("changed since backup") */
int bb_plat_get_attr(const char *path, long *attr, bb_tm *mtime)
{
    struct stat st;
    struct ExamineData *ed;
    char nb[1024];
    path = bb_os4_path(path, nb, sizeof nb);
    if (stat(path, &st) != 0) return 53;
    *attr = S_ISDIR(st.st_mode) ? 16 : 0;
    ed = IDOS->ExamineObjectTags(EX_StringNameInput, path, TAG_END);
    if (ed) {
        if (ed->Protection & EXDF_NO_WRITE) *attr |= 1;
        if (!(ed->Protection & EXDF_ARCHIVE) && !S_ISDIR(st.st_mode)) *attr |= 32;
        IDOS->FreeDosObject(DOS_EXAMINEDATA, ed);
    }
    if (mtime) tm_of(st.st_mtime, mtime);
    return 0;
}

int bb_plat_set_attr(const char *path, long attr)
{
    struct ExamineData *ed;
    uint32 prot;
    char nb[1024];
    path = bb_os4_path(path, nb, sizeof nb);
    ed = IDOS->ExamineObjectTags(EX_StringNameInput, path, TAG_END);
    if (!ed) return 53;
    prot = ed->Protection;
    IDOS->FreeDosObject(DOS_EXAMINEDATA, ed);
    if (attr & 1) prot |= EXDF_NO_WRITE | EXDF_NO_DELETE;
    else prot &= ~(uint32)(EXDF_NO_WRITE | EXDF_NO_DELETE);
    if (attr & 32) prot &= ~(uint32)EXDF_ARCHIVE;
    else prot |= EXDF_ARCHIVE;
    return IDOS->SetProtection(path, prot) ? 0 : 75;
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

/* Environ(n): the program's local shell variables, then the global ones in ENV: (top level),
 * as "NAME=value". The list is read again when n = 1. */
static char **env_list;
static int env_n;

static void env_add(const char *name, const char *value, long len)
{
    size_t nl = strlen(name);
    char *e;
    int i;
    for (i = 0; i < env_n; i++)         /* a local variable hides a global one */
        if (!strncasecmp(env_list[i], name, nl) && env_list[i][nl] == '=') return;
    e = malloc(nl + (size_t)len + 2);
    memcpy(e, name, nl);
    e[nl] = '=';
    memcpy(e + nl + 1, value, (size_t)len);
    e[nl + 1 + len] = 0;
    env_list = realloc(env_list, sizeof(char *) * (size_t)(env_n + 1));
    env_list[env_n++] = e;
}

static void env_read(void)
{
    struct Process *me = (struct Process *)IExec->FindTask(NULL);
    struct Node *n;
    APTR ctx;
    int i;
    for (i = 0; i < env_n; i++) free(env_list[i]);
    env_n = 0;
    for (n = (struct Node *)me->pr_LocalVars.mlh_Head; n->ln_Succ; n = n->ln_Succ) {
        struct LocalVar *lv = (struct LocalVar *)n;
        if (n->ln_Type == LV_VAR && !(lv->lv_Flags & GVF_BINARY_VAR) && n->ln_Name)
            env_add(n->ln_Name, lv->lv_Value ? (const char *)lv->lv_Value : "", lv->lv_Value ? lv->lv_Len : 0);
    }
    ctx = IDOS->ObtainDirContextTags(EX_StringNameInput, "ENV:", EX_DataFields, EXF_NAME | EXF_TYPE, TAG_DONE);
    if (ctx) {
        struct ExamineData *d;
        while ((d = IDOS->ExamineDir(ctx))) {
            char buf[1024];
            char path[300];
            LONG len;
            if (!EXD_IS_FILE(d)) continue;
            snprintf(path, sizeof path, "%s", d->Name);
            len = IDOS->GetVar(path, buf, sizeof buf, GVF_GLOBAL_ONLY);
            if (len >= 0) env_add(path, buf, len);
        }
        IDOS->ReleaseDirContext(ctx);
    }
}

const char *bb_plat_env_at(int index)
{
    if (index == 1 || !env_list) env_read();
    return index >= 1 && index <= env_n ? env_list[index - 1] : NULL;
}

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

/* --- background work (async Http) ------------------------------------------------------------
 * A worker is a child process (NP_Child) started with the job as its entry data. Cancel and
 * program end send it Ctrl-C (bb_plat_thread_break), which ends its network waits. It signals the
 * task that started it with a signal bit allocated once in that task (bb_plat_wake), which the
 * forms event loop includes in its Wait. join waits until the worker has returned from fn. */
typedef struct {
    void (*fn)(void *);
    void *arg;
    volatile int finished;
    struct Task *parent;
    struct Process *proc;
} bb_worker;

static int8 wake_bit = -1;
static struct Task *wake_task;

static int32 worker_entry(STRPTR args, int32 len, struct ExecBase *sys)
{
    (void)args; (void)len; (void)sys;
    bb_worker *w = (bb_worker *)IDOS->GetEntryData();
    w->fn(w->arg);
    IExec->Forbid();                  /* the parent may free w as soon as finished is set */
    w->finished = 1;
    bb_plat_wake();
    IExec->Permit();
    return 0;                         /* NP_Child: the program isn't unloaded before this returns */
}

void *bb_plat_thread_start(void (*fn)(void *), void *arg)
{
    if (wake_bit < 0) {
        wake_bit = IExec->AllocSignal(-1);
        wake_task = IExec->FindTask(NULL);
    }
    bb_worker *w = calloc(1, sizeof *w);
    if (!w) return NULL;
    w->fn = fn;
    w->arg = arg;
    w->parent = IExec->FindTask(NULL);
    struct Process *p = IDOS->CreateNewProcTags(NP_Entry, worker_entry, NP_EntryData, w, NP_Name, "Boing BASIC worker",
                                                NP_Priority, (int32)IExec->FindTask(NULL)->tc_Node.ln_Pri,
                                                NP_StackSize, 131072, NP_Child, TRUE, NP_Output, ZERO, NP_Input, ZERO,
                                                NP_CloseOutput, FALSE, NP_CloseInput, FALSE, TAG_DONE);
    if (!p) {
        free(w);
        return NULL;
    }
    w->proc = p;                      /* (worker_entry doesn't touch it) */
    return w;
}

void bb_plat_thread_join(void *p)
{
    bb_worker *w = p;
    if (!w) return;
    while (!w->finished) bb_plat_sleep_ms(5);
    free(w);
}

/* Ctrl-C to the worker: Roadshow's blocking calls and our WaitSelects end with it. Only while it
   hasn't finished: a finished worker's process may already be gone. */
void bb_plat_thread_break(void *p)
{
    bb_worker *w = p;
    if (!w) return;
    IExec->Forbid();
    if (!w->finished) IExec->Signal((struct Task *)w->proc, SIGBREAKF_CTRL_C);
    IExec->Permit();
}

void bb_plat_wake(void)
{
    if (wake_task && wake_bit >= 0) IExec->Signal(wake_task, 1u << wake_bit);
}

unsigned long bb_plat_wake_mask(void) { return wake_bit >= 0 ? 1ul << wake_bit : 0; }
