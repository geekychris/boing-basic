/* Workbench, ARexx, locale and help for BASIC programs on AmigaOS 4 (docs/ui.md sections 6
 * and 7): App.ToolType, App.Arg, AppWindows (files dropped on a form), an AppIcon, AppMenuItems,
 * App.SaveIcon, an ARexx port (ARexx_Command), App.SendARexx, catalogs (App.Str and the .afg's
 * "$id:text" strings), AmigaGuide help, and pictures on the clipboard (IFF ILBM through
 * datatypes). The event loop (forms.c pump) waits on bbf_app_sigmask() too. */
#include "forms_int.h"
#include "../bb_app.h"
#include "../bb_sys.h"
#include "../boing.h"
#include "../canvas.h"

#include <workbench/workbench.h>
#include <workbench/startup.h>
#include <workbench/icon.h>
#include <rexx/storage.h>
#include <rexx/rxslib.h>
#include <libraries/amigaguide.h>
#include <datatypes/datatypes.h>
#include <datatypes/pictureclass.h>
#include <dos/dostags.h>
#include <proto/wb.h>
#include <proto/icon.h>
#include <proto/rexxsyslib.h>
#include <proto/locale.h>
#include <proto/amigaguide.h>
#include <proto/datatypes.h>
#include <proto/iffparse.h>
#include <libraries/iffparse.h>
#include <devices/clipboard.h>
const char *bb_os4_path(const char *p, char *buf, size_t n);   /* "DH1:/x" -> "DH1:x" (platform.c) */

static int app_debug = -1;
#define DBG(...) do { if (app_debug < 0) app_debug = getenv("BB_DEBUG_APP") != NULL; \
                      if (app_debug) { fprintf(stderr, "# app: " __VA_ARGS__); fflush(stderr); } } while (0)

static struct Library *WbLib, *IconLib, *RexxLib, *LocaleLib, *GuideLib, *DtLib;
static struct WorkbenchIFace *IWB;
static struct IconIFace *IIc;
static struct RexxSysIFace *IRx;
static struct LocaleIFace *ILoc;
static struct AmigaGuideIFace *IAG;
static struct DataTypesIFace *IDT;

static void *open_if(struct Library **lib, const char *name, int ver)
{
    static int registered;
    if (!registered) {          /* programs without forms use App too: close everything at exit */
        registered = 1;
        atexit(bbf_app_cleanup);
    }
    if (!*lib) *lib = IExec->OpenLibrary(name, ver);
    return *lib ? IExec->GetInterface(*lib, "main", 1, NULL) : NULL;
}

static struct WorkbenchIFace *wb(void) { if (!IWB) IWB = open_if(&WbLib, "workbench.library", 44); return IWB; }
static struct IconIFace *icon(void) { if (!IIc) IIc = open_if(&IconLib, "icon.library", 44); return IIc; }
static struct RexxSysIFace *rexx(void) { if (!IRx) IRx = open_if(&RexxLib, "rexxsyslib.library", 36); return IRx; }
static struct LocaleIFace *loc(void) { if (!ILoc) ILoc = open_if(&LocaleLib, "locale.library", 38); return ILoc; }
static struct AmigaGuideIFace *guide(void) { if (!IAG) IAG = open_if(&GuideLib, "amigaguide.library", 39); return IAG; }
static struct DataTypesIFace *dt(void) { if (!IDT) IDT = open_if(&DtLib, "datatypes.library", 45); return IDT; }

const char *bb_app_settings_dir(int archive) { return archive ? "ENVARC:" : "ENV:"; }

/* strings handed back through bb_fval */
static char *hold;
static int rs(bb_fval *out, const char *s)
{
    char *n = xstrdup(s ? s : "");
    free(hold);
    hold = n;
    out->type = BB_FV_STR;
    out->s = hold;
    return 0;
}
static int ri(bb_fval *out, int32 v)
{
    out->type = BB_FV_INT;
    out->i = v;
    return 0;
}

static char *lock_path(BPTR lock, const char *name)
{
    char buf[1024];
    buf[0] = 0;
    if (lock) IDOS->NameFromLock(lock, buf, sizeof buf);
    if (name && *name) IDOS->AddPart(buf, name, sizeof buf);
    return xstrdup(buf);
}

/* --- tooltypes and arguments -------------------------------------------------------------- */

static struct DiskObject *prog_icon;
static int icon_tried;

static struct DiskObject *program_icon(void)
{
    if (icon_tried || !icon()) return prog_icon;
    icon_tried = 1;
    struct WBStartup *wbs = bb_sys_wbstartup();
    if (wbs && wbs->sm_NumArgs > 0) {
        BPTR old = IDOS->SetCurrentDir(wbs->sm_ArgList[0].wa_Lock);
        prog_icon = IIc->GetDiskObject(wbs->sm_ArgList[0].wa_Name);
        IDOS->SetCurrentDir(old);
    }
    if (!prog_icon) {
        char path[1024];
        snprintf(path, sizeof path, "%s", bb_sys_app_path());
        IDOS->AddPart(path, bb_sys_app_exename(), sizeof path);
        prog_icon = IIc->GetDiskObject(path);
    }
    return prog_icon;
}

