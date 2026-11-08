/* Forms on AmigaOS 4 ReAction (see bb_forms.h and docs/forms-events.md).
 *
 * A form is built at run time from its .afg tree: one window.class object whose
 * WINDOW_Layout is the root layout.gadget, one BOOPSI object per designer object (as the C
 * that AmiForge's designer generates, GuiModel.cpp), gadget IDs 1..n. The event loop waits
 * on every open window, the timers' port and Ctrl-C, and calls the event handler for
 * `<control>_<Event>`. Classes are opened with IIntuition->OpenClass, so no class
 * interface globals are needed except the few classes with library functions (list nodes,
 * RethinkLayout). */
#include "../bb_forms.h"
#include "../afg.h"

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include <exec/exec.h>
#include <devices/timer.h>
#include <intuition/intuition.h>
#include <intuition/gadgetclass.h>
#include <intuition/icclass.h>
#include <devices/inputevent.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/intuition.h>
#include <proto/keymap.h>
#include <proto/listbrowser.h>
#include <proto/chooser.h>
#include <proto/layout.h>
#include <classes/window.h>
#include <classes/requester.h>
#include <gadgets/layout.h>
#include <gadgets/button.h>
#include <gadgets/string.h>
#include <gadgets/integer.h>
#include <gadgets/checkbox.h>
#include <gadgets/chooser.h>
#include <gadgets/radiobutton.h>
#include <gadgets/slider.h>
#include <gadgets/scroller.h>
#include <gadgets/listbrowser.h>
#include <gadgets/space.h>
#include <gadgets/fuelgauge.h>
#include <gadgets/getfile.h>
#include <gadgets/texteditor.h>
#include <images/label.h>
#include <images/bevel.h>

/* --- classes ---------------------------------------------------------------------------- */

enum { C_WINDOW, C_LAYOUT, C_BUTTON, C_STRING, C_INTEGER, C_CHECKBOX, C_CHOOSER, C_RADIO, C_SLIDER, C_SCROLLER,
       C_LISTBROWSER, C_LABEL, C_SPACE, C_FUELGAUGE, C_GETFILE, C_TEXTEDITOR, C_REQUESTER, C_NUM };
static const char *const class_names[C_NUM] = {
    "window.class", "gadgets/layout.gadget", "gadgets/button.gadget", "gadgets/string.gadget",
    "gadgets/integer.gadget", "gadgets/checkbox.gadget", "gadgets/chooser.gadget",
    "gadgets/radiobutton.gadget", "gadgets/slider.gadget", "gadgets/scroller.gadget",
    "gadgets/listbrowser.gadget", "images/label.image", "gadgets/space.gadget", "gadgets/fuelgauge.gadget",
    "gadgets/getfile.gadget", "gadgets/texteditor.gadget", "requester.class",
};
static struct ClassLibrary *class_lib[C_NUM];
static Class *class_ptr[C_NUM];
static struct ListBrowserIFace *ILB;
static struct ChooserIFace *ICH;
static struct LayoutIFace *ILO;
static struct KeymapIFace *IKM;
static struct Library *KeymapLib;

static Class *cls(int c)
{
    if (!class_ptr[c]) {
        class_lib[c] = IIntuition->OpenClass(class_names[c], 0, &class_ptr[c]);
        if (class_lib[c]) {
            if (c == C_LISTBROWSER) ILB = (void *)IExec->GetInterface((struct Library *)class_lib[c], "main", 1, NULL);
            if (c == C_CHOOSER) ICH = (void *)IExec->GetInterface((struct Library *)class_lib[c], "main", 1, NULL);
            if (c == C_LAYOUT) ILO = (void *)IExec->GetInterface((struct Library *)class_lib[c], "main", 1, NULL);
        }
    }
    return class_ptr[c];
}

/* --- tag lists -------------------------------------------------------------------------- */

typedef struct {
    struct TagItem *t;
    int n, cap;
} tags;

static void tg(tags *t, Tag tag, uint32 data)
{
    if (t->n + 2 > t->cap) {
        t->cap = t->cap ? t->cap * 2 : 32;
        t->t = realloc(t->t, t->cap * sizeof *t->t);
    }
    t->t[t->n].ti_Tag = tag;
    t->t[t->n].ti_Data = data;
    t->n++;
    t->t[t->n].ti_Tag = TAG_DONE;
}

static Object *new_obj(int c, tags *t)
{
    tg(t, TAG_DONE, 0);
    Class *k = cls(c);
    Object *o = k ? IIntuition->NewObjectA(k, NULL, t->t) : NULL;
    free(t->t);
    t->t = NULL;
    t->n = t->cap = 0;
    return o;
}

/* --- objects ---------------------------------------------------------------------------- */

struct bb_ctl {
    bb_form *form;
    afg_node *node;          /* NULL for the form itself */
    afg_kind kind;
    const char *name;
    Object *obj;
    uint32 gid;
    struct List labels;      /* listbrowser / chooser nodes */
    char **items;            /* chooser / radio / list texts */
    int nitems, capitems;
    STRPTR *labelarray;      /* radio */
    int32 sel;               /* ListIndex */
    char *tagstr, *hint, *text, *extra;
    int visible;
    /* timer */
    struct TimeRequest *tio;
    int interval, enabled, pending;
};

struct bb_form {
    bb_form *next;
    afg_node *afg;
    char *file;
    bb_form_event_fn fn;
    bb_form_has_event_fn has;
    void *ud;
    Object *winobj, *root;
    struct Window *win;
    struct bb_ctl self;
    struct bb_ctl **ctls;
    int nctls;
    char *ret;               /* the last string returned */
    int loaded, unloading, enabled;
    int16 lastw, lasth;
};

static bb_form *forms;
static int ending, end_code;
static struct MsgPort *timer_port;
static struct TimeRequest *timer_master;

static char *xstrdup(const char *s)
{
    char *o = malloc(strlen(s) + 1);
    if (o) strcpy(o, s);
    return o;
}

static int fire(bb_form *f, const char *ctl, const char *event, int argc, int32_t *args)
{
    if (!f->fn || ending || !*ctl) return 0;
    if (f->has && !f->has(f->ud, f, ctl, event)) return 0;
    int r = f->fn(f->ud, f, ctl, event, argc, args);
    if (r) {
        ending = 1;
        end_code = r;
    }
    return r;
}

static int fire0(bb_ctl *c, const char *event) { return fire(c->form, c->name, event, 0, NULL); }

/* set a gadget attribute, refreshing it when the window is open */
static void set_attr(bb_ctl *c, Tag tag, uint32 v)
{
    struct TagItem t[2] = { { tag, v }, { TAG_DONE, 0 } };
    if (c->form->win && c->kind != AFG_WINDOW)
        IIntuition->SetGadgetAttrsA((struct Gadget *)c->obj, c->form->win, NULL, t);
    else
        IIntuition->SetAttrsA(c->obj, t);
}

static uint32 get_attr(bb_ctl *c, Tag tag)
{
    uint32 v = 0;
    IIntuition->GetAttr(tag, c->obj, &v);
    return v;
}

static void relayout(bb_form *f)
{
    if (f->win && f->winobj) IIntuition->IDoMethod(f->winobj, WM_RETHINK);
}

/* --- item lists ------------------------------------------------------------------------- */

static void items_insert(bb_ctl *c, int at, const char *s)
{
    if (c->nitems + 1 > c->capitems) {
        c->capitems = c->capitems ? c->capitems * 2 : 8;
        c->items = realloc(c->items, c->capitems * sizeof *c->items);
    }
    if (at < 0 || at > c->nitems) at = c->nitems;
    memmove(c->items + at + 1, c->items + at, (c->nitems - at) * sizeof *c->items);
    c->items[at] = xstrdup(s);
    c->nitems++;
}

