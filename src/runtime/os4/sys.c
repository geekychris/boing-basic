/* bb_sys.h on AmigaOS 4: dos.library, intuition, textclip.library. */
#include "../bb_sys.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include <exec/exec.h>
#include <dos/dos.h>
#include <dos/dostags.h>
#include <dos/anchorpath.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/intuition.h>
#include <proto/textclip.h>

static char *command, *app_path, *exename;

static char *xstrdup(const char *s)
{
    char *o = malloc(strlen(s) + 1);
    if (o) strcpy(o, s);
    return o;
}

static char *lock_name(BPTR lock)
{
    char buf[1024];
    if (!lock || !IDOS->NameFromLock(lock, buf, sizeof buf)) return NULL;
    size_t n = strlen(buf);
    if (n > 1 && buf[n - 1] == '/') buf[n - 1] = 0;
    return xstrdup(buf);
}

static int sys_argc;
static char **sys_argv;
static void *sys_wbmsg;

void *bb_sys_wbstartup(void) { return sys_wbmsg; }
int bb_sys_argc(void) { return sys_argc > 1 ? sys_argc - 1 : 0; }
const char *bb_sys_argv(int i) { return i >= 0 && i + 1 < sys_argc ? sys_argv[i + 1] : ""; }

void bb_sys_init(int argc, char **argv, const char *app_dir)
{
    /* started from Workbench: argc is 0 and argv the WBStartup message */
    sys_wbmsg = argc == 0 ? (void *)argv : NULL;
    sys_argc = argc;
    sys_argv = argv;
    size_t len = 1;
    for (int i = 1; i < argc; i++) len += strlen(argv[i]) + 3;
    free(command);
    command = malloc(len);
    command[0] = 0;
    for (int i = 1; i < argc; i++) {
        if (i > 1) strcat(command, " ");
        int q = strchr(argv[i], ' ') != NULL;
        if (q) strcat(command, "\"");
        strcat(command, argv[i]);
        if (q) strcat(command, "\"");
    }
    free(app_path);
    app_path = NULL;
    if (app_dir) {
        BPTR l = IDOS->Lock(app_dir, SHARED_LOCK);
        app_path = l ? lock_name(l) : xstrdup(app_dir);
        if (l) IDOS->UnLock(l);
    } else
        app_path = lock_name(IDOS->GetProgramDir());
    if (!app_path) app_path = xstrdup("");
    free(exename);
    const char *p = argc > 0 && argv[0] ? argv[0] : "";
    exename = xstrdup((const char *)IDOS->FilePart(p));
    char *dot = strrchr(exename, '.');
    if (dot && !strcasecmp(dot, ".bas")) *dot = 0;
}

const char *bb_sys_command(void) { return command ? command : ""; }
const char *bb_sys_app_path(void) { return app_path ? app_path : ""; }
const char *bb_sys_app_exename(void) { return exename ? exename : ""; }

long bb_sys_shell(const char *cmd, int wait)
{
    if (wait) {
        LONG r = IDOS->SystemTags(cmd, SYS_UserShell, TRUE, TAG_DONE);
        return r;
    }
    BPTR in = IDOS->Open("NIL:", MODE_OLDFILE), out = IDOS->Open("NIL:", MODE_NEWFILE);
    if (!in || !out) {
        if (in) IDOS->Close(in);
        if (out) IDOS->Close(out);
        return 0;
    }
    /* asynchronous: the new process owns (and closes) the handles */
    LONG r = IDOS->SystemTags(cmd, SYS_Input, in, SYS_Output, out, SYS_Asynch, TRUE, SYS_UserShell, TRUE, TAG_DONE);
    if (r == -1) {
        IDOS->Close(in);
        IDOS->Close(out);
        return 0;
    }
    static long id;
    return ++id;
}

char *bb_sys_environ(const char *name)
{
    char buf[4096];
    LONG n = IDOS->GetVar(name, buf, sizeof buf, 0);
    if (n < 0) return NULL;
    return xstrdup(buf);
}

void bb_sys_beep(void) { IIntuition->DisplayBeep(NULL); }

static struct TextClipIFace *textclip(void)
{
    static struct Library *lib;
    static struct TextClipIFace *ifc;
    if (!ifc) {
        lib = IExec->OpenLibrary("textclip.library", 50);
        if (lib) ifc = (void *)IExec->GetInterface(lib, "main", 1, NULL);
    }
    return ifc;
}

