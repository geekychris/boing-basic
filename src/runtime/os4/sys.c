/* bb_sys.h on AmigaOS 4: dos.library, intuition, textclip.library. */
#include "../bb_sys.h"

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include <strings.h>

#include <exec/exec.h>
#include <dos/dos.h>
#include <dos/dostags.h>
#include <dos/anchorpath.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/intuition.h>
#include <proto/textclip.h>
#include <proto/iffparse.h>
#include <libraries/iffparse.h>
#include <workbench/startup.h>

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
/* boing started from a project icon (src/main/wbstart.c): the WBStartup, whose ArgList[1] is the
   program's own project and ArgList[2..] the other selected icons */
static void *sys_wbproj;
void bb_sys_set_wbproject(void *wbs) { sys_wbproj = wbs; }
void *bb_sys_wbproject(void) { return sys_wbproj; }
int bb_sys_argc(void) { return sys_argc > 1 ? sys_argc - 1 : 0; }
int bb_sys_raw_argc(void) { return sys_argc; }
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
    /* from Workbench (argc 0) the program's name is the first WBArg's */
    struct WBStartup *wbs = argc == 0 ? (struct WBStartup *)argv : NULL;
    const char *p = argc > 0 && argv[0] ? argv[0]
                  : wbs && wbs->sm_NumArgs > 0 && wbs->sm_ArgList[0].wa_Name ? (const char *)wbs->sm_ArgList[0].wa_Name : "";
    exename = xstrdup((const char *)IDOS->FilePart(p));
    char *dot = strrchr(exename, '.');
    if (dot && (!strcasecmp(dot, ".bas") || !strcasecmp(dot, ".bbp") || !strcasecmp(dot, ".bbc"))) *dot = 0;
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

/* units other than 0 (textclip.library only knows unit 0): IFF FTXT CHRS through iffparse */
#define ID_FTXT MAKE_ID('F', 'T', 'X', 'T')
#define ID_CHRS MAKE_ID('C', 'H', 'R', 'S')

static struct IFFParseIFace *iffparse(void)
{
    static struct Library *lib;
    static struct IFFParseIFace *ifc;
    if (!ifc) {
        lib = IExec->OpenLibrary("iffparse.library", 39);
        if (lib) ifc = (void *)IExec->GetInterface(lib, "main", 1, NULL);
    }
    return ifc;
}

/* opens unit u for reading or writing; NULL on error */
static struct IFFHandle *clip_open(struct IFFParseIFace *iff, int u, int mode)
{
    struct IFFHandle *h = iff->AllocIFF();
    if (!h) return NULL;
    struct ClipboardHandle *ch = iff->OpenClipboard(u);
    if (!ch) {
        iff->FreeIFF(h);
        return NULL;
    }
    h->iff_Stream = (uint32)ch;
    iff->InitIFFasClip(h);
    if (iff->OpenIFF(h, mode)) {
        iff->CloseClipboard(ch);
        iff->FreeIFF(h);
        return NULL;
    }
    return h;
}

static void clip_close(struct IFFParseIFace *iff, struct IFFHandle *h)
{
    iff->CloseIFF(h);
    iff->CloseClipboard((struct ClipboardHandle *)h->iff_Stream);
    iff->FreeIFF(h);
}

static char *unit_get(int u)
{
    struct IFFParseIFace *iff = iffparse();
    if (!iff) return NULL;
    struct IFFHandle *h = clip_open(iff, u, IFFF_READ);
    if (!h) return xstrdup("");                /* an empty unit */
    char *o = NULL;
    size_t n = 0;
    iff->StopChunk(h, ID_FTXT, ID_CHRS);
    /* every CHRS chunk of every FTXT form, one after another */
    for (;;) {
        int32 e = iff->ParseIFF(h, IFFPARSE_SCAN);
        if (e == IFFERR_EOC) continue;
        if (e) break;
        struct ContextNode *cn = iff->CurrentChunk(h);
        if (!cn || cn->cn_Size <= 0) continue;
        char *p = realloc(o, n + cn->cn_Size + 1);
        if (!p) break;
        o = p;
        int32 r = iff->ReadChunkBytes(h, o + n, cn->cn_Size);
        if (r > 0) n += r;
    }
    clip_close(iff, h);
    if (!o) return xstrdup("");
    o[n] = 0;
    return o;
}

static int unit_set(int u, const char *text)
{
    struct IFFParseIFace *iff = iffparse();
    if (!iff) return 5;
    struct IFFHandle *h = clip_open(iff, u, IFFF_WRITE);
    if (!h) return 5;
    int32 len = strlen(text), err = 5;
    if (!iff->PushChunk(h, ID_FTXT, ID_FORM, IFFSIZE_UNKNOWN)) {
        if (!iff->PushChunk(h, 0, ID_CHRS, len) && iff->WriteChunkBytes(h, (APTR)text, len) == len && !iff->PopChunk(h))
            err = 0;
        if (iff->PopChunk(h)) err = 5;
    }
    clip_close(iff, h);
    return err;
}