static void items_remove(bb_ctl *c, int at)
{
    free(c->items[at]);
    memmove(c->items + at, c->items + at + 1, (c->nitems - at - 1) * sizeof *c->items);
    c->nitems--;
}

static void free_nodes(bb_ctl *c)
{
    struct Node *n;
    while ((n = IExec->RemHead(&c->labels))) {
        if (c->kind == AFG_LISTBROWSER && ILB) ILB->FreeListBrowserNode(n);
        else if (c->kind == AFG_CHOOSER && ICH) ICH->FreeChooserNode(n);
    }
}

/* rebuild the node list from items (with the list detached from the gadget) */
static void build_nodes(bb_ctl *c)
{
    free_nodes(c);
    for (int i = 0; i < c->nitems; i++) {
        struct Node *n = NULL;
        if (c->kind == AFG_LISTBROWSER && ILB)
            n = ILB->AllocListBrowserNode(1, LBNCA_CopyText, TRUE, LBNCA_Text, c->items[i], TAG_DONE);
        else if (c->kind == AFG_CHOOSER && ICH)
            n = ICH->AllocChooserNode(CNA_CopyText, TRUE, CNA_Text, c->items[i], TAG_DONE);
        if (n) IExec->AddTail(&c->labels, n);
    }
}

static void list_changed(bb_ctl *c)
{
    Tag lt = c->kind == AFG_LISTBROWSER ? LISTBROWSER_Labels : CHOOSER_Labels;
    set_attr(c, lt, ~0u);
    build_nodes(c);
    if (c->sel >= c->nitems) c->sel = c->nitems - 1;
    if (c->kind == AFG_CHOOSER && c->sel < 0 && c->nitems) c->sel = 0;
    struct TagItem t[3] = { { lt, (uint32)&c->labels },
                            { c->kind == AFG_LISTBROWSER ? LISTBROWSER_Selected : CHOOSER_Selected, (uint32)c->sel },
                            { TAG_DONE, 0 } };
    if (c->form->win) IIntuition->SetGadgetAttrsA((struct Gadget *)c->obj, c->form->win, NULL, t);
    else IIntuition->SetAttrsA(c->obj, t);
}

/* --- building --------------------------------------------------------------------------- */

static void gadget_tags(bb_ctl *c, tags *t)
{
    tg(t, GA_ID, c->gid);
    tg(t, GA_RelVerify, TRUE);
    if (afg_get_bool(c->node, "disabled")) tg(t, GA_Disabled, TRUE);
    if (afg_has(c->node, "hint")) {
        c->hint = xstrdup(afg_get(c->node, "hint"));
        tg(t, GA_HintInfo, (uint32)c->hint);
    }
}

static bb_ctl *ctl_for(bb_form *f, afg_node *n)
{
    for (int i = 0; i < f->nctls; i++)
        if (f->ctls[i]->node == n) return f->ctls[i];
    return NULL;
}

static Object *build(bb_form *f, afg_node *n)
{
    tags t = { 0 };
    bb_ctl *c = ctl_for(f, n);
    bb_ctl tmp;
    if (!c) {                    /* objects without an id still need their tags */
        memset(&tmp, 0, sizeof tmp);
        tmp.form = f;
        tmp.node = n;
        tmp.kind = n->kind;
        IExec->NewList(&tmp.labels);
        c = &tmp;
    }
    Object *o = NULL;
    switch (n->kind) {
    case AFG_VLAYOUT:
    case AFG_HLAYOUT: {
        Object **kids = calloc(n->nchildren + 1, sizeof *kids);
        for (int i = 0; i < n->nchildren; i++) {
            if (n->children[i]->kind == AFG_TIMER) continue;
            kids[i] = build(f, n->children[i]);
            if (!kids[i]) {
                for (int j = 0; j < i; j++)
                    if (kids[j]) IIntuition->DisposeObject(kids[j]);
                free(kids);
                return NULL;
            }
        }
        tg(&t, LAYOUT_Orientation, n->kind == AFG_VLAYOUT ? LAYOUT_ORIENT_VERT : LAYOUT_ORIENT_HORIZ);
        tg(&t, LAYOUT_SpaceOuter, n->parent && n->parent->kind == AFG_WINDOW);
        const char *frame = afg_get(n, "frame");
        if (afg_has(n, "title") && !strcmp(frame, "none")) frame = "group";
        if (!strcmp(frame, "group")) tg(&t, LAYOUT_BevelStyle, BVS_GROUP);
        else if (!strcmp(frame, "button")) tg(&t, LAYOUT_BevelStyle, BVS_BUTTON);
        else if (!strcmp(frame, "field")) tg(&t, LAYOUT_BevelStyle, BVS_FIELD);
        if (afg_has(n, "title")) tg(&t, LAYOUT_Label, (uint32)afg_get(n, "title"));
        if (afg_get_bool(n, "even")) tg(&t, LAYOUT_EvenSize, TRUE);
        for (int i = 0; i < n->nchildren; i++) {
            afg_node *ch = n->children[i];
            if (!kids[i]) continue;
            tg(&t, LAYOUT_AddChild, (uint32)kids[i]);
            if (afg_has(ch, "label")) {
                tags lt = { 0 };
                tg(&lt, LABEL_Text, (uint32)afg_get(ch, "label"));
                Object *l = new_obj(C_LABEL, &lt);
                if (l) tg(&t, CHILD_Label, (uint32)l);
            }
            if (afg_has(ch, "weight"))
                tg(&t, n->kind == AFG_HLAYOUT ? CHILD_WeightedWidth : CHILD_WeightedHeight, afg_get_int(ch, "weight"));
            if (afg_has(ch, "minwidth")) tg(&t, CHILD_MinWidth, afg_get_int(ch, "minwidth"));
            if (afg_has(ch, "minheight")) tg(&t, CHILD_MinHeight, afg_get_int(ch, "minheight"));
        }
        free(kids);
        o = new_obj(C_LAYOUT, &t);
        break;
    }
    case AFG_BUTTON:
        gadget_tags(c, &t);
        tg(&t, GA_Text, (uint32)afg_get(n, "text"));
        o = new_obj(C_BUTTON, &t);
        break;
    case AFG_STRING:
        gadget_tags(c, &t);
        tg(&t, GA_TabCycle, TRUE);
        tg(&t, STRINGA_MaxChars, afg_get_int(n, "maxchars"));
        tg(&t, STRINGA_TextVal, (uint32)afg_get(n, "text"));
        c->text = xstrdup(afg_get(n, "text"));
        o = new_obj(C_STRING, &t);
        break;
    case AFG_INTEGER:
        gadget_tags(c, &t);
        tg(&t, GA_TabCycle, TRUE);
        tg(&t, INTEGER_Minimum, afg_get_int(n, "min"));
        tg(&t, INTEGER_Maximum, afg_get_int(n, "max"));
        tg(&t, INTEGER_Number, afg_get_int(n, "value"));
        tg(&t, INTEGER_Arrows, TRUE);
        o = new_obj(C_INTEGER, &t);
        break;
    case AFG_CHECKBOX:
        gadget_tags(c, &t);
        tg(&t, GA_Text, (uint32)afg_get(n, "text"));
        tg(&t, CHECKBOX_Checked, afg_get_bool(n, "checked"));
        o = new_obj(C_CHECKBOX, &t);
        break;
    case AFG_CHOOSER:
        cls(C_CHOOSER);
        gadget_tags(c, &t);
        c->sel = c->nitems ? afg_get_int(n, "selected") : -1;
        if (c->sel >= c->nitems) c->sel = c->nitems - 1;
        build_nodes(c);
        tg(&t, CHOOSER_PopUp, TRUE);
        tg(&t, CHOOSER_Labels, (uint32)&c->labels);
        tg(&t, CHOOSER_Selected, c->sel);
        o = new_obj(C_CHOOSER, &t);
        break;
    case AFG_RADIO:
        gadget_tags(c, &t);
        c->labelarray = calloc(c->nitems + 1, sizeof *c->labelarray);
        for (int i = 0; i < c->nitems; i++) c->labelarray[i] = c->items[i];
        c->sel = afg_get_int(n, "selected");
        tg(&t, RADIOBUTTON_LabelArray, (uint32)c->labelarray);
        tg(&t, RADIOBUTTON_Selected, c->sel);
        o = new_obj(C_RADIO, &t);
        break;
    case AFG_SLIDER:
        gadget_tags(c, &t);
        tg(&t, SLIDER_Min, afg_get_int(n, "min"));
        tg(&t, SLIDER_Max, afg_get_int(n, "max"));
        tg(&t, SLIDER_Level, afg_get_int(n, "level"));
        tg(&t, SLIDER_Orientation, afg_get_bool(n, "vertical") ? SLIDER_VERTICAL : SLIDER_HORIZONTAL);
        o = new_obj(C_SLIDER, &t);
        break;
    case AFG_SCROLLER:
        gadget_tags(c, &t);
        tg(&t, SCROLLER_Total, afg_get_int(n, "total"));
        tg(&t, SCROLLER_Visible, afg_get_int(n, "visible"));
        tg(&t, SCROLLER_Top, afg_get_int(n, "top"));
        tg(&t, SCROLLER_Orientation, afg_get_bool(n, "vertical") ? SORIENT_VERT : SORIENT_HORIZ);
        o = new_obj(C_SCROLLER, &t);
        break;
    case AFG_LISTBROWSER:
        cls(C_LISTBROWSER);
        gadget_tags(c, &t);
        c->sel = -1;
        build_nodes(c);
        tg(&t, LISTBROWSER_Labels, (uint32)&c->labels);
        tg(&t, LISTBROWSER_ShowSelected, TRUE);
        tg(&t, LISTBROWSER_Selected, (uint32)-1);
        o = new_obj(C_LISTBROWSER, &t);
        break;
    case AFG_LABEL:
        /* a read-only, borderless button rather than label.image, so Caption can change */
        tg(&t, GA_ID, c->gid);
        tg(&t, GA_ReadOnly, TRUE);
        tg(&t, GA_Text, (uint32)afg_get(n, "text"));
        tg(&t, BUTTON_BevelStyle, BVS_NONE);
        tg(&t, BUTTON_Transparent, TRUE);
        tg(&t, BUTTON_Justification, BCJ_LEFT);
        o = new_obj(C_BUTTON, &t);
        break;
    case AFG_SPACE:
        o = new_obj(C_SPACE, &t);
        break;
    case AFG_FUELGAUGE:
        tg(&t, GA_ID, c->gid);
        tg(&t, FUELGAUGE_Min, afg_get_int(n, "min"));
        tg(&t, FUELGAUGE_Max, afg_get_int(n, "max"));
        tg(&t, FUELGAUGE_Level, afg_get_int(n, "level"));
        tg(&t, FUELGAUGE_Percent, TRUE);
        tg(&t, FUELGAUGE_Justification, FGJ_CENTER);
        o = new_obj(C_FUELGAUGE, &t);
        break;
    case AFG_GETFILE:
        gadget_tags(c, &t);
        tg(&t, GETFILE_TitleText, (uint32)afg_get(n, "title"));
        if (afg_has(n, "pattern")) {
            tg(&t, GETFILE_Pattern, (uint32)afg_get(n, "pattern"));
            tg(&t, GETFILE_DoPatterns, TRUE);
        }
        if (afg_get_bool(n, "save")) tg(&t, GETFILE_DoSaveMode, TRUE);
        o = new_obj(C_GETFILE, &t);
        break;
    case AFG_TEXTEDITOR:
        gadget_tags(c, &t);
        if (afg_has(n, "text")) tg(&t, GA_TEXTEDITOR_Contents, (uint32)afg_get(n, "text"));
        o = new_obj(C_TEXTEDITOR, &t);
        break;
    default:
        break;
    }
    if (c != &tmp) c->obj = o;
    return o;
}