static int tooltype_count(void)
{
    struct DiskObject *d = program_icon();
    int n = 0;
    if (d && d->do_ToolTypes)
        while (d->do_ToolTypes[n]) n++;
    return n;
}

static int tooltype(const char *name, const char *def, bb_fval *out)
{
    struct DiskObject *d = program_icon();
    if (d && d->do_ToolTypes) {
        STRPTR v = IIc->FindToolType((STRPTR *)d->do_ToolTypes, name);
        if (v) return rs(out, *v ? (char *)v : "1");
    }
    return rs(out, def);
}

/* the files the program was given: Workbench arguments, else the shell's */
static int arg_count(void)
{
    struct WBStartup *wbs = bb_sys_wbstartup();
    if (wbs) return wbs->sm_NumArgs > 1 ? wbs->sm_NumArgs - 1 : 0;
    return bb_sys_argc();
}

static int arg(int i, bb_fval *out)
{
    struct WBStartup *wbs = bb_sys_wbstartup();
    if (i < 0 || i >= arg_count()) return 381;
    if (wbs) {
        char *p = lock_path(wbs->sm_ArgList[i + 1].wa_Lock, (const char *)wbs->sm_ArgList[i + 1].wa_Name);
        rs(out, p);
        free(p);
        return 0;
    }
    return rs(out, bb_sys_argv(i));
}

/* --- AppWindow, AppIcon, AppMenuItem ------------------------------------------------------- */

static struct MsgPort *app_port;
static char **drops;
static int ndrops;
static struct AppIcon *appicon;
static struct DiskObject *appicon_obj;
static char *appicon_name;
static struct AppMenuItem *menuitems[16];
static char *menutexts[16];
static int nmenuitems;

static bb_int app_doevents(void);

static struct MsgPort *port(void)
{
    bb_set_doevents(app_doevents);
    if (!app_port) app_port = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    return app_port;
}

static void set_drops(struct AppMessage *am)
{
    for (int i = 0; i < ndrops; i++) free(drops[i]);
    free(drops);
    drops = NULL;
    ndrops = 0;
    if (am->am_NumArgs <= 0) return;
    drops = calloc(am->am_NumArgs, sizeof *drops);
    for (int i = 0; i < am->am_NumArgs; i++) drops[ndrops++] = lock_path(am->am_ArgList[i].wa_Lock, (const char *)am->am_ArgList[i].wa_Name);
}

static int form_wants_drops(bb_form *f)
{
    if (f->dropmode || afg_get_bool(f->afg, "dropfiles")) return 1;
    for (int i = 0; i < f->nctls; i++)
        if (afg_get_bool(f->ctls[i]->node, "dropfiles")) return 1;
    return 0;
}

void bbf_app_window_open(bb_form *f)
{
    if (f->appwin || !f->win || !form_wants_drops(f) || !wb() || !port()) return;
    f->appwin = IWB->AddAppWindowA(1, (uint32)f, f->win, app_port, NULL);
}

void bbf_app_window_close(bb_form *f)
{
    if (f->appwin && IWB) IWB->RemoveAppWindow(f->appwin);
    f->appwin = NULL;
}

static void app_drop_on_form(struct AppMessage *am)
{
    bb_form *f;
    for (f = forms; f; f = f->next)
        if ((uint32)f == am->am_UserData && f->loaded) break;
    if (!f) return;
    set_drops(am);
    int32_t a[3] = { ndrops, am->am_MouseX, am->am_MouseY };
    /* the control under the drop point that takes files, else the form */
    for (int i = f->nctls - 1; i >= 0; i--) {
        bb_ctl *c = f->ctls[i];
        if (!c->obj || !afg_takes_space(c->kind) || c->kind == AFG_TOOL || !afg_get_bool(c->node, "dropfiles")) continue;
        struct Gadget *g = (struct Gadget *)c->obj;
        if (am->am_MouseX >= g->LeftEdge && am->am_MouseY >= g->TopEdge && am->am_MouseX < g->LeftEdge + g->Width &&
            am->am_MouseY < g->TopEdge + g->Height) {
            a[1] -= g->LeftEdge;
            a[2] -= g->TopEdge;
            fire(f, c->name, "OLEDragDrop", 3, a);
            return;
        }
    }
    a[1] -= f->win ? f->win->BorderLeft : 0;
    a[2] -= f->win ? f->win->BorderTop : 0;
    fire(f, "Form", "OLEDragDrop", 3, a);
}