char *bb_sys_clipboard_get(void)
{
    if (bb_sys_clip_unit) return unit_get(bb_sys_clip_unit);
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
    if (bb_sys_clip_unit) return unit_set(bb_sys_clip_unit, text);
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

const char *bb_os4_path(const char *p, char *buf, size_t n);

int bb_sys_kill(const char *pattern)
{
    char nb_pattern[1024];
    pattern = bb_os4_path(pattern, nb_pattern, sizeof nb_pattern);
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
    char nb_path[1024];
    path = bb_os4_path(path, nb_path, sizeof nb_path);
    BPTR l = IDOS->CreateDir(path);
    if (!l) return vb_err(IDOS->IoErr());
    IDOS->UnLock(l);
    return 0;
}

int bb_sys_rmdir(const char *path)
{
    char nb_path[1024];
    path = bb_os4_path(path, nb_path, sizeof nb_path);
    if (bb_sys_getattr(path) != 16) return 76;
    return IDOS->Delete(path) ? 0 : vb_err(IDOS->IoErr());
}

int bb_sys_chdir(const char *path)
{
    char nb_path[1024];
    path = bb_os4_path(path, nb_path, sizeof nb_path);
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
    char nb_from[1024];
    char nb_to[1024];
    from = bb_os4_path(from, nb_from, sizeof nb_from);
    to = bb_os4_path(to, nb_to, sizeof nb_to);
    return IDOS->Rename(from, to) ? 0 : vb_err(IDOS->IoErr());
}

int bb_sys_filecopy(const char *from, const char *to)
{
    char nb_from[1024];
    char nb_to[1024];
    from = bb_os4_path(from, nb_from, sizeof nb_from);
    to = bb_os4_path(to, nb_to, sizeof nb_to);
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
    char nb_path[1024];
    path = bb_os4_path(path, nb_path, sizeof nb_path);
    struct ExamineData *d = examine(path);
    if (!d) return -1;
    long n = EXD_IS_FILE(d) ? (long)d->FileSize : 0;
    IDOS->FreeDosObject(DOS_EXAMINEDATA, d);
    return n;
}

int bb_sys_getattr(const char *path)
{
    char nb_path[1024];
    path = bb_os4_path(path, nb_path, sizeof nb_path);
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
    char nb_path[1024];
    path = bb_os4_path(path, nb_path, sizeof nb_path);
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
    char nb_path[1024];
    path = bb_os4_path(path, nb_path, sizeof nb_path);
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

/* ---- Process ---- */

int bb_sys_setenv(const char *name, const char *value)
{
    if (!name || !*name) return 5;
    if (!value) {
        IDOS->DeleteVar(name, GVF_LOCAL_ONLY);     /* removing one that isn't there is fine */
        return 0;
    }
    return IDOS->SetVar(name, value, -1, GVF_LOCAL_ONLY) ? 0 : 5;
}

/* a whole file into a malloc'd buffer (NUL-terminated); "" if it can't be read */
static char *slurp(const char *path, long *len)
{
    BPTR fh = IDOS->Open(path, MODE_OLDFILE);
    char *buf = NULL;
    long n = 0, cap = 0;
    if (fh) {
        for (;;) {
            LONG r;
            if (n + 4096 + 1 > cap) {
                cap = (n + 4096 + 1) * 2;
                buf = realloc(buf, (size_t)cap);
            }
            r = IDOS->Read(fh, buf + n, 4096);
            if (r <= 0) break;
            n += r;
        }
        IDOS->Close(fh);
    }
    if (!buf) buf = malloc(1);
    buf[n] = 0;
    *len = n;
    return buf;
}

int bb_sys_run(const char *cmd, const char *in, long inlen, char **out, long *outlen, char **eout, long *eoutlen,
               char *err, int errsz)
{
    static unsigned long seq;
    char inname[64], outname[64], errname[64];
    BPTR fin = 0, fout = 0, ferr = 0;
    LONG rc;
    unsigned long id = (unsigned long)(uintptr_t)IExec->FindTask(NULL);
    seq++;
    *out = *eout = NULL;
    *outlen = *eoutlen = 0;
    snprintf(inname, sizeof inname, "T:bbproc.%lx.%lu.in", id, seq);
    snprintf(outname, sizeof outname, "T:bbproc.%lx.%lu.out", id, seq);
    snprintf(errname, sizeof errname, "T:bbproc.%lx.%lu.err", id, seq);
    if (in && inlen > 0) {
        BPTR w = IDOS->Open(inname, MODE_NEWFILE);
        if (!w || IDOS->Write(w, in, inlen) != inlen) {
            if (w) IDOS->Close(w);
            IDOS->Delete(inname);
            snprintf(err, (size_t)errsz, "can't write the input file in T:");
            return -1;
        }
        IDOS->Close(w);
        fin = IDOS->Open(inname, MODE_OLDFILE);
    } else
        fin = IDOS->Open("NIL:", MODE_OLDFILE);
    fout = IDOS->Open(outname, MODE_NEWFILE);
    ferr = IDOS->Open(errname, MODE_NEWFILE);
    if (!fin || !fout || !ferr) {
        if (fin) IDOS->Close(fin);
        if (fout) IDOS->Close(fout);
        if (ferr) IDOS->Close(ferr);
        IDOS->Delete(inname);
        IDOS->Delete(outname);
        IDOS->Delete(errname);
        snprintf(err, (size_t)errsz, "can't open the files for the command's input and output in T:");
        return -1;
    }
    rc = IDOS->SystemTags(cmd, SYS_Input, fin, SYS_Output, fout, SYS_Error, ferr, SYS_UserShell, TRUE, TAG_DONE);
    /* synchronous: the handles stay ours */
    IDOS->Close(fin);
    IDOS->Close(fout);
    IDOS->Close(ferr);
    IDOS->Delete(inname);
    *out = slurp(outname, outlen);
    *eout = slurp(errname, eoutlen);
    IDOS->Delete(outname);
    IDOS->Delete(errname);
    if (rc == -1) {
        snprintf(err, (size_t)errsz, "can't start the command (no shell?)");
        return -1;
    }
    return (int)rc;
}