static void collect(afg_node *n, void *ud)
{
    bb_form *f = ud;
    /* every object but the window and layouts (objects without an id get a control too, with
       the name "", so their items and strings have an owner; BASIC can't reach them) */
    if (n->kind == AFG_WINDOW || n->kind == AFG_VLAYOUT || n->kind == AFG_HLAYOUT) return;
    bb_ctl *c = calloc(1, sizeof *c);
    c->form = f;
    c->node = n;
    c->kind = n->kind;
    c->name = afg_get(n, "id");
    c->gid = f->nctls + 1;
    c->visible = 1;
    c->sel = -1;
    IExec->NewList(&c->labels);
    if (n->kind == AFG_CHOOSER || n->kind == AFG_RADIO || n->kind == AFG_LISTBROWSER) {
        char **v;
        int k = afg_split_items(afg_get(n, "items"), &v);
        for (int i = 0; i < k; i++) items_insert(c, -1, v[i]);
        afg_free_items(v, k);
    }
    if (n->kind == AFG_TIMER) {
        c->interval = afg_get_int(n, "interval");
        c->enabled = afg_get_bool(n, "enabled");
    }
    f->ctls = realloc(f->ctls, (f->nctls + 1) * sizeof *f->ctls);
    f->ctls[f->nctls++] = c;
}

/* --- timers ----------------------------------------------------------------------------- */

static int timers_init(void)
{
    if (timer_master) return 1;
    timer_port = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    if (!timer_port) return 0;
    timer_master = IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Size, sizeof(struct TimeRequest),
                                             ASOIOR_ReplyPort, timer_port, TAG_DONE);
    if (!timer_master || IExec->OpenDevice("timer.device", UNIT_MICROHZ, (struct IORequest *)timer_master, 0)) {
        if (timer_master) IExec->FreeSysObject(ASOT_IOREQUEST, timer_master);
        IExec->FreeSysObject(ASOT_PORT, timer_port);
        timer_master = NULL;
        timer_port = NULL;
        return 0;
    }
    return 1;
}

static void timer_send(bb_ctl *c)
{
    if (c->pending || !c->enabled || c->interval <= 0 || !c->form->loaded) return;
    if (!timers_init()) return;
    if (!c->tio)
        c->tio = IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Duplicate, timer_master, TAG_DONE);
    if (!c->tio) return;
    c->tio->Request.io_Command = TR_ADDREQUEST;
    c->tio->Time.Seconds = c->interval / 1000;
    c->tio->Time.Microseconds = (c->interval % 1000) * 1000;
    IExec->SendIO((struct IORequest *)c->tio);
    c->pending = 1;
}

static void timer_stop(bb_ctl *c)
{
    if (c->pending) {
        IExec->AbortIO((struct IORequest *)c->tio);
        IExec->WaitIO((struct IORequest *)c->tio);
        c->pending = 0;
    }
}

static void timers_handle(void)
{
    struct Message *m;
    /* collect the replies first: an event sub may start or stop timers */
    while ((m = IExec->GetMsg(timer_port))) {
        for (bb_form *f = forms; f; f = f->next)
            for (int i = 0; i < f->nctls; i++) {
                bb_ctl *c = f->ctls[i];
                if (c->tio && (struct Message *)c->tio == m) c->pending = 2;   /* fired */
            }
    }
    for (bb_form *f = forms; f && !ending; f = f->next)
        for (int i = 0; i < f->nctls && !ending; i++) {
            bb_ctl *c = f->ctls[i];
            if (c->kind != AFG_TIMER || c->pending != 2) continue;
            c->pending = 0;
            if (c->enabled && f->loaded && !f->unloading) {
                fire0(c, "Timer");
                timer_send(c);
            }
        }
}