static void app_messages(void)
{
    struct AppMessage *am;
    while (app_port && (am = (struct AppMessage *)IExec->GetMsg(app_port))) {
        if (am->am_Type == AMTYPE_APPWINDOW)
            app_drop_on_form(am);
        else if (am->am_Type == AMTYPE_APPICON) {
            set_drops(am);
            if (am->am_NumArgs == 0)
                bb_app_event("AppIcon_DblClick", 0, NULL);
            else {
                bb_value v = bb_v_long(ndrops);
                bb_app_event("AppIcon_DragDrop", 1, &v);
            }
        } else if (am->am_Type == AMTYPE_APPMENUITEM) {
            set_drops(am);
            bb_value v[2] = { bb_v_long((int32)am->am_ID), bb_v_long(ndrops) };
            bb_app_event("AppMenu_Click", 2, v);
        }
        IExec->ReplyMsg(&am->am_Message);
    }
}

static int show_appicon(const char *name, const char *file)
{
    if (!wb() || !icon() || !port()) return 5;
    if (appicon) IWB->RemoveAppIcon(appicon);
    appicon = NULL;
    if (appicon_obj) IIc->FreeDiskObject(appicon_obj);
    appicon_obj = NULL;
    if (file && *file) {
        char f[1024];
        char nb_[1024];
        snprintf(f, sizeof f, "%s", bb_os4_path(file, nb_, sizeof nb_));
        size_t n = strlen(f);
        if (n > 5 && !strcasecmp(f + n - 5, ".info")) f[n - 5] = 0;
        appicon_obj = IIc->GetDiskObject(f);
    }
    if (!appicon_obj) {
        struct DiskObject *p = program_icon();
        if (p) appicon_obj = IIc->DupDiskObjectA(p, NULL);
    }
    if (!appicon_obj) appicon_obj = IIc->GetDefDiskObject(WBTOOL);
    if (!appicon_obj) return 7;
    appicon_obj->do_CurrentX = appicon_obj->do_CurrentY = NO_ICON_POSITION;
    free(appicon_name);
    appicon_name = xstrdup(name);
    appicon = IWB->AddAppIconA(1, 0, appicon_name, app_port, 0, appicon_obj, NULL);
    return appicon ? 0 : 7;
}

static void hide_appicon(void)
{
    if (appicon) IWB->RemoveAppIcon(appicon);
    appicon = NULL;
    if (appicon_obj) IIc->FreeDiskObject(appicon_obj);
    appicon_obj = NULL;
}

static int add_menuitem(const char *text, bb_fval *ret)
{
    if (nmenuitems >= 16) return 7;
    if (!wb() || !port()) return 5;
    menutexts[nmenuitems] = xstrdup(text);
    menuitems[nmenuitems] = IWB->AddAppMenuItemA(nmenuitems, 0, menutexts[nmenuitems], app_port, NULL);
    if (!menuitems[nmenuitems]) {
        free(menutexts[nmenuitems]);
        return 7;
    }
    return ri(ret, nmenuitems++);
}

/* App.SaveIcon path [, defaultTool [, template]]: a project icon for a saved document */
static int save_icon(const char *path, const char *tool, const char *templ)
{
    if (!icon()) return 5;
    struct DiskObject *d = NULL;
    char nbt_[1024];
    if (templ && *templ) d = IIc->GetDiskObject(bb_os4_path(templ, nbt_, sizeof nbt_));
    if (!d) d = IIc->GetDefDiskObject(WBPROJECT);
    if (!d) return 7;
    char deftool[1024];
    if (tool && *tool) snprintf(deftool, sizeof deftool, "%s", tool);
    else {
        snprintf(deftool, sizeof deftool, "%s", bb_sys_app_path());
        IDOS->AddPart(deftool, bb_sys_app_exename(), sizeof deftool);
    }
    STRPTR old = d->do_DefaultTool;
    uint8 oldtype = d->do_Type;
    int16 ox = d->do_CurrentX, oy = d->do_CurrentY;
    d->do_DefaultTool = deftool;
    d->do_Type = WBPROJECT;
    d->do_CurrentX = d->do_CurrentY = NO_ICON_POSITION;
    int ok = IIc->PutDiskObject(path, d);
    d->do_DefaultTool = old;
    d->do_Type = oldtype;
    d->do_CurrentX = ox;
    d->do_CurrentY = oy;
    IIc->FreeDiskObject(d);
    return ok ? 0 : 75;
}

/* --- ARexx --------------------------------------------------------------------------------- */

static struct MsgPort *rexx_port;
static char rexx_name[64];
static int32 rexx_rc;

static void rexx_close(void)
{
    if (!rexx_port) return;
    IExec->Forbid();
    IExec->RemPort(rexx_port);
    struct Message *m;
    while ((m = IExec->GetMsg(rexx_port))) {
        struct RexxMsg *rm = (struct RexxMsg *)m;
        rm->rm_Result1 = 20;
        rm->rm_Result2 = 0;
        IExec->ReplyMsg(m);
    }
    IExec->Permit();
    rexx_port->mp_Node.ln_Name = NULL;
    IExec->FreeSysObject(ASOT_PORT, rexx_port);
    rexx_port = NULL;
    rexx_name[0] = 0;
}

