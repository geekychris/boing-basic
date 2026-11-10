/* The program as an AmigaOS 4 desktop citizen (docs/ui.md, "Notifications, Commodities, ReadArgs"):
 * application.library registration and Ringhio notifications (App.Notify), messages from the
 * system (App_Quit / App_Hide / App_Show), a Commodities broker with hotkeys (App.HotKey →
 * HotKey_Pressed(Name)) and an Exchange entry, and ReadArgs templates (App.ReadArgs, App.ArgValue). */
#include "forms_int.h"
#include "../boing.h"
#include "../bb_app.h"
#include "../bb_sys.h"
#include <libraries/application.h>
#include <libraries/commodities.h>
#include <proto/application.h>
#include <proto/commodities.h>
#include <dos/rdargs.h>
#include <ctype.h>

static struct Library *AppLib, *CxLib;
static struct ApplicationIFace *IApp;
static struct CommoditiesIFace *ICx;
static uint32 app_id;
static uint32 notify_result;              /* App.NotifyResult: application.library's last answer */
void bbf_app_enable_doevents(void);
void bbf_app_atexit(void);
static struct MsgPort *app_port;          /* application.library's port for us */

/* --- application.library ----------------------------------------------------------------- */

static int app_register(void)
{
    if (app_id) return 1;
    bbf_app_atexit();                       /* unregistered at exit even without forms */
    bbf_app_enable_doevents();              /* DoEvents handles the port in programs without forms */
    if (!IApp) {
        AppLib = IExec->OpenLibrary("application.library", 53);
        if (AppLib) IApp = (void *)IExec->GetInterface(AppLib, "application", 2, NULL);
        if (!IApp) return 0;
    }
    bb_str *t = bb_app_title();
    app_id = IApp->RegisterApplication(bb_str_ptr(t)[0] ? bb_str_ptr(t) : "BoingBASIC",
                                       REGAPP_AppNotifications, TRUE, REGAPP_NoIcon, TRUE,
                                       REGAPP_Description, (uint32)"A Boing BASIC program", TAG_DONE);
    bb_str_release(t);
    if (app_id) IApp->GetApplicationAttrs(app_id, APPATTR_Port, (uint32)&app_port, TAG_DONE);
    return app_id != 0;
}

/* App.Notify title, text [, imagefile]: a Ringhio notification; 0 or a VB error */
static int app_notify(const char *title, const char *text, const char *image)
{
    if (!app_register()) return 5;
    uint32 r;
    for (int tries = 0;; tries++) {
        r = notify_result = IApp->Notify(app_id, APPNOTIFY_Title, (uint32)title, APPNOTIFY_Text, (uint32)text,
                                         image && *image ? APPNOTIFY_ImageFile : TAG_IGNORE, (uint32)image,
                                         APPNOTIFY_PubScreenName, (uint32)"FRONT", TAG_DONE);
        /* right after RegisterApplication the notification server may not know us yet */
        if (r != APPNOTIFY_ERROR_APPNOTREGISTERED || tries >= 10) break;
        IDOS->Delay(10);
    }
    return r == APPNOTIFY_OK_MSGQUEUED || r == APPNOTIFY_OK_APPREGISTERED ? 0 : 5;
}

static void app_messages(void)
{
    struct ApplicationMsg *m;
    while (app_port && (m = (struct ApplicationMsg *)IExec->GetMsg(app_port))) {
        uint32 type = m->type;
        IExec->ReplyMsg(&m->msg);
        if (type == APPLIBMT_Quit) {
            if (!bb_app_event("App_Quit", 0, NULL)) bb_forms_end();
        } else if (type == APPLIBMT_Hide) bb_app_event("App_Hide", 0, NULL);
        else if (type == APPLIBMT_Unhide || type == APPLIBMT_ToFront) bb_app_event("App_Show", 0, NULL);
    }
}

/* --- Commodities ------------------------------------------------------------------------- */

static struct MsgPort *cx_port;
static CxObj *broker;
static char *hotnames[32];
static int nhot;

static int cx_broker(void)
{
    if (broker) return 1;
    bbf_app_atexit();                       /* the broker must go before the port does */
    bbf_app_enable_doevents();
    if (!ICx) {
        CxLib = IExec->OpenLibrary("commodities.library", 50);
        if (CxLib) ICx = (void *)IExec->GetInterface(CxLib, "main", 1, NULL);
        if (!ICx) return 0;
    }
    if (!cx_port) cx_port = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    if (!cx_port) return 0;
    static char name[64], title[80];
    bb_str *t = bb_app_title();
    snprintf(name, sizeof name, "%.60s", bb_str_ptr(t)[0] ? bb_str_ptr(t) : "BoingBASIC");
    snprintf(title, sizeof title, "%s", name);
    bb_str_release(t);
    struct NewBroker nb;
    memset(&nb, 0, sizeof nb);
    nb.nb_Version = NB_VERSION;
    nb.nb_Name = name;
    nb.nb_Title = title;
    nb.nb_Descr = "A Boing BASIC program";
    nb.nb_Unique = NBU_UNIQUE | NBU_NOTIFY;
    nb.nb_Flags = COF_SHOW_HIDE;
    nb.nb_Port = cx_port;
    int32 err = 0;
    broker = ICx->CxBroker(&nb, &err);
    if (!broker) return 0;
    ICx->ActivateCxObj(broker, 1);
    return 1;
}