/* --- forms ------------------------------------------------------------------------------ */

static void form_free(bb_form *f)
{
    for (int i = 0; i < f->nctls; i++) {
        bb_ctl *c = f->ctls[i];
        if (c->kind == AFG_TIMER) {
            timer_stop(c);
            if (c->tio) IExec->FreeSysObject(ASOT_IOREQUEST, c->tio);
        }
    }
    if (f->winobj) {
        if (f->win) IIntuition->IDoMethod(f->winobj, WM_CLOSE);
        IIntuition->DisposeObject(f->winobj);    /* disposes the layout and gadgets too */
    }
    for (int i = 0; i < f->nctls; i++) {
        bb_ctl *c = f->ctls[i];
        free_nodes(c);
        for (int k = 0; k < c->nitems; k++) free(c->items[k]);
        free(c->items);
        free(c->labelarray);
        free(c->tagstr);
        free(c->hint);
        free(c->text);
        free(c->extra);
        free(c);
    }
    free(f->ctls);
    free(f->self.tagstr);
    free(f->self.text);
    free(f->ret);
    free(f->file);
    afg_free(f->afg);
    free(f);
}

bb_form *bb_form_load(const char *afg_text, const char *file, bb_form_event_fn fn, bb_form_has_event_fn has,
                      void *ud, char *err, int errlen)
{
    char e[200];
    afg_node *a = afg_parse(afg_text, e, sizeof e);
    if (!a) {
        snprintf(err, errlen, "%s:%s", file ? file : "form", e + (strncmp(e, "line ", 5) ? 0 : 5));
        return NULL;
    }
    bb_form *f = calloc(1, sizeof *f);
    f->afg = a;
    f->file = xstrdup(file ? file : "form");
    f->fn = fn;
    f->has = has;
    f->ud = ud;
    f->enabled = 1;
    f->self.form = f;
    f->self.kind = AFG_WINDOW;
    f->self.name = "Form";
    f->self.visible = 0;
    afg_walk(a, collect, f);
    f->root = build(f, a->children[0]);
    if (!f->root) {
        snprintf(err, errlen, "%s:%d: can't create the form's gadgets (missing ReAction class?)", f->file,
                 a->children[0]->line);
        form_free(f);
        return NULL;
    }
    int w = afg_get_int(a, "width"), h = afg_get_int(a, "height");
    tags t = { 0 };
    tg(&t, WA_Title, (uint32)afg_get(a, "title"));
    tg(&t, WA_DragBar, TRUE);
    tg(&t, WA_CloseGadget, TRUE);
    tg(&t, WA_DepthGadget, TRUE);
    tg(&t, WA_Activate, TRUE);
    tg(&t, WA_SizeGadget, afg_get_bool(a, "resizable"));
    if (w > 0) tg(&t, WA_InnerWidth, w);
    if (h > 0) tg(&t, WA_InnerHeight, h);
    tg(&t, WA_IDCMP, IDCMP_GADGETUP | IDCMP_CLOSEWINDOW | IDCMP_RAWKEY | IDCMP_NEWSIZE | IDCMP_ACTIVEWINDOW |
                         IDCMP_INACTIVEWINDOW);
    tg(&t, WINDOW_Position, WPOS_CENTERSCREEN);
    tg(&t, WINDOW_GadgetHelp, TRUE);
    tg(&t, WINDOW_Layout, (uint32)f->root);
    f->winobj = new_obj(C_WINDOW, &t);
    f->self.obj = f->winobj;
    if (!f->winobj) {
        IIntuition->DisposeObject(f->root);
        f->root = NULL;
        snprintf(err, errlen, "%s:%d: can't create the window", f->file, a->line);
        form_free(f);
        return NULL;
    }
    f->loaded = 1;
    f->next = forms;
    forms = f;
    fire(f, "Form", "Load", 0, NULL);
    for (int i = 0; i < f->nctls; i++)
        if (f->ctls[i]->kind == AFG_TIMER) timer_send(f->ctls[i]);
    return f;
}

const char *bb_form_name(bb_form *f) { return afg_get(f->afg, "name"); }

bb_form *bb_form_find(const char *name)
{
    for (bb_form *f = forms; f; f = f->next)
        if (f->loaded && !strcasecmp(bb_form_name(f), name)) return f;
    return NULL;
}

bb_ctl *bb_form_self(bb_form *f) { return &f->self; }

bb_ctl *bb_form_ctl(bb_form *f, const char *name)
{
    if (!name || !*name) return NULL;
    for (int i = 0; i < f->nctls; i++)
        if (!strcasecmp(f->ctls[i]->name, name)) return f->ctls[i];
    return NULL;
}

const char *bb_ctl_kind(bb_ctl *c) { return afg_kind_name(c->kind); }

int bb_form_show(bb_form *f)
{
    if (!f->loaded) return 364;
    if (f->win) {
        IIntuition->WindowToFront(f->win);
        return 0;
    }
    f->win = (struct Window *)IIntuition->IDoMethod(f->winobj, WM_OPEN);
    if (!f->win) return 7;
    f->self.visible = 1;
    f->lastw = f->win->Width;
    f->lasth = f->win->Height;
    fire(f, "Form", "Activate", 0, NULL);
    fire(f, "Form", "Resize", 0, NULL);
    return 0;
}

int bb_form_hide(bb_form *f)
{
    if (!f->loaded) return 364;
    if (f->win) IIntuition->IDoMethod(f->winobj, WM_CLOSE);
    f->win = NULL;
    f->self.visible = 0;
    return 0;
}

static int unload(bb_form *f, int mode)
{
    if (!f->loaded || f->unloading) return 0;
    int32_t a[2] = { 0, mode };
    f->unloading = 1;
    fire(f, "Form", "QueryUnload", 2, a);
    if (!a[0]) {
        a[0] = 0;
        fire(f, "Form", "Unload", 1, a);
    }
    f->unloading = 0;
    if (a[0] && !ending) return 1;        /* cancelled */
    for (int i = 0; i < f->nctls; i++)
        if (f->ctls[i]->kind == AFG_TIMER) timer_stop(f->ctls[i]);
    bb_form_hide(f);
    f->loaded = 0;                        /* freed by the event loop / cleanup */
    return 0;
}

int bb_form_unload(bb_form *f) { return unload(f, 1); }

static void reap(void)
{
    for (bb_form **p = &forms; *p;) {
        bb_form *f = *p;
        if (!f->loaded) {
            *p = f->next;
            form_free(f);
        } else
            p = &f->next;
    }
}

/* --- properties ------------------------------------------------------------------------- */

#define IS(a) (!strcasecmp(prop, a))

static int ret_str(bb_ctl *c, bb_fval *out, const char *s)
{
    free(c->form->ret);
    c->form->ret = xstrdup(s ? s : "");
    out->type = BB_FV_STR;
    out->s = c->form->ret;
    return 0;
}

static int ret_int(bb_fval *out, int32 v)
{
    out->type = BB_FV_INT;
    out->i = v;
    return 0;
}

static int32 vint(const bb_fval *v) { return v->type == BB_FV_INT ? v->i : (v->s ? atol(v->s) : 0); }

static const char *vstr(const bb_fval *v, char *buf)
{
    if (v->type == BB_FV_STR) return v->s ? v->s : "";
    sprintf(buf, "%ld", (long)v->i);
    return buf;
}

static int vb_bool(int b) { return b ? -1 : 0; }

static int has_list(afg_kind k) { return k == AFG_CHOOSER || k == AFG_RADIO || k == AFG_LISTBROWSER; }