/* DoEvents in a program without forms handles the ARexx port and Workbench messages too */
static bb_int app_doevents(void)
{
    bb_forms_doevents();
    return 0;
}

static int rexx_open(const char *name)
{
    bb_set_doevents(app_doevents);
    rexx_close();
    if (!name || !*name) return 0;
    char want[56], buf[64];
    snprintf(want, sizeof want, "%s", name);
    for (char *p = want; *p; p++)
        if (*p >= 'a' && *p <= 'z') *p -= 32;        /* ARexx port names are upper case */
    snprintf(buf, sizeof buf, "%s", want);
    /* a private port made public by hand: its name is our static rexx_name, and closing it
       is RemPort + drain + FreeSysObject */
    rexx_port = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    if (!rexx_port) return 7;
    IExec->Forbid();
    for (int i = 1; IExec->FindPort(buf) && i < 100; i++) snprintf(buf, sizeof buf, "%s.%d", want, i);
    snprintf(rexx_name, sizeof rexx_name, "%s", buf);
    rexx_port->mp_Node.ln_Name = rexx_name;
    rexx_port->mp_Node.ln_Pri = 0;
    IExec->AddPort(rexx_port);
    IExec->Permit();
    return 0;
}

/* a command for the program: ARexx_Command(Cmd, Args, Result) */
static void rexx_command(struct RexxMsg *rm)
{
    const char *line = rm->rm_Args[0] ? (const char *)rm->rm_Args[0] : "";
    while (*line == ' ' || *line == '\t') line++;
    const char *sp = line;
    while (*sp && *sp != ' ' && *sp != '\t') sp++;
    char *cmd = malloc(sp - line + 1);
    memcpy(cmd, line, sp - line);
    cmd[sp - line] = 0;
    while (*sp == ' ' || *sp == '\t') sp++;
    bb_str *result = NULL;
    bb_value v[3] = { bb_v_str(bb_str_from_c(cmd)), bb_v_str(bb_str_from_c(sp)), bb_v_ref(BB_STRING, &result) };
    rexx_rc = 0;
    DBG("ARexx_Command %s / %s\n", cmd, sp);
    int had = bb_app_event("ARexx_Command", 3, v);
    DBG("handler %d result %s\n", had, result ? bb_str_ptr(result) : "-");
    bb_v_release(&v[0]);
    bb_v_release(&v[1]);
    rm->rm_Result1 = had ? rexx_rc : 30;      /* no handler: "unknown command" */
    rm->rm_Result2 = 0;
    if (had && !rexx_rc && (rm->rm_Action & RXFF_RESULT) && result && rexx())
        rm->rm_Result2 = (int32)IRx->CreateArgstring(bb_str_ptr(result), strlen(bb_str_ptr(result)));
    bb_str_release(result);
    free(cmd);
}

static void rexx_messages(void)
{
    struct RexxMsg *rm;
    DBG("rexx signal\n");
    while (rexx_port && (rm = (struct RexxMsg *)IExec->GetMsg(rexx_port))) {
        DBG("rexx msg action %lx arg0 %s\n", (unsigned long)rm->rm_Action, rm->rm_Args[0] ? (char *)rm->rm_Args[0] : "-");
        if (rm->rm_Node.mn_Node.ln_Type == NT_REPLYMSG) continue;
        if ((rm->rm_Action & RXCODEMASK) == RXCOMM) rexx_command(rm);
        else {
            rm->rm_Result1 = 20;
            rm->rm_Result2 = 0;
        }
        DBG("rexx reply rc %ld\n", (long)rm->rm_Result1);
        IExec->ReplyMsg(&rm->rm_Node);
    }
}