/* App.HotKey name, "ctrl alt p": HotKey_Pressed(Name) when the keys are pressed anywhere */
static int add_hotkey(const char *name, const char *desc)
{
    if (nhot >= 32) return 7;
    if (!cx_broker()) return 5;
    CxObj *filter = ICx->CreateCxObj(CX_FILTER, (int32)desc, 0);
    if (!filter) return 5;
    ICx->AttachCxObj(filter, ICx->CreateCxObj(CX_SEND, (int32)cx_port, nhot + 1));
    ICx->AttachCxObj(filter, ICx->CreateCxObj(CX_TRANSLATE, 0, 0));    /* the keys don't go further */
    if (ICx->CxObjError(filter)) {
        ICx->DeleteCxObjAll(filter);
        return 380;                  /* a description commodities can't parse */
    }
    ICx->AttachCxObj(broker, filter);
    hotnames[nhot++] = xstrdup(name);
    return 0;
}

static void cx_messages(void)
{
    CxMsg *m;
    while (cx_port && (m = (CxMsg *)IExec->GetMsg(cx_port))) {
        uint32 type = ICx->CxMsgType(m);
        int32 id = ICx->CxMsgID(m);
        IExec->ReplyMsg((struct Message *)m);
        if (type == CXM_IEVENT && id >= 1 && id <= nhot) {
            bb_value v = bb_v_str(bb_str_from_c(hotnames[id - 1]));
            bb_app_event("HotKey_Pressed", 1, &v);
            bb_v_release(&v);
        } else if (type == CXM_COMMAND) {
            switch (id) {
            case CXCMD_KILL:
                if (!bb_app_event("App_Quit", 0, NULL)) bb_forms_end();
                break;
            case CXCMD_APPEAR: case CXCMD_UNIQUE: bb_app_event("App_Show", 0, NULL); break;
            case CXCMD_DISAPPEAR: bb_app_event("App_Hide", 0, NULL); break;
            case CXCMD_DISABLE: ICx->ActivateCxObj(broker, 0); break;
            case CXCMD_ENABLE: ICx->ActivateCxObj(broker, 1); break;
            }
        }
    }
}

/* --- ReadArgs ----------------------------------------------------------------------------- */

typedef struct rarg {
    char key[32];
    char type;            /* 'S' switch, 'N' number, 'M' multiple, ' ' string */
    char *value;          /* as text; multiple values joined by '\n' */
} rarg;
static rarg rargs[32];
static int nrargs;

static void clear_rargs(void)
{
    for (int i = 0; i < nrargs; i++) free(rargs[i].value);
    nrargs = 0;
}

/* App.ReadArgs(template): parses the program's arguments (the command line; from Workbench the
   tooltypes KEY=value); True if they fit the template. App.ArgValue(key) reads a value. */