static char *editor_text(bb_ctl *c)
{
    STRPTR s = (STRPTR)IIntuition->DoGadgetMethod((struct Gadget *)c->obj, c->form->win, NULL,
                                                   (Msg)&(struct GP_TEXTEDITOR_ExportText){ GM_TEXTEDITOR_ExportText, NULL });
    char *o = xstrdup(s ? (char *)s : "");
    if (s) IExec->FreeVec(s);
    return o;
}

static int form_get(bb_form *f, const char *prop, bb_fval *out)
{
    struct Window *w = f->win;
    if (IS("Name")) return ret_str(&f->self, out, bb_form_name(f));
    if (IS("Caption")) return ret_str(&f->self, out, (const char *)get_attr(&f->self, WA_Title));
    if (IS("Visible")) return ret_int(out, vb_bool(w != NULL));
    if (IS("Enabled")) return ret_int(out, vb_bool(f->enabled));
    if (IS("Tag")) return ret_str(&f->self, out, f->self.tagstr);
    if (IS("WindowState")) return ret_int(out, 0);
    if (IS("Width")) return ret_int(out, w ? w->Width - w->BorderLeft - w->BorderRight : afg_get_int(f->afg, "width"));
    if (IS("Height")) return ret_int(out, w ? w->Height - w->BorderTop - w->BorderBottom : afg_get_int(f->afg, "height"));
    if (IS("Left")) return ret_int(out, w ? w->LeftEdge : 0);
    if (IS("Top")) return ret_int(out, w ? w->TopEdge : 0);
    return 438;
}

static int form_set(bb_form *f, const char *prop, const bb_fval *v)
{
    char buf[16];
    struct Window *w = f->win;
    if (IS("Caption")) {
        /* window.class keeps the pointer: keep our own copy */
        free(f->self.text);
        f->self.text = xstrdup(vstr(v, buf));
        set_attr(&f->self, WA_Title, (uint32)f->self.text);
        return 0;
    }
    if (IS("Visible")) return vint(v) ? bb_form_show(f) : bb_form_hide(f);
    if (IS("Enabled")) {
        f->enabled = vint(v) != 0;
        set_attr(&f->self, WA_BusyPointer, !f->enabled);
        return 0;
    }
    if (IS("Tag")) {
        free(f->self.tagstr);
        f->self.tagstr = xstrdup(vstr(v, buf));
        return 0;
    }
    if (IS("Width") || IS("Height") || IS("Left") || IS("Top")) {
        if (!w) return 0;
        int x = w->LeftEdge, y = w->TopEdge, ww = w->Width, hh = w->Height, n = vint(v);
        if (IS("Width")) ww = n + w->BorderLeft + w->BorderRight;
        if (IS("Height")) hh = n + w->BorderTop + w->BorderBottom;
        if (IS("Left")) x = n;
        if (IS("Top")) y = n;
        IIntuition->ChangeWindowBox(w, x, y, ww, hh);
        return 0;
    }
    if (IS("Name") || IS("WindowState")) return 383;
    return 438;
}

int bb_ctl_get(bb_ctl *c, const char *prop, int index, bb_fval *out)
{
    out->type = BB_FV_NONE;
    if (c->kind == AFG_WINDOW) return form_get(c->form, prop, out);
    if (!c->form->loaded) return 364;
    struct Gadget *g = (struct Gadget *)c->obj;
    afg_kind k = c->kind;
    if (IS("Name")) return ret_str(c, out, c->name);
    if (IS("Tag")) return ret_str(c, out, c->tagstr);
    if (k == AFG_TIMER) {
        if (IS("Interval")) return ret_int(out, c->interval);
        if (IS("Enabled")) return ret_int(out, vb_bool(c->enabled));
        return 438;
    }
    if (IS("Visible")) return ret_int(out, vb_bool(c->visible));
    if (IS("Enabled")) return ret_int(out, vb_bool(!(g->Flags & GFLG_DISABLED)));
    if (IS("ToolTipText")) return ret_str(c, out, c->hint);
    if (IS("Left")) return ret_int(out, g->LeftEdge);
    if (IS("Top")) return ret_int(out, g->TopEdge);
    if (IS("Width")) return ret_int(out, g->Width);
    if (IS("Height")) return ret_int(out, g->Height);
    if (has_list(k)) {
        if (IS("ListCount")) return ret_int(out, c->nitems);
        if (IS("List")) {
            if (index < 0 || index >= c->nitems) return 381;
            return ret_str(c, out, c->items[index]);
        }
        if (IS("ListIndex") || (k == AFG_RADIO && IS("Value"))) {
            if (k == AFG_LISTBROWSER) {
                int32 s = (int32)get_attr(c, LISTBROWSER_Selected);
                c->sel = s;
            } else if (k == AFG_CHOOSER)
                c->sel = (int32)get_attr(c, CHOOSER_Selected);
            else
                c->sel = (int32)get_attr(c, RADIOBUTTON_Selected);
            return ret_int(out, c->sel);
        }
        if (IS("Text")) {
            bb_fval tmp;
            bb_ctl_get(c, "ListIndex", -1, &tmp);
            return ret_str(c, out, c->sel >= 0 && c->sel < c->nitems ? c->items[c->sel] : "");
        }
        if (k == AFG_LISTBROWSER && IS("TopIndex")) return ret_int(out, (int32)get_attr(c, LISTBROWSER_Top));
    }
    switch (k) {
    case AFG_BUTTON:
    case AFG_CHECKBOX:
    case AFG_LABEL:
        if (IS("Caption") || IS("Text")) return ret_str(c, out, c->text ? c->text : afg_get(c->node, "text"));
        if (k == AFG_CHECKBOX && IS("Value")) return ret_int(out, get_attr(c, CHECKBOX_Checked) ? 1 : 0);
        break;
    case AFG_STRING:
        if (IS("Text")) return ret_str(c, out, (const char *)get_attr(c, STRINGA_TextVal));
        if (IS("MaxLength")) return ret_int(out, (int32)get_attr(c, STRINGA_MaxChars));
        if (IS("Locked")) return ret_int(out, vb_bool(get_attr(c, GA_ReadOnly)));
        if (IS("SelStart")) return ret_int(out, (int32)get_attr(c, STRINGA_BufferPos));
        if (IS("SelLength")) return ret_int(out, 0);
        break;
    case AFG_INTEGER:
        if (IS("Value")) return ret_int(out, (int32)get_attr(c, INTEGER_Number));
        if (IS("Text")) {
            char b[16];
            sprintf(b, "%ld", (long)(int32)get_attr(c, INTEGER_Number));
            return ret_str(c, out, b);
        }
        if (IS("Min")) return ret_int(out, (int32)get_attr(c, INTEGER_Minimum));
        if (IS("Max")) return ret_int(out, (int32)get_attr(c, INTEGER_Maximum));
        break;
    case AFG_SLIDER:
        if (IS("Value")) return ret_int(out, (int32)get_attr(c, SLIDER_Level));
        if (IS("Min")) return ret_int(out, (int32)get_attr(c, SLIDER_Min));
        if (IS("Max")) return ret_int(out, (int32)get_attr(c, SLIDER_Max));
        break;
    case AFG_SCROLLER:
        if (IS("Value")) return ret_int(out, (int32)get_attr(c, SCROLLER_Top));
        if (IS("Max")) return ret_int(out, (int32)get_attr(c, SCROLLER_Total));
        if (IS("LargeChange")) return ret_int(out, (int32)get_attr(c, SCROLLER_Visible));
        break;
    case AFG_FUELGAUGE:
        if (IS("Value")) return ret_int(out, (int32)get_attr(c, FUELGAUGE_Level));
        if (IS("Min")) return ret_int(out, (int32)get_attr(c, FUELGAUGE_Min));
        if (IS("Max")) return ret_int(out, (int32)get_attr(c, FUELGAUGE_Max));
        break;
    case AFG_GETFILE:
        if (IS("FileName") || IS("Text")) return ret_str(c, out, (const char *)get_attr(c, GETFILE_FullFile));
        if (IS("DialogTitle")) return ret_str(c, out, (const char *)get_attr(c, GETFILE_TitleText));
        if (IS("Pattern")) return ret_str(c, out, (const char *)get_attr(c, GETFILE_Pattern));
        if (IS("SaveMode")) return ret_int(out, vb_bool(get_attr(c, GETFILE_DoSaveMode)));
        break;
    case AFG_TEXTEDITOR:
        if (IS("Text")) {
            char *s = editor_text(c);
            ret_str(c, out, s);
            free(s);
            return 0;
        }
        if (IS("Locked")) return ret_int(out, vb_bool(get_attr(c, GA_TEXTEDITOR_ReadOnly)));
        if (IS("LineCount")) {
            char *s = editor_text(c);
            int n = *s ? 1 : 0;
            for (char *p = s; *p; p++)
                if (*p == '\n' && p[1]) n++;
            free(s);
            return ret_int(out, n);
        }
        break;
    default:
        break;
    }
    return 438;
}