char *bb_sys_clipboard_get(void)
{
    struct TextClipIFace *t = textclip();
    if (!t) return NULL;
    STRPTR buf = NULL;
    ULONG size = 0;
    if (!t->ReadClipVector(&buf, &size)) return xstrdup("");
    char *o = malloc(size + 1);
    if (o) {
        memcpy(o, buf, size);
        o[size] = 0;
    }
    t->DisposeClipVector(buf);
    return o;
}

int bb_sys_clipboard_set(const char *text)
{
    struct TextClipIFace *t = textclip();
    if (!t) return 5;
    return t->WriteClipVector(text, strlen(text)) ? 0 : 5;
}

/* --- Dir ---------------------------------------------------------------------------------- */

static struct AnchorPath *anchor;
static int dir_attrs;

/* VB wildcards (* and ?) to an AmigaDOS pattern (#? and ?); an existing #? is kept */
static char *amiga_pattern(const char *p)
{
    char *o = malloc(strlen(p) * 2 + 3), *q = o;
    for (; *p; p++) {
        if (*p == '*') {
            *q++ = '#';
            *q++ = '?';
        } else
            *q++ = *p;
    }
    *q = 0;
    /* "dir/" or "dir:" alone means everything in it */
    if (q > o && (q[-1] == '/' || q[-1] == ':')) strcpy(q, "#?");
    return o;
}

static void dir_end(void)
{
    if (anchor) {
        IDOS->MatchEnd(anchor);
        IDOS->FreeDosObject(DOS_ANCHORPATH, anchor);
        anchor = NULL;
    }
}

static char *dir_take(LONG err)
{
    while (!err) {
        /* the AP_ macros: ap_ExData is NULL before dos.library V54 */
        int isdir = AP_IS_DIRECTORY(anchor) || AP_IS_LINKDIR(anchor);
        if (!isdir || (dir_attrs & 16)) return xstrdup((const char *)AP_GET_NAME(anchor));
        err = IDOS->MatchNext(anchor);
    }
    dir_end();
    return NULL;
}

char *bb_sys_dir_first(const char *pattern, int attributes)
{
    dir_end();
    anchor = IDOS->AllocDosObjectTags(DOS_ANCHORPATH, ADO_Strlen, 0, ADO_Mask, SIGBREAKF_CTRL_C, TAG_DONE);
    if (!anchor) return NULL;
    dir_attrs = attributes;
    char *pat = amiga_pattern(pattern);
    LONG err = IDOS->MatchFirst(pat, anchor);
    free(pat);
    return dir_take(err);
}

char *bb_sys_dir_next(void)
{
    if (!anchor) return NULL;
    return dir_take(IDOS->MatchNext(anchor));
}

/* --- files -------------------------------------------------------------------------------- */

static int vb_err(LONG ioerr)
{
    switch (ioerr) {
    case ERROR_OBJECT_NOT_FOUND: return 53;
    case ERROR_DIR_NOT_FOUND: return 76;
    case ERROR_OBJECT_EXISTS: return 58;
    case ERROR_DELETE_PROTECTED:
    case ERROR_WRITE_PROTECTED:
    case ERROR_READ_PROTECTED:
    case ERROR_DISK_WRITE_PROTECTED:
    case ERROR_OBJECT_IN_USE: return 70;
    case ERROR_DIRECTORY_NOT_EMPTY: return 75;
    case ERROR_DEVICE_NOT_MOUNTED: return 68;
    case ERROR_DISK_FULL: return 61;
    default: return 75;
    }
}

int bb_sys_kill(const char *pattern)
{
    int found = 0;
    char *pat = amiga_pattern(pattern);
    struct AnchorPath *ap = IDOS->AllocDosObjectTags(DOS_ANCHORPATH, ADO_Strlen, 1024, TAG_DONE);
    if (!ap) {
        free(pat);
        return 7;
    }
    int e = 0;
    LONG err = IDOS->MatchFirst(pat, ap);
    while (!err) {
        if (AP_IS_FILE(ap)) {
            found = 1;
            if (!IDOS->Delete(ap->ap_Buffer)) e = vb_err(IDOS->IoErr());
        }
        err = IDOS->MatchNext(ap);
    }
    IDOS->MatchEnd(ap);
    IDOS->FreeDosObject(DOS_ANCHORPATH, ap);
    free(pat);
    return e ? e : found ? 0 : 53;
}

int bb_sys_mkdir(const char *path)
{
    BPTR l = IDOS->CreateDir(path);
    if (!l) return vb_err(IDOS->IoErr());
    IDOS->UnLock(l);
    return 0;
}

int bb_sys_rmdir(const char *path)
{
    if (bb_sys_getattr(path) != 16) return 76;
    return IDOS->Delete(path) ? 0 : vb_err(IDOS->IoErr());
}

