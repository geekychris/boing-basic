/* The Printer object (docs/ui.md section 8) on printer.device: Printer.Print text (through the
 * printer driver's translation), NewPage, EndDoc, PaintPicture canvas (a graphic dump fed by
 * DRPA_SourceHook from the canvas's pixels), ShowSetup (the printer preferences requester). */
#include "forms_int.h"
#include "../bb_app.h"
#include "../canvas.h"
#include <devices/printer.h>
#include <stddef.h>

static struct MsgPort *pport;
static union printerIO {
    struct IOStdReq ios;
    struct IODRPTagsReq drp;
    struct IOPrtPrefsReq prefs;
} *preq;
static int popen_, pages, perr;

static int prn_open(void)
{
    if (popen_) return 0;
    pport = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    if (!pport) return 7;
    preq = IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Size, sizeof *preq, ASOIOR_ReplyPort, pport, TAG_DONE);
    if (!preq || IExec->OpenDevice("printer.device", 0, (struct IORequest *)preq, 0)) {
        if (preq) IExec->FreeSysObject(ASOT_IOREQUEST, preq);
        IExec->FreeSysObject(ASOT_PORT, pport);
        preq = NULL;
        pport = NULL;
        return 482;                     /* VB: "Printer error" */
    }
    popen_ = 1;
    pages = 1;
    return 0;
}

static void prn_close(void)
{
    if (!popen_) return;
    IExec->CloseDevice((struct IORequest *)preq);
    IExec->FreeSysObject(ASOT_IOREQUEST, preq);
    IExec->FreeSysObject(ASOT_PORT, pport);
    preq = NULL;
    pport = NULL;
    popen_ = 0;
}

static int prn_write(const char *s, int len)
{
    int e = prn_open();
    if (e) return e;
    preq->ios.io_Command = CMD_WRITE;
    preq->ios.io_Data = (APTR)s;
    preq->ios.io_Length = len;
    perr = IExec->DoIO((struct IORequest *)preq);
    return perr ? 482 : 0;
}

struct pic {
    const uint32_t *px;
    int32_t w, h;
};

static uint32 source_hook(struct Hook *h, APTR dummy, struct DRPSourceMsg *m)
{
    (void)dummy;
    struct pic *p = h->h_Data;
    for (int32 y = 0; y < m->height; y++)
        for (int32 x = 0; x < m->width; x++) {
            int32 sx = m->x + x, sy = m->y + y;
            uint32 c = sx < p->w && sy < p->h ? p->px[sy * p->w + sx] & 0xFFFFFF : 0xFFFFFF;
            m->buf[y * m->width + x] = c;
        }
    return 0;
}

static int paint_picture(bb_obj *canvas, int argc, const bb_fval *argv)
{
    struct pic p;
    if (!canvas || !bb_canvas_pixels(canvas, &p.px, &p.w, &p.h)) return 13;
    int e = prn_open();
    if (e) return e;
    struct Hook hook = { { 0 } };
    hook.h_Entry = (HOOKFUNC)source_hook;
    hook.h_Data = &p;
    struct TagItem tags[] = { { DRPA_SourceHook, (uint32)&hook }, { DRPA_AspectX, 1 }, { DRPA_AspectY, 1 }, { TAG_DONE, 0 } };
    memset(&preq->drp.io_RastPort, 0, sizeof preq->drp - offsetof(struct IODRPTagsReq, io_RastPort));
    preq->drp.io_Command = PRD_DUMPRPORTTAGS;
    preq->drp.io_SrcX = argc > 1 ? vint(&argv[1]) : 0;
    preq->drp.io_SrcY = argc > 2 ? vint(&argv[2]) : 0;
    preq->drp.io_SrcWidth = argc > 3 && argv[3].type != BB_FV_NONE ? vint(&argv[3]) : p.w;
    preq->drp.io_SrcHeight = argc > 4 && argv[4].type != BB_FV_NONE ? vint(&argv[4]) : p.h;
    preq->drp.io_Special = SPECIAL_FULLCOLS | SPECIAL_ASPECT | SPECIAL_NOFORMFEED;
    preq->drp.io_TagList = tags;
    perr = IExec->DoIO((struct IORequest *)preq);
    return perr ? 482 : 0;
}

static int show_setup(void)
{
    int e = prn_open();
    if (e) return e;
    struct Window *w = bbf_front_window();
    struct TagItem tags[] = { { w ? PPRA_Window : TAG_IGNORE, (uint32)w }, { TAG_DONE, 0 } };
    preq->prefs.io_Command = PRD_EDITPREFS;
    preq->prefs.io_TagList = tags;
    IExec->DoIO((struct IORequest *)preq);
    return 0;
}

int bb_prn_plat_get(const char *prop, int index, bb_fval *out)
{
    (void)index;
    if (!strcasecmp(prop, "Page")) return ret_int(out, pages);
    if (!strcasecmp(prop, "Error")) return ret_int(out, perr);
    return 438;
}

int bb_prn_plat_set(const char *prop, int index, const bb_fval *v)
{
    (void)prop; (void)index; (void)v;
    return 438;
}

int bb_prn_plat_call(const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    char buf[16];
    (void)ret;
    if (!strcasecmp(method, "Print")) {
        /* Printer.Print a [, b ...]: the texts, then a new line */
        for (int i = 0; i < argc; i++) {
            const char *s = argv[i].type == BB_FV_NONE ? "" : vstr(&argv[i], buf);
            int e = prn_write(s, strlen(s));
            if (e) return e;
        }
        return prn_write("\n", 1);
    }
    if (!strcasecmp(method, "Write")) {     /* no new line */
        for (int i = 0; i < argc; i++) {
            const char *s = argv[i].type == BB_FV_NONE ? "" : vstr(&argv[i], buf);
            int e = prn_write(s, strlen(s));
            if (e) return e;
        }
        return 0;
    }
    if (!strcasecmp(method, "NewPage")) {
        pages++;
        return prn_write("\f", 1);
    }
    if (!strcasecmp(method, "EndDoc")) {
        int e = popen_ ? prn_write("\f", 1) : 0;
        prn_close();
        return e;
    }
    if (!strcasecmp(method, "KillDoc")) {
        prn_close();
        return 0;
    }
    if (!strcasecmp(method, "PaintPicture")) {
        if (argc < 1 || argv[0].type != BB_FV_OBJ) return 13;
        return paint_picture(argv[0].o, argc, argv);
    }
    if (!strcasecmp(method, "ShowSetup")) return show_setup();
    return 438;
}

void bbf_print_cleanup(void) { prn_close(); }