static int set_text_prop(bb_ctl *c, const char *s)
{
    free(c->text);
    c->text = xstrdup(s);
    set_attr(c, GA_Text, (uint32)c->text);
    relayout(c->form);
    return 0;
}

int bb_ctl_set(bb_ctl *c, const char *prop, int index, const bb_fval *v)
{
    char buf[16];
    if (c->kind == AFG_WINDOW) return form_set(c->form, prop, v);
    if (!c->form->loaded) return 364;
    afg_kind k = c->kind;
    if (IS("Name")) return 383;
    if (IS("Tag")) {
        free(c->tagstr);
        c->tagstr = xstrdup(vstr(v, buf));
        return 0;
    }
    if (k == AFG_TIMER) {
        if (IS("Interval")) {
            c->interval = vint(v);
            timer_stop(c);
            timer_send(c);
            return 0;
        }
        if (IS("Enabled")) {
            c->enabled = vint(v) != 0;
            if (c->enabled) timer_send(c);
            else timer_stop(c);
            return 0;
        }
        return 438;
    }
    if (IS("Enabled")) {
        set_attr(c, GA_Disabled, vint(v) == 0);
        return 0;
    }
    if (IS("Visible")) {
        c->visible = vint(v) != 0;
        set_attr(c, GA_Hidden, !c->visible);
        relayout(c->form);
        return 0;
    }
    if (IS("ToolTipText")) {
        free(c->hint);
        c->hint = xstrdup(vstr(v, buf));
        set_attr(c, GA_HintInfo, (uint32)c->hint);
        return 0;
    }
    if (IS("Left") || IS("Top") || IS("Width") || IS("Height")) return 383;
    if (has_list(k)) {
        if (IS("ListCount")) return 383;
        if (IS("List")) {
            if (k == AFG_RADIO) return 383;
            if (index < 0 || index >= c->nitems) return 381;
            free(c->items[index]);
            c->items[index] = xstrdup(vstr(v, buf));
            list_changed(c);
            return 0;
        }
        if (IS("ListIndex") || (k == AFG_RADIO && IS("Value"))) {
            int32 n = vint(v);
            if (n < -1 || n >= c->nitems || (n == -1 && k != AFG_LISTBROWSER)) return 380;
            c->sel = n;
            if (k == AFG_LISTBROWSER) {
                set_attr(c, LISTBROWSER_Selected, (uint32)n);
                if (n >= 0) set_attr(c, LISTBROWSER_MakeVisible, (uint32)n);
            } else
                set_attr(c, k == AFG_CHOOSER ? CHOOSER_Selected : RADIOBUTTON_Selected, (uint32)n);
            fire0(c, "Click");        /* VB6 fires Click when code sets ListIndex */
            return 0;
        }
        if (k == AFG_LISTBROWSER && IS("TopIndex")) {
            set_attr(c, LISTBROWSER_Top, (uint32)vint(v));
            return 0;
        }
        if (IS("Text")) return 383;
    }
    switch (k) {
    case AFG_BUTTON:
    case AFG_CHECKBOX:
    case AFG_LABEL:
        if (IS("Caption") || IS("Text")) return set_text_prop(c, vstr(v, buf));
        if (k == AFG_CHECKBOX && IS("Value")) {
            int on = vint(v) != 0;
            set_attr(c, CHECKBOX_Checked, on);
            fire0(c, "Click");
            return 0;
        }
        break;
    case AFG_STRING:
        if (IS("Text")) {
            const char *s = vstr(v, buf);
            set_attr(c, STRINGA_TextVal, (uint32)s);
            free(c->text);
            c->text = xstrdup(s);
            fire0(c, "Change");
            return 0;
        }
        if (IS("MaxLength")) {
            set_attr(c, STRINGA_MaxChars, vint(v));
            return 0;
        }
        if (IS("Locked")) {
            set_attr(c, GA_ReadOnly, vint(v) != 0);
            return 0;
        }
        if (IS("SelStart")) {
            set_attr(c, STRINGA_BufferPos, vint(v));
            return 0;
        }
        if (IS("SelLength")) return 0;
        break;
    case AFG_INTEGER:
        if (IS("Value") || IS("Text")) {
            set_attr(c, INTEGER_Number, vint(v));
            return 0;
        }
        if (IS("Min")) { set_attr(c, INTEGER_Minimum, vint(v)); return 0; }
        if (IS("Max")) { set_attr(c, INTEGER_Maximum, vint(v)); return 0; }
        break;
    case AFG_SLIDER:
        if (IS("Value")) {
            set_attr(c, SLIDER_Level, vint(v));
            fire0(c, "Change");
            return 0;
        }
        if (IS("Min")) { set_attr(c, SLIDER_Min, vint(v)); return 0; }
        if (IS("Max")) { set_attr(c, SLIDER_Max, vint(v)); return 0; }
        break;
    case AFG_SCROLLER:
        if (IS("Value")) { set_attr(c, SCROLLER_Top, vint(v)); fire0(c, "Change"); return 0; }
        if (IS("Max")) { set_attr(c, SCROLLER_Total, vint(v)); return 0; }
        if (IS("LargeChange")) { set_attr(c, SCROLLER_Visible, vint(v)); return 0; }
        break;
    case AFG_FUELGAUGE:
        if (IS("Value")) { set_attr(c, FUELGAUGE_Level, vint(v)); return 0; }
        if (IS("Min")) { set_attr(c, FUELGAUGE_Min, vint(v)); return 0; }
        if (IS("Max")) { set_attr(c, FUELGAUGE_Max, vint(v)); return 0; }
        break;
    case AFG_GETFILE:
        if (IS("FileName") || IS("Text")) {
            /* getfile copies the string */
            const char *s = vstr(v, buf);
            set_attr(c, GETFILE_FullFile, (uint32)s);
            return 0;
        }
        if (IS("DialogTitle")) {
            free(c->text);
            c->text = xstrdup(vstr(v, buf));
            set_attr(c, GETFILE_TitleText, (uint32)c->text);
            return 0;
        }
        if (IS("Pattern")) {
            free(c->extra);      /* keep the string alive while the gadget may point at it */
            c->extra = xstrdup(vstr(v, buf));
            set_attr(c, GETFILE_Pattern, (uint32)c->extra);
            set_attr(c, GETFILE_DoPatterns, *c->extra != 0);
            return 0;
        }
        if (IS("SaveMode")) { set_attr(c, GETFILE_DoSaveMode, vint(v) != 0); return 0; }
        break;
    case AFG_TEXTEDITOR:
        if (IS("Text")) {
            set_attr(c, GA_TEXTEDITOR_Contents, (uint32)vstr(v, buf));
            fire0(c, "Change");
            return 0;
        }
        if (IS("Locked")) { set_attr(c, GA_TEXTEDITOR_ReadOnly, vint(v) != 0); return 0; }
        if (IS("LineCount")) return 383;
        break;
    default:
        break;
    }
    return 438;
}