int bb_sys_chdir(const char *path)
{
    BPTR l = IDOS->Lock(path, SHARED_LOCK);
    if (!l) return 76;
    BPTR old = IDOS->SetCurrentDir(l);
    if (old) IDOS->UnLock(old);
    return 0;
}

char *bb_sys_curdir(void)
{
    char *n = lock_name(IDOS->GetCurrentDir());
    return n ? n : xstrdup("");
}

int bb_sys_rename(const char *from, const char *to)
{
    return IDOS->Rename(from, to) ? 0 : vb_err(IDOS->IoErr());
}

int bb_sys_filecopy(const char *from, const char *to)
{
    BPTR in = IDOS->Open(from, MODE_OLDFILE);
    if (!in) return 53;
    BPTR out = IDOS->Open(to, MODE_NEWFILE);
    if (!out) {
        IDOS->Close(in);
        return vb_err(IDOS->IoErr());
    }
    /* in 64 KB pieces (newlib's/exec's big copies are unreliable on the QEMU guest anyway) */
    char *buf = malloc(65536);
    int e = buf ? 0 : 7;
    LONG n;
    while (!e && (n = IDOS->Read(in, buf, 65536)) > 0)
        if (IDOS->Write(out, buf, n) != n) e = vb_err(IDOS->IoErr());
    free(buf);
    IDOS->Close(in);
    IDOS->Close(out);
    return e;
}

static struct ExamineData *examine(const char *path)
{
    return IDOS->ExamineObjectTags(EX_StringNameInput, path, TAG_DONE);
}

long bb_sys_filelen(const char *path)
{
    struct ExamineData *d = examine(path);
    if (!d) return -1;
    long n = EXD_IS_FILE(d) ? (long)d->FileSize : 0;
    IDOS->FreeDosObject(DOS_EXAMINEDATA, d);
    return n;
}

int bb_sys_getattr(const char *path)
{
    struct ExamineData *d = examine(path);
    if (!d) return -1;
    int a = 0;
    if (EXD_IS_DIRECTORY(d)) a |= 16;
    if (d->Protection & EXDF_NO_WRITE) a |= 1;
    IDOS->FreeDosObject(DOS_EXAMINEDATA, d);
    return a;
}

/* the device/assign/volume part of a path exists in the DOS list (never touches it) */
static int volume_known(const char *path)
{
    const char *colon = strchr(path, ':');
    char name[64];
    struct DosList *dl;
    int found;
    size_t n;
    if (!colon) return 1;                       /* relative path */
    n = (size_t)(colon - path);
    if (n == 0) return 1;                       /* ":" = root of the current volume */
    if (n >= sizeof name) return 0;
    if (n == 7 && !strncasecmp(path, "PROGDIR", 7)) return 1;
    memcpy(name, path, n);
    name[n] = 0;
    dl = IDOS->LockDosList(LDF_ALL | LDF_READ);
    found = IDOS->FindDosEntry(dl, name, LDF_ALL) != NULL;
    IDOS->UnLockDosList(LDF_ALL | LDF_READ);
    return found;
}

/* requesters off while probing (pr_WindowPtr = -1), restored afterwards */
static APTR quiet_begin(void)
{
    struct Process *me = (struct Process *)IExec->FindTask(NULL);
    APTR old = me->pr_WindowPtr;
    me->pr_WindowPtr = (APTR)-1;
    return old;
}
static void quiet_end(APTR old) { ((struct Process *)IExec->FindTask(NULL))->pr_WindowPtr = old; }

int bb_sys_probe(const char *path)
{
    APTR old;
    BPTR l;
    if (!volume_known(path)) return 0;
    old = quiet_begin();
    l = IDOS->Lock(path, SHARED_LOCK);
    quiet_end(old);
    if (l) IDOS->UnLock(l);
    return l != 0;
}

char *bb_sys_real_path(const char *path)
{
    APTR old;
    BPTR l;
    char *n;
    if (!volume_known(path)) return NULL;
    old = quiet_begin();
    l = IDOS->Lock(path, SHARED_LOCK);
    quiet_end(old);
    if (!l) return NULL;
    {
        /* the device form ("DH1:AF-basic"), not the volume name ("chris:AF-basic"): GCC's ld
           can't search a volume-name path */
        char buf[1024];
        if (IDOS->DevNameFromLock(l, buf, sizeof buf, DN_FULLPATH)) {
            size_t k = strlen(buf);
            if (k > 1 && buf[k - 1] == '/') buf[k - 1] = 0;
            n = xstrdup(buf);
        } else n = lock_name(l);
    }
    IDOS->UnLock(l);
    return n;
}