/* App.SendARexx(port, command): RESULT, RC in App.ARexxRC */
static int send_arexx(const char *portname, const char *command, bb_fval *ret)
{
    if (!rexx()) return 5;
    if (rexx_port && !strcasecmp(portname, rexx_name)) {
        /* our own port: no message (it would wait for itself) */
        bb_str *result = NULL;
        const char *sp = command;
        while (*sp && *sp != ' ') sp++;
        char *cmd = malloc(sp - command + 1);
        memcpy(cmd, command, sp - command);
        cmd[sp - command] = 0;
        while (*sp == ' ') sp++;
        bb_value v[3] = { bb_v_str(bb_str_from_c(cmd)), bb_v_str(bb_str_from_c(sp)), bb_v_ref(BB_STRING, &result) };
        rexx_rc = 0;
        if (!bb_app_event("ARexx_Command", 3, v)) rexx_rc = 30;
        bb_v_release(&v[0]);
        bb_v_release(&v[1]);
        free(cmd);
        rs(ret, result ? bb_str_ptr(result) : "");
        bb_str_release(result);
        return 0;
    }
    struct MsgPort *reply = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    if (!reply) return 7;
    struct RexxMsg *rm = IRx->CreateRexxMsg(reply, NULL, NULL);
    int err = 0;
    if (!rm) err = 7;
    else {
        rm->rm_Args[0] = (STRPTR)IRx->CreateArgstring(command, strlen(command));
        rm->rm_Action = RXCOMM | RXFF_RESULT;
        IExec->Forbid();
        struct MsgPort *dest = IExec->FindPort(portname);
        if (dest) IExec->PutMsg(dest, &rm->rm_Node);
        IExec->Permit();
        if (!dest) err = 5;
        else {
            IExec->WaitPort(reply);
            IExec->GetMsg(reply);
            rexx_rc = rm->rm_Result1;
            if (!rm->rm_Result1 && rm->rm_Result2) {
                rs(ret, (const char *)rm->rm_Result2);
                IRx->DeleteArgstring((STRPTR)rm->rm_Result2);
            } else
                rs(ret, "");
        }
        IRx->DeleteArgstring((STRPTR)rm->rm_Args[0]);
        IRx->DeleteRexxMsg(rm);
    }
    IExec->FreeSysObject(ASOT_PORT, reply);
    return err;
}

static int run_arexx(const char *script)
{
    char cmd[1100];
    snprintf(cmd, sizeof cmd, "RX \"%s\"", script);
    BPTR in = IDOS->Open("NIL:", MODE_OLDFILE), out = IDOS->Open("NIL:", MODE_NEWFILE);
    int32 r = IDOS->SystemTags(cmd, SYS_Asynch, TRUE, SYS_Input, in, SYS_Output, out, TAG_DONE);
    if (r == -1) {
        IDOS->Close(in);
        IDOS->Close(out);
        return 5;
    }
    return 0;
}

/* --- locale ------------------------------------------------------------------------------- */

static struct Catalog *catalog;

static int open_catalog(const char *name, const char *builtin)
{
    if (!loc()) return 0;
    if (catalog) ILoc->CloseCatalog(catalog);
    catalog = ILoc->OpenCatalog(NULL, name, builtin && *builtin ? OC_BuiltInLanguage : TAG_IGNORE, (uint32)builtin, TAG_DONE);
    return 0;
}

const char *bbf_app_str(int32 id, const char *def)
{
    if (catalog && ILoc) return (const char *)ILoc->GetCatalogStr(catalog, id, def);
    return def;
}

/* "$12:Open..." in a .afg value: the catalog's string 12, else "Open..." */
static void localize_node(afg_node *n, void *ud)
{
    (void)ud;
    for (int i = 0; i < n->nprops; i++) {
        char *v = n->props[i].value;
        if (v[0] != '$' || v[1] < '0' || v[1] > '9') continue;
        char *colon = strchr(v, ':');
        if (!colon) continue;
        int32 id = atol(v + 1);
        const char *s = bbf_app_str(id, colon + 1);
        n->props[i].value = xstrdup(s);
        free(v);
    }
}

void bbf_localize(afg_node *root) { afg_walk(root, localize_node, NULL); }

/* --- AmigaGuide --------------------------------------------------------------------------- */

static APTR guide_handle;
static char *help_file;

static void guide_close(void)
{
    if (guide_handle && IAG) IAG->CloseAmigaGuide(guide_handle);
    guide_handle = NULL;
}

static int show_help(const char *file, const char *node)
{
    if (!guide()) return 5;
    guide_close();
    struct NewAmigaGuide nag;
    memset(&nag, 0, sizeof nag);
    nag.nag_Name = (STRPTR)file;
    nag.nag_Node = node && *node ? (STRPTR)node : NULL;
    guide_handle = IAG->OpenAmigaGuideAsyncA(&nag, NULL);
    return guide_handle ? 0 : 53;
}

static void guide_messages(void)
{
    struct AmigaGuideMsg *m;
    if (!guide_handle) return;
    while ((m = IAG->GetAmigaGuideMsg(guide_handle))) {
        int quit = m->agm_Type == ShutdownMsgID;
        IAG->ReplyAmigaGuideMsg(m);
        if (quit) {
            guide_close();
            break;
        }
    }
}

int bbf_app_help_key(bb_form *f)
{
    (void)f;
    if (!help_file) return 0;
    show_help(help_file, "main");
    return 1;
}

/* --- clipboard pictures (datatypes: IFF ILBM on clipboard unit 0) -------------------------- */

/* Clipboard.SetPicture: a 24-bit IFF ILBM written with iffparse to clipboard unit 0 (what
   every OS4 picture program and the picture datatype read) */