#undef IS
#define IS(a) (!strcasecmp(method, a))

int bb_ctl_call(bb_ctl *c, const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    char buf[16];
    if (ret) ret->type = BB_FV_NONE;
    bb_form *f = c->form;
    if (c->kind == AFG_WINDOW) {
        if (IS("Show")) return bb_form_show(f);
        if (IS("Hide")) return bb_form_hide(f);
        if (IS("Refresh")) { relayout(f); return 0; }
        if (IS("Move")) {
            static const char *const p[4] = { "Left", "Top", "Width", "Height" };
            for (int i = 0; i < argc && i < 4; i++) form_set(f, p[i], &argv[i]);
            return 0;
        }
        return 438;
    }
    if (!f->loaded) return 364;
    if (IS("Refresh")) {
        if (f->win) IIntuition->RefreshGList((struct Gadget *)c->obj, f->win, NULL, 1);
        return 0;
    }
    if (IS("SetFocus")) {
        if (f->win && (c->kind == AFG_STRING || c->kind == AFG_INTEGER || c->kind == AFG_TEXTEDITOR))
            IIntuition->IDoMethod(f->winobj, WM_ACTIVATEGADGET, c->obj);
        return 0;
    }
    if (has_list(c->kind) && c->kind != AFG_RADIO) {
        if (IS("AddItem")) {
            if (argc < 1) return 5;
            int at = argc > 1 ? vint(&argv[1]) : -1;
            if (argc > 1 && (at < 0 || at > c->nitems)) return 5;
            items_insert(c, at, vstr(&argv[0], buf));
            if (c->sel >= 0 && at >= 0 && at <= c->sel) c->sel++;
            list_changed(c);
            return 0;
        }
        if (IS("RemoveItem")) {
            if (argc < 1) return 5;
            int at = vint(&argv[0]);
            if (at < 0 || at >= c->nitems) return 5;
            items_remove(c, at);
            if (c->sel == at) c->sel = -1;
            else if (c->sel > at) c->sel--;
            list_changed(c);
            return 0;
        }
        if (IS("Clear")) {
            while (c->nitems) items_remove(c, c->nitems - 1);
            c->sel = -1;
            list_changed(c);
            return 0;
        }
    }
    if (c->kind == AFG_GETFILE && IS("ShowOpen")) {
        if (IIntuition->IDoMethod(c->obj, GFILE_REQUEST, f->win)) {
            if (f->win) IIntuition->RefreshGList((struct Gadget *)c->obj, f->win, NULL, 1);
        } else
            set_attr(c, GETFILE_FullFile, (uint32)"");
        return 0;
    }
    return 438;
}

/* --- events ----------------------------------------------------------------------------- */

static bb_ctl *ctl_by_gid(bb_form *f, uint32 gid)
{
    if (gid >= 1 && gid <= (uint32)f->nctls) return f->ctls[gid - 1];
    return NULL;
}

static int vb_key(int raw)
{
    static const char row1[] = "1234567890", rowq[] = "QWERTYUIOP", rowa[] = "ASDFGHJKL", rowz[] = "ZXCVBNM";
    if (raw >= 0x01 && raw <= 0x0A) return row1[raw - 1];
    if (raw >= 0x10 && raw <= 0x19) return rowq[raw - 0x10];
    if (raw >= 0x20 && raw <= 0x28) return rowa[raw - 0x20];
    if (raw >= 0x31 && raw <= 0x37) return rowz[raw - 0x31];
    if (raw >= 0x50 && raw <= 0x59) return 112 + raw - 0x50;   /* F1-F10 */
    switch (raw) {
    case 0x40: return 32;
    case 0x41: return 8;
    case 0x42: return 9;
    case 0x43:
    case 0x44: return 13;
    case 0x45: return 27;
    case 0x46: return 46;
    case 0x4C: return 38;
    case 0x4D: return 40;
    case 0x4E: return 39;
    case 0x4F: return 37;
    case 0x5F: return 47;
    }
    return 0x100 + raw;      /* other keys: 256 + the raw key code */
}

static int vb_shift(uint32 q)
{
    int s = 0;
    if (q & (IEQUALIFIER_LSHIFT | IEQUALIFIER_RSHIFT)) s |= 1;
    if (q & IEQUALIFIER_CONTROL) s |= 2;
    if (q & (IEQUALIFIER_LALT | IEQUALIFIER_RALT)) s |= 4;
    if (q & (IEQUALIFIER_LCOMMAND | IEQUALIFIER_RCOMMAND)) s |= 8;
    return s;
}

static void raw_key(bb_form *f, int code)
{
    uint32 q = 0;
    IIntuition->GetAttr(WINDOW_Qualifier, f->winobj, &q);
    int up = code & IECODE_UP_PREFIX, raw = code & 0x7F;
    if (raw >= 0x60 && raw <= 0x67) return;            /* qualifier keys alone */
    int32_t a[2] = { vb_key(raw), vb_shift(q) };
    fire(f, "Form", up ? "KeyUp" : "KeyDown", 2, a);
    if (up || ending) return;
    if (!IKM) {
        KeymapLib = IExec->OpenLibrary("keymap.library", 50);
        if (KeymapLib) IKM = (void *)IExec->GetInterface(KeymapLib, "main", 1, NULL);
    }
    if (!IKM) return;
    struct InputEvent ie;
    memset(&ie, 0, sizeof ie);
    ie.ie_Class = IECLASS_RAWKEY;
    ie.ie_Code = raw;
    ie.ie_Qualifier = q;
    char ch[8];
    if (IKM->MapRawKey(&ie, ch, sizeof ch, NULL) == 1) {
        int32_t k = (unsigned char)ch[0];
        fire(f, "Form", "KeyPress", 1, &k);
    }
}

static void gadget_up(bb_form *f, bb_ctl *c, uint16 code)
{
    switch (c->kind) {
    case AFG_BUTTON:
    case AFG_CHECKBOX:
    case AFG_RADIO:
        if (c->kind == AFG_RADIO) c->sel = code;
        fire0(c, "Click");
        break;
    case AFG_CHOOSER:
        c->sel = code;
        fire0(c, "Click");
        break;
    case AFG_STRING: {
        const char *now = (const char *)get_attr(c, STRINGA_TextVal);
        if (!now) now = "";
        if (!c->text || strcmp(c->text, now)) {
            free(c->text);
            c->text = xstrdup(now);
            fire0(c, "Change");
        }
        if (!ending) {
            int32_t k = code == 9 ? 9 : 13;
            fire(f, c->name, "KeyPress", 1, &k);
        }
        break;
    }
    case AFG_INTEGER:
    case AFG_SLIDER:
    case AFG_SCROLLER:
    case AFG_TEXTEDITOR:
        fire0(c, "Change");
        break;
    case AFG_LISTBROWSER: {
        uint32 rel = get_attr(c, LISTBROWSER_RelEvent);
        c->sel = (int32)get_attr(c, LISTBROWSER_Selected);
        fire0(c, "Click");
        if (!ending && (rel & LBRE_DOUBLECLICK)) fire0(c, "DblClick");
        break;
    }
    case AFG_GETFILE:
        if (IIntuition->IDoMethod(c->obj, GFILE_REQUEST, f->win)) fire0(c, "Change");
        break;
    default:
        break;
    }
}