static int read_args(const char *templ, bb_fval *ret)
{
    clear_rargs();
    /* the template's keys: "FILE/A,SIZE/N,QUIET/S,FILES/M" (aliases: "F=FILE") */
    const char *p = templ;
    while (*p && nrargs < 32) {
        const char *e = strchr(p, ',');
        size_t l = e ? (size_t)(e - p) : strlen(p);
        char item[64];
        snprintf(item, sizeof item, "%.*s", (int)(l < 63 ? l : 63), p);
        rarg *r = &rargs[nrargs++];
        char *slash = strchr(item, '/');
        r->type = ' ';
        if (slash) {
            for (char *q = slash; *q; q++)
                if (q[0] == '/' && strchr("SNMsnm", q[1])) r->type = (char)toupper((unsigned char)q[1]);
            *slash = 0;
        }
        char *eq = strrchr(item, '=');
        snprintf(r->key, sizeof r->key, "%s", eq ? eq + 1 : item);
        p = e ? e + 1 : p + l;
    }
    if (bb_sys_wbstartup() || (IDOS->Cli() == NULL)) {
        /* from Workbench: the tooltypes */
        for (int i = 0; i < nrargs; i++) {
            bb_fval v, d = { BB_FV_STR, 0, "", NULL };
            bb_fval a[2] = { { BB_FV_STR, 0, rargs[i].key, NULL }, d };
            if (bb_app_plat_call("ToolType", 2, a, &v) == 0 && v.s && *v.s) rargs[i].value = xstrdup(v.s);
        }
        return ret_int(ret, -1);
    }
    struct RDArgs *rda = IDOS->AllocDosObject(DOS_RDARGS, NULL);
    if (!rda) return 7;
    const char *cmd = bb_sys_command();
    char *src = malloc(strlen(cmd) + 2);
    sprintf(src, "%s\n", cmd);
    rda->RDA_Source.CS_Buffer = (STRPTR)src;
    rda->RDA_Source.CS_Length = strlen(src);
    rda->RDA_Source.CS_CurChr = 0;
    rda->RDA_Flags |= RDAF_NOPROMPT;
    int32 array[32];
    memset(array, 0, sizeof array);
    int ok = IDOS->ReadArgs(templ, array, rda) != NULL;
    if (ok)
        for (int i = 0; i < nrargs; i++) {
            if (!array[i]) continue;
            char buf[32];
            if (rargs[i].type == 'S') rargs[i].value = xstrdup("1");
            else if (rargs[i].type == 'N') {
                snprintf(buf, sizeof buf, "%ld", (long)*(int32 *)array[i]);
                rargs[i].value = xstrdup(buf);
            } else if (rargs[i].type == 'M') {
                size_t n = 1;
                char **v = (char **)array[i];
                for (int k = 0; v[k]; k++) n += strlen(v[k]) + 1;
                char *o = malloc(n);
                o[0] = 0;
                for (int k = 0; v[k]; k++) {
                    if (k) strcat(o, "\n");
                    strcat(o, v[k]);
                }
                rargs[i].value = o;
            } else
                rargs[i].value = xstrdup((char *)array[i]);
        }
    IDOS->FreeArgs(rda);
    IDOS->FreeDosObject(DOS_RDARGS, rda);
    free(src);
    return ret_int(ret, vb_bool(ok));
}

static const char *arg_value(const char *key)
{
    for (int i = 0; i < nrargs; i++)
        if (!strcasecmp(rargs[i].key, key)) return rargs[i].value ? rargs[i].value : "";
    return NULL;
}

/* --- the App members and the event loop ---------------------------------------------------- */

static char *hold;
int bbf_desk_call(const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    char b0[16], b1[16], b2[16];
#define ARG(i, b) (argc > (i) && argv[i].type != BB_FV_NONE ? vstr(&argv[i], b) : "")
    if (!strcasecmp(method, "Notify")) {
        if (argc < 2) return 450;
        return app_notify(ARG(0, b0), ARG(1, b1), ARG(2, b2));
    }
    if (!strcasecmp(method, "HotKey")) {
        if (argc < 2) return 450;
        return add_hotkey(ARG(0, b0), ARG(1, b1));
    }
    if (!strcasecmp(method, "ReadArgs")) {
        if (argc < 1) return 450;
        return read_args(ARG(0, b0), ret);
    }
    if (!strcasecmp(method, "ArgValue")) {
        if (argc < 1) return 450;
        const char *v = arg_value(ARG(0, b0));
        if (!v) return 5;                          /* not a key of the template */
        free(hold);
        hold = xstrdup(v);
        ret->type = BB_FV_STR;
        ret->s = hold;
        return 0;
    }
    if (!strcasecmp(method, "Register")) return ret_int(ret, vb_bool(app_register()));
    if (!strcasecmp(method, "NotifyResult")) return ret_int(ret, (int32)notify_result);
#undef ARG
    return 438;
}

uint32 bbf_desk_sigmask(void)
{
    uint32 m = 0;
    if (app_port) m |= 1u << app_port->mp_SigBit;
    if (cx_port) m |= 1u << cx_port->mp_SigBit;
    return m;
}

void bbf_desk_signals(uint32 got)
{
    if (app_port && (got & (1u << app_port->mp_SigBit))) app_messages();
    if (cx_port && (got & (1u << cx_port->mp_SigBit))) cx_messages();
}

void bbf_desk_cleanup(void)
{
    if (broker && ICx) ICx->DeleteCxObjAll(broker);
    broker = NULL;
    if (cx_port) {
        struct Message *m;
        while ((m = IExec->GetMsg(cx_port))) IExec->ReplyMsg(m);
        IExec->FreeSysObject(ASOT_PORT, cx_port);
        cx_port = NULL;
    }
    for (int i = 0; i < nhot; i++) free(hotnames[i]);
    nhot = 0;
    if (app_id && IApp) IApp->UnregisterApplication(app_id, TAG_DONE);
    app_id = 0;
    app_port = NULL;
    clear_rargs();
    free(hold);
    hold = NULL;
    if (ICx) IExec->DropInterface((struct Interface *)ICx);
    if (CxLib) IExec->CloseLibrary(CxLib);
    if (IApp) IExec->DropInterface((struct Interface *)IApp);
    if (AppLib) IExec->CloseLibrary(AppLib);
    ICx = NULL;
    CxLib = NULL;
    IApp = NULL;
    AppLib = NULL;
}