static int clip_set_picture(bb_obj *canvas, int32 image)
{
    const uint32_t *px;
    int32_t w, h;
    if (!canvas) return 13;
    if (image > 0) px = bb_canvas_image_pixels(canvas, image, &w, &h);
    else px = bb_canvas_pixels(canvas, &w, &h);       /* the drawing target */
    if (!px) return image > 0 ? 5 : 13;
    struct Library *lib = IExec->OpenLibrary("iffparse.library", 39);
    struct IFFParseIFace *iff = lib ? (void *)IExec->GetInterface(lib, "main", 1, NULL) : NULL;
    if (!iff) {
        if (lib) IExec->CloseLibrary(lib);
        return 5;
    }
    int err = 7;
    struct IFFHandle *h_ = iff->AllocIFF();
    struct ClipboardHandle *ch = h_ ? iff->OpenClipboard(PRIMARY_CLIP) : NULL;
    int rowbytes = ((w + 15) / 16) * 2;
    uint8 *row = malloc(rowbytes);
    if (h_ && ch && row) {
        h_->iff_Stream = (uint32)ch;
        iff->InitIFFasClip(h_);
        if (!iff->OpenIFF(h_, IFFF_WRITE)) {
            struct BitMapHeader bmh;
            memset(&bmh, 0, sizeof bmh);
            bmh.bmh_Width = w;
            bmh.bmh_Height = h;
            bmh.bmh_Depth = 24;
            bmh.bmh_XAspect = 1;
            bmh.bmh_YAspect = 1;
            bmh.bmh_PageWidth = w;
            bmh.bmh_PageHeight = h;
            if (!iff->PushChunk(h_, ID_ILBM, ID_FORM, IFFSIZE_UNKNOWN) &&
                !iff->PushChunk(h_, ID_ILBM, ID_BMHD, sizeof bmh) && iff->WriteChunkBytes(h_, &bmh, sizeof bmh) == sizeof bmh &&
                !iff->PopChunk(h_) && !iff->PushChunk(h_, ID_ILBM, ID_BODY, IFFSIZE_UNKNOWN)) {
                err = 0;
                for (int32 y = 0; y < h && !err; y++)
                    for (int plane = 0; plane < 24 && !err; plane++) {
                        /* planes 0-7: red bits 0-7, 8-15 green, 16-23 blue */
                        int shift = plane < 8 ? 16 + plane : plane < 16 ? plane : plane - 16;
                        memset(row, 0, rowbytes);
                        for (int32 x = 0; x < w; x++)
                            if ((px[y * w + x] >> shift) & 1) row[x >> 3] |= 0x80 >> (x & 7);
                        if (iff->WriteChunkBytes(h_, row, rowbytes) != rowbytes) err = 5;
                    }
                iff->PopChunk(h_);          /* BODY */
                iff->PopChunk(h_);          /* FORM */
            } else
                err = 5;
            iff->CloseIFF(h_);
        }
    }
    free(row);
    if (ch) iff->CloseClipboard(ch);
    if (h_) iff->FreeIFF(h_);
    IExec->DropInterface((struct Interface *)iff);
    IExec->CloseLibrary(lib);
    return err;
}

/* the clipboard's picture as pixels (malloc'd), 0 if there is none */
static uint32_t *clip_read(int32 *pw, int32 *ph)
{
    if (!dt()) return NULL;
    Object *o = IDT->NewDTObject((APTR)0, DTA_SourceType, DTST_CLIPBOARD, DTA_GroupID, GID_PICTURE, PDTA_DestMode,
                                 PMODE_V43, PDTA_Remap, FALSE, TAG_DONE);
    if (!o) return NULL;
    struct BitMapHeader *bmh = NULL;
    uint32_t *px = NULL;
    if (IDT->GetDTAttrs(o, PDTA_BitMapHeader, (uint32)&bmh, TAG_DONE) && bmh && bmh->bmh_Width > 0) {
        int32 w = bmh->bmh_Width, h = bmh->bmh_Height;
        px = malloc((size_t)w * h * 4);
        if (px) {
            struct pdtBlitPixelArray bpa;
            memset(&bpa, 0, sizeof bpa);
            bpa.MethodID = PDTM_READPIXELARRAY;
            bpa.pbpa_PixelData = px;
            bpa.pbpa_PixelFormat = PBPAFMT_ARGB;
            bpa.pbpa_PixelArrayMod = w * 4;
            bpa.pbpa_Width = w;
            bpa.pbpa_Height = h;
            if (IIntuition->IDoMethodA(o, (Msg)&bpa)) {
                *pw = w;
                *ph = h;
                for (int32 i = 0; i < w * h; i++) px[i] |= 0xFF000000u;
            } else {
                free(px);
                px = NULL;
            }
        }
    }
    IDT->DisposeDTObject(o);
    return px;
}

/* Clipboard.GetImage(canvas): the picture as a new image of the canvas, its id (0 = none) */
static int clip_get_image(bb_obj *canvas, bb_fval *ret)
{
    int32 w, h;
    if (!canvas || !bb_is_canvas(canvas)) return 13;
    uint32_t *px = clip_read(&w, &h);
    return ri(ret, px ? bb_canvas_new_image(canvas, w, h, px) : 0);
}