static void handle_form(bb_form *f)
{
    uint32 result;
    uint16 code = 0;
    while (f->loaded && f->win && !ending &&
           (result = IIntuition->IDoMethod(f->winobj, WM_HANDLEINPUT, &code)) != WMHI_LASTMSG) {
        if (!f->enabled && (result & WMHI_CLASSMASK) != WMHI_NEWSIZE) continue;
        switch (result & WMHI_CLASSMASK) {
        case WMHI_CLOSEWINDOW:
            unload(f, 0);
            break;
        case WMHI_GADGETUP: {
            bb_ctl *c = ctl_by_gid(f, result & WMHI_GADGETMASK);
            if (c) gadget_up(f, c, code);
            break;
        }
        case WMHI_RAWKEY:
            raw_key(f, result & WMHI_KEYMASK);
            break;
        case WMHI_ACTIVE:
            fire(f, "Form", "Activate", 0, NULL);
            break;
        case WMHI_INACTIVE:
            fire(f, "Form", "Deactivate", 0, NULL);
            break;
        case WMHI_NEWSIZE:
            if (f->win && (f->win->Width != f->lastw || f->win->Height != f->lasth)) {
                f->lastw = f->win->Width;
                f->lasth = f->win->Height;
                fire(f, "Form", "Resize", 0, NULL);
            }
            break;
        }
    }
}

static int any_loaded(void)
{
    for (bb_form *f = forms; f; f = f->next)
        if (f->loaded) return 1;
    return 0;
}

static void pump(int wait)
{
    uint32 sigs = SIGBREAKF_CTRL_C;
    for (bb_form *f = forms; f; f = f->next)
        if (f->loaded && f->win) {
            uint32 s = 0;
            IIntuition->GetAttr(WINDOW_SigMask, f->winobj, &s);
            sigs |= s;
        }
    if (timer_port) sigs |= 1u << timer_port->mp_SigBit;
    uint32 got = wait ? IExec->Wait(sigs) : IExec->SetSignal(0, sigs) & sigs;
    if (got & SIGBREAKF_CTRL_C) {
        ending = 1;
        end_code = 0;
    }
    if (timer_port && (got & (1u << timer_port->mp_SigBit))) timers_handle();
    for (bb_form *f = forms; f && !ending; f = f->next)
        if (f->loaded && f->win) handle_form(f);
}

int bb_forms_run(void)
{
    while (!ending && any_loaded()) {
        reap();
        pump(1);
    }
    reap();
    int r = ending ? end_code : 0;
    return r;
}

void bb_forms_doevents(void)
{
    pump(0);
}

void bb_forms_end(void) { ending = 1; }

void bb_forms_cleanup(void)
{
    while (forms) {
        bb_form *f = forms;
        forms = f->next;
        f->loaded = 0;
        form_free(f);
    }
    if (timer_master) {
        IExec->CloseDevice((struct IORequest *)timer_master);
        IExec->FreeSysObject(ASOT_IOREQUEST, timer_master);
        IExec->FreeSysObject(ASOT_PORT, timer_port);
        timer_master = NULL;
        timer_port = NULL;
    }
    if (IKM) IExec->DropInterface((struct Interface *)IKM);
    if (KeymapLib) IExec->CloseLibrary(KeymapLib);
    IKM = NULL;
    KeymapLib = NULL;
    if (ILB) IExec->DropInterface((struct Interface *)ILB);
    if (ICH) IExec->DropInterface((struct Interface *)ICH);
    if (ILO) IExec->DropInterface((struct Interface *)ILO);
    ILB = NULL;
    ICH = NULL;
    ILO = NULL;
    for (int i = 0; i < C_NUM; i++)
        if (class_lib[i]) {
            IIntuition->CloseClass(class_lib[i]);
            class_lib[i] = NULL;
            class_ptr[i] = NULL;
        }
}

/* --- requesters ------------------------------------------------------------------------- */

static struct Window *front_window(void)
{
    for (bb_form *f = forms; f; f = f->next)
        if (f->loaded && f->win) return f->win;
    return NULL;
}

static const char *prog_name(void)
{
    static char name[64];
    if (!name[0]) {
        if (!IDOS->GetCliProgramName(name, sizeof name) || !name[0]) strcpy(name, "Boing BASIC");
        else strcpy(name, (char *)IDOS->FilePart(name));
    }
    return name;
}

static uint32 open_req(tags *t)
{
    tg(t, TAG_DONE, 0);
    Class *k = cls(C_REQUESTER);
    if (!k) {
        free(t->t);
        return 0;
    }
    Object *req = IIntuition->NewObjectA(k, NULL, t->t);
    free(t->t);
    if (!req) return 0;
    struct Window *w = front_window();
    struct Screen *scr = w ? NULL : IIntuition->LockPubScreen(NULL);
    uint32 r = IIntuition->IDoMethod(req, RM_OPENREQ, NULL, w, scr);
    if (scr) IIntuition->UnlockPubScreen(NULL, scr);
    IIntuition->DisposeObject(req);
    return r;
}

int bb_ui_msgbox(const char *prompt, int buttons, const char *title)
{
    static const char *const texts[6] = { "_OK", "_OK|_Cancel", "_Abort|_Retry|_Ignore", "_Yes|_No|_Cancel",
                                          "_Yes|_No", "_Retry|_Cancel" };
    static const int codes[6][3] = { { 1 }, { 1, 2 }, { 3, 4, 5 }, { 6, 7, 2 }, { 6, 7 }, { 4, 2 } };
    static const int counts[6] = { 1, 2, 3, 3, 2, 2 };
    int type = buttons & 7;
    if (type > 5) type = 0;
    int img = REQIMAGE_DEFAULT;
    switch (buttons & 0x70) {
    case 16: img = REQIMAGE_ERROR; break;
    case 32: img = REQIMAGE_QUESTION; break;
    case 48: img = REQIMAGE_WARNING; break;
    case 64: img = REQIMAGE_INFO; break;
    }
    tags t = { 0 };
    tg(&t, REQ_Type, REQTYPE_INFO);
    tg(&t, REQ_TitleText, (uint32)(title && *title ? title : prog_name()));
    tg(&t, REQ_BodyText, (uint32)prompt);
    tg(&t, REQ_GadgetText, (uint32)texts[type]);
    tg(&t, REQ_Image, img);
    uint32 r = open_req(&t);
    /* buttons are numbered 1, 2, ... from the left and the rightmost is 0 */
    int n = counts[type];
    int idx = r == 0 ? n - 1 : (int)r - 1;
    if (idx < 0 || idx >= n) idx = n - 1;
    return codes[type][idx];
}

char *bb_ui_inputbox(const char *prompt, const char *title, const char *def)
{
    char *buf = calloc(1, 1024);
    if (!buf) return NULL;
    if (def) strncpy(buf, def, 1023);
    tags t = { 0 };
    tg(&t, REQ_Type, REQTYPE_STRING);
    tg(&t, REQ_TitleText, (uint32)(title && *title ? title : prog_name()));
    tg(&t, REQ_BodyText, (uint32)prompt);
    tg(&t, REQ_GadgetText, (uint32)"_OK|_Cancel");
    tg(&t, REQS_Buffer, (uint32)buf);
    tg(&t, REQS_MaxChars, 1023);
    tg(&t, REQS_AllowEmpty, TRUE);
    uint32 r = open_req(&t);
    if (r == 0) {
        free(buf);
        return NULL;
    }
    return buf;
}

int bb_ctl_screen_box(bb_ctl *c, int *x, int *y, int *w, int *h)
{
    struct Window *win = c->form->win;
    if (!win) return 0;
    if (c->kind == AFG_WINDOW) {
        *x = win->LeftEdge;
        *y = win->TopEdge;
        *w = win->Width;
        *h = win->Height;
        return 1;
    }
    struct Gadget *g = (struct Gadget *)c->obj;
    if (!g) return 0;
    *x = win->LeftEdge + g->LeftEdge;
    *y = win->TopEdge + g->TopEdge;
    *w = g->Width;
    *h = g->Height;
    return 1;
}