static int clip_get_picture(bb_obj *canvas, bb_fval *ret)
{
    if (!canvas || !bb_is_canvas(canvas)) return 13;
    if (!dt()) return 5;
    Object *o = IDT->NewDTObject((APTR)0, DTA_SourceType, DTST_CLIPBOARD, DTA_GroupID, GID_PICTURE, PDTA_DestMode,
                                 PMODE_V43, PDTA_Remap, FALSE, TAG_DONE);
    if (!o) return ri(ret, 0);
    struct BitMapHeader *bmh = NULL;
    int ok = 0;
    if (IDT->GetDTAttrs(o, PDTA_BitMapHeader, (uint32)&bmh, TAG_DONE) && bmh && bmh->bmh_Width > 0) {
        int32 w = bmh->bmh_Width, h = bmh->bmh_Height;
        uint32_t *px = malloc((size_t)w * h * 4);
        if (px) {
            struct pdtBlitPixelArray bpa;
            memset(&bpa, 0, sizeof bpa);
            bpa.MethodID = PDTM_READPIXELARRAY;
            bpa.pbpa_PixelData = px;
            bpa.pbpa_PixelFormat = PBPAFMT_ARGB;
            bpa.pbpa_PixelArrayMod = w * 4;
            bpa.pbpa_Width = w;
            bpa.pbpa_Height = h;
            if (IIntuition->IDoMethodA(o, (Msg)&bpa)) ok = bb_canvas_put_picture(canvas, px, w, h);
            free(px);
        }
    }
    IDT->DisposeDTObject(o);
    return ri(ret, vb_bool(ok));
}

static int clip_has_picture(bb_fval *ret)
{
    if (!dt()) return ri(ret, 0);
    Object *o = IDT->NewDTObject((APTR)0, DTA_SourceType, DTST_CLIPBOARD, DTA_GroupID, GID_PICTURE, TAG_DONE);
    if (o) IDT->DisposeDTObject(o);
    return ri(ret, vb_bool(o != NULL));
}

/* --- the platform members ----------------------------------------------------------------- */

#define IS(a) (!strcasecmp(prop, a))

int bb_app_plat_get(const char *prop, int index, bb_fval *out)
{
    if (IS("FromWorkbench")) return ri(out, vb_bool(bb_sys_wbstartup() != NULL));
    if (IS("ToolTypeCount")) return ri(out, tooltype_count());
    if (IS("ToolTypes")) {
        struct DiskObject *d = program_icon();
        if (index < 0 || index >= tooltype_count()) return 381;
        return rs(out, (const char *)d->do_ToolTypes[index]);
    }
    if (IS("ArgCount")) return ri(out, arg_count());
    if (IS("Arg")) return arg(index, out);
    if (IS("DropCount")) return ri(out, ndrops);
    if (IS("DropFile")) {
        if (index < 0 || index >= ndrops) return 381;
        return rs(out, drops[index]);
    }
    if (IS("ARexxPort") || IS("ARexxPortName")) return rs(out, rexx_name);
    if (IS("ARexxRC")) return ri(out, rexx_rc);
    if (IS("HelpFile")) return rs(out, help_file);
    if (IS("Language")) {
        if (catalog && catalog->cat_Language) return rs(out, (const char *)catalog->cat_Language);
        struct Locale *l = loc() ? ILoc->OpenLocale(NULL) : NULL;
        rs(out, l && l->loc_PrefLanguages[0] ? (const char *)l->loc_PrefLanguages[0] : "english");
        if (l) ILoc->CloseLocale(l);
        return 0;
    }
    return 438;
}

int bb_app_plat_set(const char *prop, int index, const bb_fval *v)
{
    char buf[16];
    (void)index;
    if (IS("ARexxPort")) return rexx_open(vstr(v, buf));
    if (IS("ARexxRC")) { rexx_rc = vint(v); return 0; }
    if (IS("HelpFile")) {
        free(help_file);
        help_file = *vstr(v, buf) ? xstrdup(vstr(v, buf)) : NULL;
        return 0;
    }
    return 438;
}

#undef IS
#define IS(a) (!strcasecmp(method, a))

static const char *argstr(int argc, const bb_fval *argv, int i, char *buf)
{
    return i < argc && argv[i].type != BB_FV_NONE ? vstr(&argv[i], buf) : "";
}

int bb_app_plat_call(const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    char b0[16], b1[16], b2[16];
    if (IS("ToolType")) {
        if (argc < 1) return 450;
        return tooltype(argstr(argc, argv, 0, b0), argstr(argc, argv, 1, b1), ret);
    }
    if (IS("ToolTypes")) {
        bb_fval tmp;
        int e = bb_app_plat_get("ToolTypes", argc ? vint(&argv[0]) : -1, &tmp);
        *ret = tmp;
        return e;
    }
    if (IS("Arg") || IS("DropFile")) {
        if (argc < 1) return 450;
        return bb_app_plat_get(method, vint(&argv[0]), ret);
    }
    if (IS("ShowAppIcon")) {
        if (argc < 1) return 450;
        return show_appicon(argstr(argc, argv, 0, b0), argstr(argc, argv, 1, b1));
    }
    if (IS("HideAppIcon")) { hide_appicon(); return 0; }
    if (IS("AddAppMenuItem")) {
        if (argc < 1) return 450;
        return add_menuitem(argstr(argc, argv, 0, b0), ret);
    }
    if (IS("SaveIcon")) {
        if (argc < 1) return 450;
        return save_icon(argstr(argc, argv, 0, b0), argstr(argc, argv, 1, b1), argstr(argc, argv, 2, b2));
    }
    if (IS("SendARexx")) {
        if (argc < 2) return 450;
        return send_arexx(argstr(argc, argv, 0, b0), argstr(argc, argv, 1, b1), ret);
    }
    if (IS("RunARexx")) {
        if (argc < 1) return 450;
        return run_arexx(argstr(argc, argv, 0, b0));
    }
    if (IS("OpenCatalog")) {
        if (argc < 1) return 450;
        open_catalog(argstr(argc, argv, 0, b0), argstr(argc, argv, 1, b1));
        return ri(ret, vb_bool(catalog != NULL));
    }
    if (IS("Str")) {
        if (argc < 1) return 450;
        return rs(ret, bbf_app_str(vint(&argv[0]), argstr(argc, argv, 1, b1)));
    }
    if (IS("ShowHelp")) {
        if (argc < 1) return 450;
        return show_help(argstr(argc, argv, 0, b0), argstr(argc, argv, 1, b1));
    }
    return 438;
}

int bb_clip_plat_call(const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    if (IS("SetPicture")) {      /* SetPicture canvas [, imageId]: 0 / none = what it draws on */
        if (argc < 1 || argv[0].type != BB_FV_OBJ) return 13;
        return clip_set_picture(argv[0].o, argc > 1 && argv[1].type != BB_FV_NONE ? vint(&argv[1]) : 0);
    }
    if (IS("GetImage")) {
        if (argc < 1 || argv[0].type != BB_FV_OBJ) return 13;
        return clip_get_image(argv[0].o, ret);
    }
    if (IS("GetPicture")) {
        if (argc < 1 || argv[0].type != BB_FV_OBJ) return 13;
        return clip_get_picture(argv[0].o, ret);
    }
    if (IS("HasPicture")) return clip_has_picture(ret);
    return 438;
}

/* --- the event loop's part ------------------------------------------------------------------ */

uint32 bbf_app_sigmask(void)
{
    uint32 m = 0;
    if (app_port) m |= 1u << app_port->mp_SigBit;
    if (rexx_port) m |= 1u << rexx_port->mp_SigBit;
    if (guide_handle && IAG) m |= IAG->AmigaGuideSignal(guide_handle);
    return m;
}

void bbf_app_signals(uint32 got)
{
    if (app_port && (got & (1u << app_port->mp_SigBit))) app_messages();
    if (rexx_port && (got & (1u << rexx_port->mp_SigBit))) rexx_messages();
    if (guide_handle && IAG && (got & IAG->AmigaGuideSignal(guide_handle))) guide_messages();
}

void bbf_print_cleanup(void);

void bbf_app_cleanup(void)
{
    bbf_print_cleanup();
    rexx_close();
    guide_close();
    hide_appicon();
    for (int i = 0; i < nmenuitems; i++) {
        if (menuitems[i] && IWB) IWB->RemoveAppMenuItem(menuitems[i]);
        free(menutexts[i]);
    }
    nmenuitems = 0;
    if (app_port) {
        struct Message *m;
        while ((m = IExec->GetMsg(app_port))) IExec->ReplyMsg(m);
        IExec->FreeSysObject(ASOT_PORT, app_port);
        app_port = NULL;
    }
    for (int i = 0; i < ndrops; i++) free(drops[i]);
    free(drops);
    drops = NULL;
    ndrops = 0;
    if (catalog && ILoc) ILoc->CloseCatalog(catalog);
    catalog = NULL;
    if (prog_icon && IIc) IIc->FreeDiskObject(prog_icon);
    prog_icon = NULL;
    icon_tried = 0;
    free(help_file);
    help_file = NULL;
    free(hold);
    hold = NULL;
#define DROP(i, l) do { if (i) IExec->DropInterface((struct Interface *)i); i = NULL; if (l) IExec->CloseLibrary(l); l = NULL; } while (0)
    DROP(IWB, WbLib);
    DROP(IIc, IconLib);
    DROP(IRx, RexxLib);
    DROP(ILoc, LocaleLib);
    DROP(IAG, GuideLib);
    DROP(IDT, DtLib);
}
