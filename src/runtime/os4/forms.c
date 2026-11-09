/* Forms on AmigaOS 4 ReAction (see bb_forms.h and docs/forms-events.md).
 *
 * A form is built at run time from its .afg tree: one window.class object whose
 * WINDOW_Layout is the root layout.gadget, one BOOPSI object per designer object (as the C
 * that AmiForge's designer generates, GuiModel.cpp), gadget IDs 1..n. The event loop waits
 * on every open window, the timers' port and Ctrl-C, and calls the event handler for
 * `<control>_<Event>`. Classes are opened with IIntuition->OpenClass, so no class
 * interface globals are needed except the few classes with library functions (list nodes,
 * RethinkLayout). */
#include "forms_int.h"
#include "../boing.h"     /* bb_app_title for remembered window boxes */
#include "../platform.h"  /* bb_plat_seconds: timers keep a fixed timeline */
#include <intuition/pointerclass.h>

/* ReAction's layout code is stack hungry, and a program started from a background CLI (or
 * Workbench) may get only a few KB: every program linking the forms gets 256 KB. (A
 * project's Stack= setting, emitted by the compiler, comes first in the file and wins.) */
static const char __attribute__((used)) bb_stack_cookie[] = "$STACK:262144";

/* --- classes ---------------------------------------------------------------------------- */

static const char *const class_names[C_NUM] = {
    "window.class", "gadgets/layout.gadget", "gadgets/button.gadget", "gadgets/string.gadget",
    "gadgets/integer.gadget", "gadgets/checkbox.gadget", "gadgets/chooser.gadget",
    "gadgets/radiobutton.gadget", "gadgets/slider.gadget", "gadgets/scroller.gadget",
    "gadgets/listbrowser.gadget", "images/label.image", "gadgets/space.gadget", "gadgets/fuelgauge.gadget",
    "gadgets/getfile.gadget", "gadgets/texteditor.gadget", "requester.class",
    "menuclass", "popupmenu.class", "popupmenuitem.class", "gadgets/speedbar.gadget", "images/bitmap.image",
    "gadgets/clicktab.gadget", "arexx.class",
};
static struct ClassLibrary *class_lib[C_NUM];
static Class *class_ptr[C_NUM];
static struct ListBrowserIFace *ILB;
struct ListBrowserIFace *bbf_ILB;
static struct ChooserIFace *ICH;
static struct LayoutIFace *ILO;
static struct KeymapIFace *IKM;
static struct Library *KeymapLib;

struct Library *bbf_class_lib(int c) { return (struct Library *)class_lib[c]; }

Class *cls(int c)
{
    if (c == C_MENU) return NULL;
    if (!class_ptr[c]) {
        class_lib[c] = IIntuition->OpenClass(class_names[c], 0, &class_ptr[c]);
        if (class_lib[c]) {
            if (c == C_LISTBROWSER) bbf_ILB = ILB = (void *)IExec->GetInterface((struct Library *)class_lib[c], "main", 1, NULL);
            if (c == C_CHOOSER) ICH = (void *)IExec->GetInterface((struct Library *)class_lib[c], "main", 1, NULL);
            if (c == C_LAYOUT) ILO = (void *)IExec->GetInterface((struct Library *)class_lib[c], "main", 1, NULL);
        }
    }
    return class_ptr[c];
}

void tg(tags *t, Tag tag, uint32 data)
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

Object *new_obj(int c, tags *t)
{
    tg(t, TAG_DONE, 0);
    Object *o;
    if (c == C_MENU)             /* Intuition's own public class (V54.6), no class library */
        o = IIntuition->NewObjectA(NULL, "menuclass", t->t);
    else {
        Class *k = cls(c);
        o = k ? IIntuition->NewObjectA(k, NULL, t->t) : NULL;
    }
    free(t->t);
    t->t = NULL;
    t->n = t->cap = 0;
    return o;
}

bb_form *forms;
int ending;
static int end_code;
static struct MsgPort *timer_port;
static void box_save(bb_form *f);
static bb_form *modal_top;                /* the form shown with vbModal (input goes only there) */
static struct TimeRequest *timer_master;

char *xstrdup(const char *s)
{
    char *o = malloc(strlen(s) + 1);
    if (o) strcpy(o, s);
    return o;
}

int fire(bb_form *f, const char *ctl, const char *event, int argc, int32_t *args)
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

int fire0(bb_ctl *c, const char *event) { return fire(c->form, c->name, event, 0, NULL); }

/* set a gadget attribute, refreshing it when the window is open */
void set_attr(bb_ctl *c, Tag tag, uint32 v)
{
    struct TagItem t[2] = { { tag, v }, { TAG_DONE, 0 } };
    if (c->form->win && c->kind != AFG_WINDOW)
        IIntuition->SetGadgetAttrsA((struct Gadget *)c->obj, c->form->win, NULL, t);
    else
        IIntuition->SetAttrsA(c->obj, t);
}

uint32 get_attr(bb_ctl *c, Tag tag)
{
    uint32 v = 0;
    IIntuition->GetAttr(tag, c->obj, &v);
    return v;
}

static void canvas_refresh_all(bb_form *f);

void relayout(bb_form *f)
{
    if (f->win && f->winobj) {
        IIntuition->IDoMethod(f->winobj, WM_RETHINK);
        canvas_refresh_all(f);       /* the layout repainted the boxes of canvases and grids */
    }
}

/* --- item lists ------------------------------------------------------------------------- */

void bbf_items_insert(bb_ctl *c, int at, const char *s)
{
    if (c->nitems + 1 > c->capitems) {
        c->capitems = c->capitems ? c->capitems * 2 : 8;
        c->items = realloc(c->items, c->capitems * sizeof *c->items);
        c->msel = realloc(c->msel, c->capitems * sizeof *c->msel);
        c->idata = realloc(c->idata, c->capitems * sizeof *c->idata);
    }
    if (at < 0 || at > c->nitems) at = c->nitems;
    memmove(c->items + at + 1, c->items + at, (c->nitems - at) * sizeof *c->items);
    memmove(c->msel + at + 1, c->msel + at, (c->nitems - at) * sizeof *c->msel);
    memmove(c->idata + at + 1, c->idata + at, (c->nitems - at) * sizeof *c->idata);
    c->items[at] = xstrdup(s);
    c->msel[at] = 0;
    c->idata[at] = 0;
    c->nitems++;
}

static void items_remove(bb_ctl *c, int at)
{
    free(c->items[at]);
    memmove(c->items + at, c->items + at + 1, (c->nitems - at - 1) * sizeof *c->items);
    memmove(c->msel + at, c->msel + at + 1, (c->nitems - at - 1) * sizeof *c->msel);
    memmove(c->idata + at, c->idata + at + 1, (c->nitems - at - 1) * sizeof *c->idata);
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
            n = bbf_list_node(c, i);
        else if (c->kind == AFG_CHOOSER && ICH)
            n = ICH->AllocChooserNode(CNA_CopyText, TRUE, CNA_Text, c->items[i], TAG_DONE);
        if (n) IExec->AddTail(&c->labels, n);
    }
}

static void list_changed(bb_ctl *c)
{
    Tag lt = c->kind == AFG_LISTBROWSER ? LISTBROWSER_Labels : CHOOSER_Labels;
    if (c->kind == AFG_LISTBROWSER) bbf_list_sync_sel(c);
    set_attr(c, lt, ~0u);
    build_nodes(c);
    if (c->sel >= c->nitems) c->sel = c->nitems - 1;
    if (c->kind == AFG_CHOOSER && c->sel < 0 && c->nitems) c->sel = 0;
    /* (not LISTBROWSER_Selected on a multi-select list: it would clear every selection) */
    struct TagItem t[3] = { { lt, (uint32)&c->labels },
                            { c->kind == AFG_LISTBROWSER ? (c->multi ? TAG_IGNORE : LISTBROWSER_Selected) : CHOOSER_Selected, (uint32)c->sel },
                            { TAG_DONE, 0 } };
    if (c->form->win) IIntuition->SetGadgetAttrsA((struct Gadget *)c->obj, c->form->win, NULL, t);
    else IIntuition->SetAttrsA(c->obj, t);
}

/* --- building --------------------------------------------------------------------------- */

void bbf_gadget_tags(bb_ctl *c, tags *t)
{
    tg(t, GA_ID, c->gid);
    tg(t, GA_RelVerify, TRUE);
    if (afg_get_bool(c->node, "disabled")) tg(t, GA_Disabled, TRUE);
    if (afg_has(c->node, "hint")) {
        c->hint = xstrdup(afg_get(c->node, "hint"));
        tg(t, GA_HintInfo, (uint32)c->hint);
    }
}

/* Per-keystroke Change: string.gadget sends no IDCMPUPDATE while typing, and window.class
 * gets no IntuiTicks while a gadget is active. An edit hook runs (in input.device's task)
 * after every edit: it marks the control and signals the program's task, whose event loop
 * then compares the text and fires Change. */
static struct Task *main_task;
static int8 edit_sigbit = -1;

static uint32 edit_hook_func(struct Hook *h, struct SGWork *sgw, uint32 *msg)
{
    if (*msg != SGH_KEY) return 0;
    bb_ctl *c = h->h_Data;
    if (sgw->Actions & (SGA_USE | SGA_END)) {
        c->edited = 1;
        if (main_task && edit_sigbit >= 0) IExec->Signal(main_task, 1u << edit_sigbit);
    }
    return ~0u;
}

static bb_ctl *ctl_for(bb_form *f, afg_node *n)
{
    for (int i = 0; i < f->nctls; i++)
        if (f->ctls[i]->node == n) return f->ctls[i];
    return NULL;
}

Object *bbf_build(bb_form *f, afg_node *n);
#define build bbf_build

Object *bbf_build(bb_form *f, afg_node *n)
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
            if (!afg_takes_space(n->children[i]->kind)) continue;     /* timer, commondialog */
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
        /* a tabs page: its title is the tab's label, not a frame title inside the page */
        int page = n->parent && n->parent->kind == AFG_TABS;
        if (!page && afg_has(n, "title") && !strcmp(frame, "none")) frame = "group";
        if (!strcmp(frame, "group")) tg(&t, LAYOUT_BevelStyle, BVS_GROUP);
        else if (!strcmp(frame, "button")) tg(&t, LAYOUT_BevelStyle, BVS_BUTTON);
        else if (!strcmp(frame, "field")) tg(&t, LAYOUT_BevelStyle, BVS_FIELD);
        if (afg_has(n, "title") && !page) {
            tg(&t, LAYOUT_Label, (uint32)afg_get(n, "title"));
            afg_set(n, "_framed", "1");      /* what the layout was given (layout.gadget doesn't say) */
        }
        if (afg_get_bool(n, "even")) tg(&t, LAYOUT_EvenSize, TRUE);
        if (afg_get_bool(n, "splitter")) tg(&t, LAYOUT_WeightBar, TRUE);     /* draggable bars between children */
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
            else if (ch->kind == AFG_STATUSBAR || ch->kind == AFG_TOOLBAR)
                /* bars keep their own height (width for a bar in a row): the rest of the
                   window goes to the other controls */
                tg(&t, n->kind == AFG_HLAYOUT ? CHILD_WeightedWidth : CHILD_WeightedHeight, 0);
            if (afg_has(ch, "minwidth")) tg(&t, CHILD_MinWidth, afg_get_int(ch, "minwidth"));
            if (afg_has(ch, "minheight")) tg(&t, CHILD_MinHeight, afg_get_int(ch, "minheight"));
        }
        free(kids);
        o = new_obj(C_LAYOUT, &t);
        break;
    }
    case AFG_BUTTON:
        bbf_gadget_tags(c, &t);
        if (afg_has(n, "image") && (c->img = bbf_load_image(afg_get(n, "image"), afg_get(n, "selimage")))) {
            /* a picture button; with a text, the picture and the text side by side (label.image) */
            if (*afg_get(n, "text")) {
                tags lt = { 0 };
                tg(&lt, LABEL_Image, (uint32)c->img);
                tg(&lt, LABEL_Text, (uint32)afg_get(n, "text"));
                c->selimg = new_obj(C_LABEL, &lt);
                tg(&t, BUTTON_RenderImage, (uint32)(c->selimg ? c->selimg : c->img));
            } else
                tg(&t, BUTTON_RenderImage, (uint32)c->img);
        } else
            tg(&t, GA_Text, (uint32)afg_get(n, "text"));
        o = new_obj(C_BUTTON, &t);
        break;
    case AFG_STRING:
        bbf_gadget_tags(c, &t);
        tg(&t, GA_TabCycle, TRUE);
        if (c != &tmp) {
            if (!main_task) main_task = IExec->FindTask(NULL);
            if (edit_sigbit < 0) edit_sigbit = IExec->AllocSignal(-1);
            c->edit_hook.h_Entry = (HOOKFUNC)edit_hook_func;
            c->edit_hook.h_Data = c;
            tg(&t, STRINGA_EditHook, (uint32)&c->edit_hook);
        }
        tg(&t, STRINGA_MaxChars, afg_get_int(n, "maxchars"));
        tg(&t, STRINGA_TextVal, (uint32)afg_get(n, "text"));
        c->text = xstrdup(afg_get(n, "text"));
        o = new_obj(C_STRING, &t);
        break;
    case AFG_INTEGER:
        bbf_gadget_tags(c, &t);
        tg(&t, GA_TabCycle, TRUE);
        tg(&t, INTEGER_Minimum, afg_get_int(n, "min"));
        tg(&t, INTEGER_Maximum, afg_get_int(n, "max"));
        tg(&t, INTEGER_Number, afg_get_int(n, "value"));
        tg(&t, INTEGER_Arrows, TRUE);
        o = new_obj(C_INTEGER, &t);
        break;
    case AFG_CHECKBOX:
        bbf_gadget_tags(c, &t);
        tg(&t, GA_Text, (uint32)afg_get(n, "text"));
        tg(&t, CHECKBOX_Checked, afg_get_bool(n, "checked"));
        o = new_obj(C_CHECKBOX, &t);
        break;
    case AFG_CHOOSER:
        cls(C_CHOOSER);
        bbf_gadget_tags(c, &t);
        c->sel = c->nitems ? afg_get_int(n, "selected") : -1;
        if (c->sel >= c->nitems) c->sel = c->nitems - 1;
        build_nodes(c);
        tg(&t, CHOOSER_PopUp, TRUE);
        tg(&t, CHOOSER_Labels, (uint32)&c->labels);
        tg(&t, CHOOSER_Selected, c->sel);
        o = new_obj(C_CHOOSER, &t);
        break;
    case AFG_RADIO:
        bbf_gadget_tags(c, &t);
        c->labelarray = calloc(c->nitems + 1, sizeof *c->labelarray);
        for (int i = 0; i < c->nitems; i++) c->labelarray[i] = c->items[i];
        c->sel = afg_get_int(n, "selected");
        tg(&t, RADIOBUTTON_LabelArray, (uint32)c->labelarray);
        tg(&t, RADIOBUTTON_Selected, c->sel);
        o = new_obj(C_RADIO, &t);
        break;
    case AFG_SLIDER:
        bbf_gadget_tags(c, &t);
        tg(&t, ICA_TARGET, ICTARGET_IDCMP);
        c->lastval = afg_get_int(n, "level");
        tg(&t, SLIDER_Min, afg_get_int(n, "min"));
        tg(&t, SLIDER_Max, afg_get_int(n, "max"));
        tg(&t, SLIDER_Level, afg_get_int(n, "level"));
        tg(&t, SLIDER_Orientation, afg_get_bool(n, "vertical") ? SLIDER_VERTICAL : SLIDER_HORIZONTAL);
        o = new_obj(C_SLIDER, &t);
        break;
    case AFG_SCROLLER:
        bbf_gadget_tags(c, &t);
        tg(&t, ICA_TARGET, ICTARGET_IDCMP);
        c->lastval = afg_get_int(n, "top");
        tg(&t, SCROLLER_Total, afg_get_int(n, "total"));
        tg(&t, SCROLLER_Visible, afg_get_int(n, "visible"));
        tg(&t, SCROLLER_Top, afg_get_int(n, "top"));
        tg(&t, SCROLLER_Orientation, afg_get_bool(n, "vertical") ? SORIENT_VERT : SORIENT_HORIZ);
        o = new_obj(C_SCROLLER, &t);
        break;
    case AFG_LISTBROWSER:
        cls(C_LISTBROWSER);
        bbf_gadget_tags(c, &t);
        c->sel = -1;
        bbf_list_setup(c, &t);
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
    case AFG_CANVAS:             /* canvas: a space of the canvas size; canvas_os4.c blits into it */
        tg(&t, SPACE_MinWidth, afg_get_int(n, "width") * (afg_get_int(n, "scale") > 1 ? afg_get_int(n, "scale") : 1));
        tg(&t, SPACE_MinHeight, afg_get_int(n, "height") * (afg_get_int(n, "scale") > 1 ? afg_get_int(n, "scale") : 1));
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
        bbf_gadget_tags(c, &t);
        tg(&t, GETFILE_TitleText, (uint32)afg_get(n, "title"));
        if (afg_has(n, "pattern")) {
            tg(&t, GETFILE_Pattern, (uint32)afg_get(n, "pattern"));
            tg(&t, GETFILE_DoPatterns, TRUE);
        }
        if (afg_get_bool(n, "save")) tg(&t, GETFILE_DoSaveMode, TRUE);
        o = new_obj(C_GETFILE, &t);
        break;
    case AFG_TEXTEDITOR:
        bbf_gadget_tags(c, &t);
        tg(&t, ICA_TARGET, ICTARGET_IDCMP);    /* CursorMove / Change while typing */
        if (afg_get_bool(n, "fixedfont")) tg(&t, GA_TEXTEDITOR_FixedFont, TRUE);
        if (afg_has(n, "text")) tg(&t, GA_TEXTEDITOR_Contents, (uint32)afg_get(n, "text"));
        o = new_obj(C_TEXTEDITOR, &t);
        break;
    default:
        o = bbf_ext_build(f, n, c, &t);       /* the kinds of docs/ui.md (ui_*.c) */
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
        for (int i = 0; i < k; i++) bbf_items_insert(c, -1, v[i]);
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

/* Timers keep a fixed timeline, as VB's do: each tick is due one Interval after the previous
   one was due, not after its handler returned (that made the period Interval + handler time).
   A tick that is due already fires at once; more than a period behind, the timeline restarts
   from now (no burst of catch-up ticks). */
static void timer_arm(bb_ctl *c)
{
    double now, wait;
    long us;
    if (c->pending || !c->enabled || c->interval <= 0 || !c->form->loaded) return;
    if (!timers_init()) return;
    if (!c->tio)
        c->tio = IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Duplicate, timer_master, TAG_DONE);
    if (!c->tio) return;
    now = bb_plat_seconds();
    if (c->deadline < now - c->interval / 1000.0) c->deadline = now;
    wait = c->deadline - now;
    us = wait > 0 ? (long)(wait * 1e6) : 0;
    c->tio->Request.io_Command = TR_ADDREQUEST;
    c->tio->Time.Seconds = us / 1000000;
    c->tio->Time.Microseconds = us % 1000000;
    IExec->SendIO((struct IORequest *)c->tio);
    c->pending = 1;
}

/* (re)start: the first tick one Interval from now */
static void timer_send(bb_ctl *c)
{
    if (c->pending) return;
    c->deadline = bb_plat_seconds() + c->interval / 1000.0;
    timer_arm(c);
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
                /* the next tick is due one Interval after this one was (the handler may have
                   restarted the timer: then it is pending already) */
                if (!c->pending) {
                    c->deadline += c->interval / 1000.0;
                    timer_arm(c);
                }
            }
        }
}

/* --- forms ------------------------------------------------------------------------------ */

static void form_free(bb_form *f)
{
    for (int i = 0; i < f->nctls; i++) {
        bb_ctl *c = f->ctls[i];
        if (c->kind == AFG_CANVAS) bb_canvas_ctl_gone(c);     /* canvas */
        if (c->kind == AFG_TIMER) {
            timer_stop(c);
            if (c->tio) IExec->FreeSysObject(ASOT_IOREQUEST, c->tio);
        }
    }
    box_save(f);
    bbf_app_window_close(f);
    if (f->win && f->curptr != POINTERTYPE_NORMAL) IIntuition->SetWindowPointer(f->win, TAG_DONE);
    if (f->winobj) {
        if (f->win) IIntuition->IDoMethod(f->winobj, WM_CLOSE);
        IIntuition->DisposeObject(f->winobj);    /* disposes the layout and gadgets too */
    }
    bbf_menus_free(f);                           /* menu strips: ours to dispose */
    for (int i = 0; i < f->nctls; i++) {
        bb_ctl *c = f->ctls[i];
        bbf_ext_free(c);
        free_nodes(c);
        for (int k = 0; k < c->nitems; k++) free(c->items[k]);
        free(c->items);
        free(c->msel);
        free(c->idata);
        if (c->colinfo && ILB) ILB->FreeLBColumnInfo(c->colinfo);
        if (c->coltitles) {
            for (int k = 0; k < c->ncols; k++) free(c->coltitles[k]);
            free(c->coltitles);
        }
        free(c->labelarray);
        free(c->tagstr);
        free(c->hint);
        free(c->text);
        free(c->extra);
        free(c->ctxmenu);
        free(c);
    }
    free(f->ctls);
    free(f->self.tagstr);
    free(f->self.text);
    free(f->self.ctxmenu);
    free(f->ret);
    free(f->file);
    afg_free(f->afg);
    free(f);
}

/* window.class calls this inside WM_HANDLEINPUT: only note the gadget, events come after */
static uint32 idcmp_func(struct Hook *h, Object *wobj, struct IntuiMessage *m)
{
    (void)wobj;
    bb_form *f = h->h_Data;
    if (m->Class == IDCMP_IDCMPUPDATE) {
        uint16 gid = (uint16)IUtility->GetTagData(GA_ID, 0, (struct TagItem *)m->IAddress);
        for (int i = 0; i < f->nupd; i++)
            if (f->upd[i] == gid) return 0;
        if (gid && f->nupd < 32) f->upd[f->nupd++] = gid;
    } else if (m->Class == IDCMP_MOUSEBUTTONS || m->Class == IDCMP_MOUSEMOVE ||
               (m->Class == IDCMP_EXTENDEDMOUSE && m->Code == IMSGCODE_INTUIWHEELDATA)) {
        /* moves are merged: only the newest position of a run counts */
        if (m->Class == IDCMP_MOUSEMOVE && f->nmq && f->mq[f->nmq - 1].mcls == IDCMP_MOUSEMOVE) f->nmq--;
        if (f->nmq < 32) {
            int i = f->nmq++;
            f->mq[i].mcls = m->Class;
            f->mq[i].code = m->Code;
            f->mq[i].qual = m->Qualifier;
            f->mq[i].x = m->MouseX;
            f->mq[i].y = m->MouseY;
            f->mq[i].wheel = m->Class == IDCMP_EXTENDEDMOUSE ? ((struct IntuiWheelData *)m->IAddress)->WheelY : 0;
            f->mq[i].secs = m->Seconds;
            f->mq[i].micros = m->Micros;
        }
    }
    return 0;
}

/* --- mouse events: <canvas>_MouseDown/MouseUp/MouseMove/DblClick/MouseWheel, Form_Mouse* --- */

static const char *const mouse_events[] = { "MouseDown", "MouseUp", "MouseMove", "MouseWheel", "DblClick", NULL };

static int wants_mouse(bb_form *f, bb_ctl *c)
{
    if (afg_get(f->afg, "name")[0] == '_') return 0;     /* the runtime's own requesters */
    for (int i = 0; mouse_events[i]; i++)
        if (!f->has || f->has(f->ud, f, c->name, mouse_events[i])) return 1;
    return 0;
}

static int ctl_has(bb_form *f, bb_ctl *c, const char *ev) { return !f->has || f->has(f->ud, f, c->name, ev); }

/* the canvas under a window position (NULL = the form itself) */
static bb_ctl *mouse_target(bb_form *f, int x, int y)
{
    for (int i = 0; i < f->nctls; i++) {
        bb_ctl *c = f->ctls[i];
        if ((c->kind != AFG_CANVAS && c->kind != AFG_GRID) || !c->obj || !c->visible || !c->name[0]) continue;
        struct Gadget *g = (struct Gadget *)c->obj;
        if (x >= g->LeftEdge && y >= g->TopEdge && x < g->LeftEdge + g->Width && y < g->TopEdge + g->Height) return c;
    }
    return NULL;
}

/* window pixels -> the canvas's pixels (it is centred in its box and maybe scaled up) */
static void canvas_xy(bb_ctl *c, int wx, int wy, int32_t *x, int32_t *y)
{
    struct Gadget *g = (struct Gadget *)c->obj;
    int w = g->Width, h = g->Height, s = 1;
    bb_canvas_ctl_geometry(c, &w, &h, &s);
    int ox = g->Width > w * s ? (g->Width - w * s) / 2 : 0, oy = g->Height > h * s ? (g->Height - h * s) / 2 : 0;
    int dx = wx - g->LeftEdge - ox, dy = wy - g->TopEdge - oy;
    *x = dx >= 0 ? dx / s : -((-dx + s - 1) / s);
    *y = dy >= 0 ? dy / s : -((-dy + s - 1) / s);
}

int bbf_vb_shift(uint32 q);
#define vb_shift bbf_vb_shift

/* RightButton canvases: the right button goes to the canvas (not the menus) while the pointer
   is over it, the classic paint program behaviour (WFLG_RMBTRAP set only there) */
static void rmb_trap(bb_form *f, int x, int y)
{
    if (!f->win) return;
    bb_ctl *c = f->buttons ? f->capture : mouse_target(f, x, y);
    int want = c && c->kind == AFG_CANVAS && c->rmb;
    if (want != ((f->win->Flags & WFLG_RMBTRAP) != 0)) {
        IExec->Forbid();
        if (want) f->win->Flags |= WFLG_RMBTRAP;
        else f->win->Flags &= ~WFLG_RMBTRAP;
        IExec->Permit();
    }
}

/* MousePointer: VB's values -> pointer types (V53.37 SetWindowPointer WA_PointerType) */
static int vb_pointer(int v)
{
    switch (v) {
    case 2: return POINTERTYPE_CROSS;           /* vbCrosshair */
    case 3: return POINTERTYPE_TEXT;            /* vbIbeam */
    case 11: return POINTERTYPE_BUSY;           /* vbHourglass */
    case 15: return POINTERTYPE_SCROLLALL;      /* vbSizeAll */
    default:
        /* 100 + an OS4 pointer type: pen 135, rubber 137, zoom in 133, hand 111 ... */
        if (v >= 100 && v <= 100 + POINTERTYPE_SMUDGE) {
            int t = v - 100;
            /* pen, rotate, rubber, select and smudge are intuition.library 54.21: older ones get the cross */
            struct Library *ib = (struct Library *)IntuitionBase;
            if (t >= POINTERTYPE_PEN && (ib->lib_Version < 54 || (ib->lib_Version == 54 && ib->lib_Revision < 21)))
                t = POINTERTYPE_CROSS;
            return t;
        }
        return POINTERTYPE_NORMAL;              /* vbDefault, vbArrow */
    }
}

void bbf_update_pointer(bb_form *f, int x, int y)
{
    if (!f->win) return;
    int v = f->self.ptr;
    if (x >= 0) {
        bb_ctl *c = f->buttons ? f->capture : mouse_target(f, x, y);
        if (c && c->kind == AFG_CANVAS && c->ptr) v = c->ptr;
    } else if (!f->mouse_wanted)
        /* no mouse reports in this window: a canvas pointer covers the whole window */
        for (int i = 0; i < f->nctls; i++)
            if (f->ctls[i]->kind == AFG_CANVAS && f->ctls[i]->ptr) v = f->ctls[i]->ptr;
    int t = vb_pointer(v);
    if (t != f->curptr) {
        f->curptr = t;
        IIntuition->SetWindowPointer(f->win, WA_PointerType, t, TAG_DONE);
    }
}

static void mouse_events_handle(bb_form *f)
{
    for (int k = 0; k < f->nmq && f->loaded && !ending; k++) {
        typeof(f->mq[0]) e = f->mq[k];
        int bit = 0, up = 0;
        if (e.mcls == IDCMP_MOUSEBUTTONS) {
            int b = e.code & ~IECODE_UP_PREFIX;
            bit = b == IECODE_LBUTTON ? 1 : b == IECODE_RBUTTON ? 2 : b == IECODE_MBUTTON ? 4 : 0;
            up = (e.code & IECODE_UP_PREFIX) != 0;
            if (!bit) continue;
        }
        bb_ctl *c = f->capture && f->buttons ? f->capture : mouse_target(f, e.x, e.y);
        if (e.mcls == IDCMP_MOUSEMOVE) {
            rmb_trap(f, e.x, e.y);
            bbf_update_pointer(f, e.x, e.y);
        }
        if (e.mcls == IDCMP_MOUSEBUTTONS && !up)
            for (int i = 0; i < f->nctls; i++)       /* a click elsewhere takes the focus from grids */
                if (f->ctls[i]->kind == AFG_GRID && f->ctls[i] != c) bbf_grid_blur(f->ctls[i]);
        if (c && c->kind == AFG_GRID) {
            /* the grid handles its own mouse (cells, selection, editing) */
            if (e.mcls == IDCMP_MOUSEBUTTONS && bit == 1) {
                if (!up) { f->buttons |= 1; f->capture = c; }
                else { f->buttons &= ~1; if (!f->buttons) f->capture = NULL; }
                bbf_grid_mouse(c, !up, up, 0, e.x, e.y, e.qual, e.secs, e.micros);
            } else if (e.mcls == IDCMP_MOUSEMOVE)
                bbf_grid_mouse(c, 0, 0, 1, e.x, e.y, e.qual, e.secs, e.micros);
            continue;
        }
        const char *name = c ? c->name : "Form";
        int32_t a[4] = { 0, vb_shift(e.qual), 0, 0 };
        if (c) {
            canvas_xy(c, e.x, e.y, &a[2], &a[3]);
            c->mx = a[2];
            c->my = a[3];
        }
        else {
            a[2] = e.x - (f->win ? f->win->BorderLeft : 0);
            a[3] = e.y - (f->win ? f->win->BorderTop : 0);
        }
        if (e.mcls == IDCMP_MOUSEBUTTONS && !up) {
            f->buttons |= bit;
            f->capture = c;
            f->movex = a[2];
            f->movey = a[3];
            a[0] = bit;
            fire(f, name, "MouseDown", 4, a);
            if (bit == 1) {
                if (f->last_down == c && IIntuition->DoubleClick(f->last_secs, f->last_micros, e.secs, e.micros)) {
                    fire(f, name, "DblClick", 0, NULL);
                    f->last_down = NULL;
                } else {
                    f->last_down = c;
                    f->last_secs = e.secs;
                    f->last_micros = e.micros;
                }
            }
        } else if (e.mcls == IDCMP_MOUSEBUTTONS) {
            /* Intuition may not report the last move before the release: report it, so a
               drag always ends where the button went up */
            if (a[2] != f->movex || a[3] != f->movey) {
                int32_t m[4] = { f->buttons, a[1], a[2], a[3] };
                f->movex = a[2];
                f->movey = a[3];
                fire(f, name, "MouseMove", 4, m);
                if (ending || !f->loaded) break;
            }
            f->buttons &= ~bit;
            a[0] = bit;
            fire(f, name, "MouseUp", 4, a);
            if (!f->buttons) f->capture = NULL;
        } else if (e.mcls == IDCMP_MOUSEMOVE) {
            /* only while a button is down, unless the canvas asks for every move (mousemove=1) */
            if (!f->buttons && !(c ? afg_get_bool(c->node, "mousemove") : afg_get_bool(f->afg, "mousemove"))) continue;
            a[0] = f->buttons;
            f->movex = a[2];
            f->movey = a[3];
            fire(f, name, "MouseMove", 4, a);
        } else {
            int32_t d[1] = { -e.wheel };        /* VB: positive = away from the user */
            if (c ? ctl_has(f, c, "MouseWheel") : 1) fire(f, name, "MouseWheel", 1, d);
        }
    }
    f->nmq = 0;
}

/* remember=1: the window's box in ENVARC:<App.Title>/windows/<form> (and ENV:) */
static char *box_path(bb_form *f, const char *dir)
{
    bb_str *t = bb_app_title();
    char *p = malloc(strlen(dir) + strlen(bb_str_ptr(t)) + strlen(bb_form_name(f)) + 16);
    sprintf(p, "%s%s/windows/%s", dir, bb_str_ptr(t), bb_form_name(f));
    bb_str_release(t);
    return p;
}

static int box_load(bb_form *f, int *b)
{
    for (int arch = 0; arch < 2; arch++) {
        char *p = box_path(f, arch ? "ENVARC:" : "ENV:");
        FILE *fp = fopen(p, "r");
        free(p);
        if (!fp) continue;
        int n = fscanf(fp, "%d %d %d %d", &b[0], &b[1], &b[2], &b[3]);
        fclose(fp);
        if (n == 4 && b[2] > 20 && b[3] > 10) return 1;
    }
    return 0;
}

static void box_save(bb_form *f)
{
    if (!f->win || !afg_get_bool(f->afg, "remember")) return;
    for (int arch = 0; arch < 2; arch++) {
        char *p = box_path(f, arch ? "ENVARC:" : "ENV:");
        /* the directories, then the file */
        for (char *q = strchr(p, ':') + 1; *q; q++)
            if (*q == '/') {
                *q = 0;
                IDOS->CreateDirTree(p);
                *q = '/';
                break;
            }
        char *last = strrchr(p, '/');
        *last = 0;
        BPTR l = IDOS->CreateDirTree(p);
        if (l) IDOS->UnLock(l);
        *last = '/';
        FILE *fp = fopen(p, "w");
        if (fp) {
            fprintf(fp, "%d %d %d %d\n", f->win->LeftEdge, f->win->TopEdge, f->win->Width, f->win->Height);
            fclose(fp);
        }
        free(p);
    }
}

static struct MsgPort *iconify_port;     /* WINDOW_AppPort of forms with iconify=1 */

bb_form *bb_form_load(const char *afg_text, const char *file, bb_form_event_fn fn, bb_form_has_event_fn has,
                      void *ud, char *err, int errlen)
{
    char e[200];
    afg_node *a = afg_parse(afg_text, e, sizeof e);
    if (!a) {
        snprintf(err, errlen, "%s:%s", file ? file : "form", e + (strncmp(e, "line ", 5) ? 0 : 5));
        return NULL;
    }
    bbf_localize(a);                     /* "$12:Open..." texts from the catalog */
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
    int box[4], remembered = afg_get_bool(a, "remember") && box_load(f, box);
    int tool = afg_get_bool(a, "toolwindow");
    tg(&t, WA_DragBar, TRUE);
    tg(&t, WA_CloseGadget, TRUE);
    tg(&t, WA_DepthGadget, !tool);
    tg(&t, WA_Activate, TRUE);
    tg(&t, WA_SizeGadget, afg_get_bool(a, "resizable") && !tool);
    if (remembered) {
        tg(&t, WA_Left, box[0]);
        tg(&t, WA_Top, box[1]);
        tg(&t, WA_Width, box[2]);
        tg(&t, WA_Height, box[3]);
    } else {
        if (w > 0) tg(&t, WA_InnerWidth, w);
        if (h > 0) tg(&t, WA_InnerHeight, h);
    }
    if (afg_get_bool(a, "iconify")) {
        if (!iconify_port) iconify_port = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
        if (iconify_port) {
            tg(&t, WINDOW_IconifyGadget, TRUE);
            tg(&t, WINDOW_AppPort, (uint32)iconify_port);
            tg(&t, WINDOW_IconTitle, (uint32)afg_get(a, "title"));
        }
    }
    for (int i = 0; i < f->nctls; i++) {
        if (f->ctls[i]->kind == AFG_CANVAS && f->ctls[i]->name[0] && wants_mouse(f, f->ctls[i])) f->mouse_wanted = 1;
        if (f->ctls[i]->kind == AFG_GRID) f->mouse_wanted = 1;
        if (f->ctls[i]->kind == AFG_CANVAS) {
            f->ctls[i]->rmb = afg_get_bool(f->ctls[i]->node, "rmb");
            f->ctls[i]->fill = afg_get_bool(f->ctls[i]->node, "fill");
            if (f->ctls[i]->rmb) f->mouse_wanted = 1;
            f->ctls[i]->ptr = afg_get_int(f->ctls[i]->node, "mousepointer");
            if (f->ctls[i]->ptr) f->mouse_wanted = 1;
        }
    }
    if (wants_mouse(f, &f->self)) f->mouse_wanted = 1;
    if (f->mouse_wanted) tg(&t, WA_ReportMouse, TRUE);
    tg(&t, WA_IDCMP, IDCMP_GADGETUP | IDCMP_CLOSEWINDOW | IDCMP_RAWKEY | IDCMP_NEWSIZE | IDCMP_ACTIVEWINDOW |
                         IDCMP_INACTIVEWINDOW | IDCMP_MENUPICK |
                         (f->mouse_wanted ? IDCMP_MOUSEBUTTONS | IDCMP_MOUSEMOVE | IDCMP_EXTENDEDMOUSE : 0));
    if (!bbf_menus_build(f, &t)) {
        free(t.t);
        IIntuition->DisposeObject(f->root);
        f->root = NULL;
        snprintf(err, errlen, "%s:%d: can't create the menus (needs intuition.library 54.6)", f->file, a->line);
        form_free(f);
        return NULL;
    }
    if (!remembered) tg(&t, WINDOW_Position, WPOS_CENTERSCREEN);
    tg(&t, WINDOW_GadgetHelp, TRUE);
    f->idcmp_hook.h_Entry = (HOOKFUNC)idcmp_func;
    f->idcmp_hook.h_Data = f;
    tg(&t, WINDOW_IDCMPHook, (uint32)&f->idcmp_hook);
    tg(&t, WINDOW_IDCMPHookBits, IDCMP_IDCMPUPDATE |
                                     (f->mouse_wanted ? IDCMP_MOUSEBUTTONS | IDCMP_MOUSEMOVE | IDCMP_EXTENDEDMOUSE : 0));
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

/* canvas: show every canvas control's last picture again (window opened or resized) */
static void canvas_refresh_all(bb_form *f)
{
    for (int i = 0; i < f->nctls; i++) {
        bb_ctl *c = f->ctls[i];
        if (c->kind == AFG_CANVAS && c->fill && c->obj && f->win) {
            /* fill=1: the picture takes the control's whole box; <id>_Resize redraws it */
            struct Gadget *g = (struct Gadget *)c->obj;
            int w = 0, h = 0, sc = 1;
            bb_canvas_ctl_geometry(c, &w, &h, &sc);
            if (sc < 1) sc = 1;
            if (bb_canvas_ctl_fit(c, g->Width / sc, g->Height / sc)) fire0(c, "Resize");
        }
        if (c->kind == AFG_CANVAS) bb_canvas_ctl_refresh(c);
        if (f->ctls[i]->kind == AFG_GRID) bbf_grid_refresh(f->ctls[i]);
    }
}

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
    f->curptr = POINTERTYPE_NORMAL;
    bbf_app_window_open(f);
    if (f->self.ptr || !f->mouse_wanted) bbf_update_pointer(f, -1, -1);
    f->lastw = f->win->Width;
    f->lasth = f->win->Height;
    canvas_refresh_all(f);       /* canvas */
    fire(f, "Form", "Activate", 0, NULL);
    fire(f, "Form", "Resize", 0, NULL);
    return 0;
}

int bb_form_hide(bb_form *f)
{
    if (!f->loaded) return 364;
    box_save(f);
    bbf_app_window_close(f);
    if (f->win && f->curptr != POINTERTYPE_NORMAL) IIntuition->SetWindowPointer(f->win, TAG_DONE);   /* back to the default first */
    f->curptr = POINTERTYPE_NORMAL;
    if (f->win) IIntuition->IDoMethod(f->winobj, WM_CLOSE);
    f->win = NULL;
    f->iconified = 0;
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

int ret_str(bb_ctl *c, bb_fval *out, const char *s)
{
    char **slot = c->form ? &c->form->ret : &c->ret_buf;
    char *n = xstrdup(s ? s : "");      /* s may be the old string */
    free(*slot);
    *slot = n;
    out->type = BB_FV_STR;
    out->s = n;
    return 0;
}

int ret_int(bb_fval *out, int32 v)
{
    out->type = BB_FV_INT;
    out->i = v;
    return 0;
}

int32 vint(const bb_fval *v) { return v->type == BB_FV_INT ? v->i : (v->s ? atol(v->s) : 0); }

const char *vstr(const bb_fval *v, char *buf)
{
    if (v->type == BB_FV_STR) return v->s ? v->s : "";
    sprintf(buf, "%ld", (long)v->i);
    return buf;
}

int vb_bool(int b) { return b ? -1 : 0; }

static int has_list(afg_kind k) { return k == AFG_CHOOSER || k == AFG_RADIO || k == AFG_LISTBROWSER; }

static char *editor_text(bb_ctl *c)
{
    /* DoGadgetMethodA: the message by pointer (DoGadgetMethod takes the method id and its
       arguments inline) */
    STRPTR s = (STRPTR)IIntuition->DoGadgetMethodA((struct Gadget *)c->obj, c->form->win, NULL,
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
    if (IS("WindowState")) return ret_int(out, f->iconified ? 1 : 0);
    if (IS("Width")) return ret_int(out, w ? w->Width - w->BorderLeft - w->BorderRight : afg_get_int(f->afg, "width"));
    if (IS("Height")) return ret_int(out, w ? w->Height - w->BorderTop - w->BorderBottom : afg_get_int(f->afg, "height"));
    if (IS("Left")) return ret_int(out, w ? w->LeftEdge : 0);
    if (IS("Top")) return ret_int(out, w ? w->TopEdge : 0);
    if (IS("ContextMenu")) return ret_str(&f->self, out, f->self.ctxmenu ? f->self.ctxmenu : afg_get(f->afg, "contextmenu"));
    if (IS("ContextControl")) return ret_str(&f->self, out, f->ctx_control ? f->ctx_control : "");
    if (IS("OLEDropMode")) return ret_int(out, f->dropmode || afg_get_bool(f->afg, "dropfiles"));
    if (IS("MousePointer")) return ret_int(out, f->self.ptr);
    if (IS("PointerType")) return ret_int(out, f->curptr);     /* the OS4 pointer type shown now (tests) */
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
    if (IS("ContextMenu")) {
        free(f->self.ctxmenu);
        f->self.ctxmenu = xstrdup(vstr(v, buf));
        return 0;
    }
    if (IS("MousePointer")) {
        f->self.ptr = vint(v);
        bbf_update_pointer(f, -1, -1);
        return 0;
    }
    if (IS("OLEDropMode")) {
        f->dropmode = vint(v) != 0;
        if (f->dropmode) bbf_app_window_open(f);
        else bbf_app_window_close(f);
        return 0;
    }
    if (IS("WindowState")) {
        int want = vint(v) == 1;
        if (want && f->win && afg_get_bool(f->afg, "iconify")) {
            box_save(f);
            bbf_app_window_close(f);
            IIntuition->IDoMethod(f->winobj, WM_ICONIFY);
            f->win = NULL;
            f->iconified = 1;
        } else if (!want && f->iconified) {
            f->win = (struct Window *)IIntuition->IDoMethod(f->winobj, WM_OPEN);
            f->iconified = 0;
            if (f->win) {
                bbf_app_window_open(f);
                canvas_refresh_all(f);
            }
        }
        return 0;
    }
    if (IS("Name") || IS("ContextControl")) return 383;
    return 438;
}

int bb_ctl_get(bb_ctl *c, const char *prop, int index, bb_fval *out)
{
    out->type = BB_FV_NONE;
    if (!c->form) return bbf_ext_get(c, prop, index, out);       /* a CommonDialog object */
    if (c->kind == AFG_WINDOW) return form_get(c->form, prop, out);
    if (!c->form->loaded) return 364;
    struct Gadget *g = (struct Gadget *)c->obj;
    afg_kind k = c->kind;
    if (IS("Name")) return ret_str(c, out, c->name);
    if (IS("Tag")) return ret_str(c, out, c->tagstr);
    if (k == AFG_MENU) return c->dead ? 364 : bbf_menu_get(c, prop, out);
    if (!c->obj && k != AFG_TIMER) return bbf_ext_get(c, prop, index, out);      /* tool, commondialog */
    if (IS("ContextMenu")) return ret_str(c, out, c->ctxmenu ? c->ctxmenu : afg_get(c->node, "contextmenu"));
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
        if (k == AFG_LISTBROWSER) {
            int e = bbf_list_get(c, prop, index, out);
            if (e != 438) return e;
        }
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
        if (IS("Text") || IS("Caption")) return ret_str(c, out, c->text);
        if (IS("ShowPercent")) return ret_int(out, vb_bool(get_attr(c, FUELGAUGE_Percent)));
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
        return bbf_editor_get(c, prop, out);
    default:
        return bbf_ext_get(c, prop, index, out);
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
    if (!c->form) return bbf_ext_set(c, prop, index, v);
    if (c->kind == AFG_WINDOW) return form_set(c->form, prop, v);
    if (!c->form->loaded) return 364;
    afg_kind k = c->kind;
    if (IS("Name")) return 383;
    if (IS("Tag")) {
        free(c->tagstr);
        c->tagstr = xstrdup(vstr(v, buf));
        return 0;
    }
    if (k == AFG_MENU) return c->dead ? 364 : bbf_menu_set(c, prop, v);
    if (!c->obj && k != AFG_TIMER) return bbf_ext_set(c, prop, index, v);
    if (IS("ContextMenu")) {
        free(c->ctxmenu);
        c->ctxmenu = xstrdup(vstr(v, buf));
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
        if (k == AFG_LISTBROWSER) {
            int e = bbf_list_set(c, prop, index, v);
            if (e != 438) return e;
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
            c->lastval = vint(v);       /* the gadget's notification isn't a user Scroll */
            set_attr(c, SLIDER_Level, vint(v));
            fire0(c, "Change");
            return 0;
        }
        if (IS("Min")) { set_attr(c, SLIDER_Min, vint(v)); return 0; }
        if (IS("Max")) { set_attr(c, SLIDER_Max, vint(v)); return 0; }
        break;
    case AFG_SCROLLER:
        if (IS("Value")) { c->lastval = vint(v); set_attr(c, SCROLLER_Top, vint(v)); fire0(c, "Change"); return 0; }
        if (IS("Max")) { set_attr(c, SCROLLER_Total, vint(v)); return 0; }
        if (IS("LargeChange")) { set_attr(c, SCROLLER_Visible, vint(v)); return 0; }
        break;
    case AFG_FUELGAUGE:
        if (IS("Text") || IS("Caption")) {
            /* a label instead of the percentage (GA_Text is a format string: % doubled) */
            const char *src = vstr(v, buf);
            char *o = malloc(strlen(src) * 2 + 1), *d = o;
            for (; *src; src++) {
                if (*src == '%') *d++ = '%';
                *d++ = *src;
            }
            *d = 0;
            free(c->text);
            c->text = o;
            set_attr(c, FUELGAUGE_Percent, *o ? FALSE : TRUE);
            set_attr(c, GA_Text, *o ? (uint32)o : 0);
            return 0;
        }
        if (IS("ShowPercent")) { set_attr(c, FUELGAUGE_Percent, vint(v) != 0); return 0; }
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
        return bbf_editor_set(c, prop, v);
    default:
        return bbf_ext_set(c, prop, index, v);
    }
    return 438;
}

int bb_ctl_get2(bb_ctl *c, const char *prop, int i, int j, bb_fval *out)
{
    out->type = BB_FV_NONE;
    if (!c->form || !c->form->loaded) return 364;
    return bbf_get2(c, prop, i, j, out);
}

int bb_ctl_set2(bb_ctl *c, const char *prop, int i, int j, const bb_fval *v)
{
    if (!c->form || !c->form->loaded) return 364;
    return bbf_set2(c, prop, i, j, v);
}

#undef IS
#define IS(a) (!strcasecmp(method, a))

int bb_ctl_call(bb_ctl *c, const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    char buf[16];
    if (ret) ret->type = BB_FV_NONE;
    if (!c->form) return bbf_ext_call(c, method, argc, argv, ret);
    bb_form *f = c->form;
    if (c->kind == AFG_WINDOW) {
        if (IS("Show")) return bb_form_show(f);
        if (IS("Hide")) return bb_form_hide(f);
        if (IS("Refresh")) { relayout(f); return 0; }
        if (IS("SetFocus")) {
            if (f->win) {
                IIntuition->WindowToFront(f->win);
                IIntuition->ActivateWindow(f->win);
            }
            return 0;
        }
        if (IS("Move")) {
            static const char *const p[4] = { "Left", "Top", "Width", "Height" };
            for (int i = 0; i < argc && i < 4; i++) form_set(f, p[i], &argv[i]);
            return 0;
        }
        return bbf_form_menu_call(f, method, argc, argv, ret);
    }
    if (!f->loaded) return 364;
    if (c->kind == AFG_MENU || c->kind == AFG_TIMER) return 438;
    if (!c->obj) return bbf_ext_call(c, method, argc, argv, ret);
    if (IS("Refresh")) {
        if (f->win) IIntuition->RefreshGList((struct Gadget *)c->obj, f->win, NULL, 1);
        return 0;
    }
    if (IS("SetFocus")) {
        if (f->win && (c->kind == AFG_STRING || c->kind == AFG_INTEGER || c->kind == AFG_TEXTEDITOR))
            IIntuition->IDoMethod(f->winobj, WM_ACTIVATEGADGET, c->obj);
        return 0;
    }
    if (c->kind == AFG_TEXTEDITOR) {
        int e = bbf_editor_call(c, method, argc, argv, ret);
        if (e != 438) return e;
    }
    if (c->kind == AFG_LISTBROWSER) {
        int e = bbf_list_call(c, method, argc, argv, ret);
        if (e != 438) return e;
    }
    if (has_list(c->kind) && c->kind != AFG_RADIO) {
        if (c->kind == AFG_LISTBROWSER) bbf_list_sync_sel(c);   /* before the rows move */
        if (IS("AddItem")) {
            if (argc < 1) return 5;
            int at = argc > 1 ? vint(&argv[1]) : -1;
            if (argc > 1 && (at < 0 || at > c->nitems)) return 5;
            bbf_items_insert(c, at, vstr(&argv[0], buf));
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
    return bbf_ext_call(c, method, argc, argv, ret);
}

/* --- events ----------------------------------------------------------------------------- */

int bbf_last_part;

bb_ctl *bbf_ctl_by_gid(bb_form *f, uint32 gid)
{
    gid &= BBF_GID_MASK;      /* the parts of a control (grid scrollers) carry its id */
    if (gid >= 1 && gid <= (uint32)f->nctls) return f->ctls[gid - 1];
    return NULL;
}

int bbf_vb_key(int raw);
#define vb_key bbf_vb_key
int bbf_vb_key(int raw)
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

int bbf_vb_shift(uint32 q)
{
    int s = 0;
    if (q & (IEQUALIFIER_LSHIFT | IEQUALIFIER_RSHIFT)) s |= 1;
    if (q & IEQUALIFIER_CONTROL) s |= 2;
    if (q & (IEQUALIFIER_LALT | IEQUALIFIER_RALT)) s |= 4;
    if (q & (IEQUALIFIER_LCOMMAND | IEQUALIFIER_RCOMMAND)) s |= 8;
    return s;
}

int bbf_map_key(int raw, uint32 qual)
{
    if (!IKM) {
        KeymapLib = IExec->OpenLibrary("keymap.library", 50);
        if (KeymapLib) IKM = (void *)IExec->GetInterface(KeymapLib, "main", 1, NULL);
    }
    if (!IKM) return 0;
    struct InputEvent ie;
    memset(&ie, 0, sizeof ie);
    ie.ie_Class = IECLASS_RAWKEY;
    ie.ie_Code = raw;
    ie.ie_Qualifier = qual;
    char ch[8];
    return IKM->MapRawKey(&ie, ch, sizeof ch, NULL) == 1 ? (unsigned char)ch[0] : 0;
}

static void raw_key(bb_form *f, int code)
{
    uint32 q = 0;
    IIntuition->GetAttr(WINDOW_Qualifier, f->winobj, &q);
    int up = code & IECODE_UP_PREFIX, raw = code & 0x7F;
    if (raw >= 0x60 && raw <= 0x67) {
        /* qualifier keys: KeyDown/KeyUp with the side-specific code (vbKeyLShift 160,
           vbKeyRShift 161, vbKeyControl 17, vbKeyLMenu 164 / vbKeyRMenu 165 for the Alt keys,
           vbKeyLWin 91 / vbKeyRWin 92 for the Amiga keys, vbKeyCapital 20); the canvas key
           state also gets the generic code (vbKeyShift 16, vbKeyMenu 18, 91 for either Amiga) */
        static const int16 side[8] = { 160, 161, 20, 17, 164, 165, 91, 92 };
        static const int16 generic[8] = { 16, 16, 20, 17, 18, 18, 91, 91 };
        int k = raw - 0x60;
        bb_canvas_key_event(side[k], !up);
        if (k != 2) {
            /* the generic code stays down while the other side's key is still held */
            int other = (k == 0 || k == 4 || k == 6) ? k + 1 : (k == 1 || k == 5 || k == 7) ? k - 1 : -1;
            uint32 oq = other == 0 ? IEQUALIFIER_LSHIFT : other == 1 ? IEQUALIFIER_RSHIFT : other == 4 ? IEQUALIFIER_LALT
                      : other == 5 ? IEQUALIFIER_RALT : other == 6 ? IEQUALIFIER_LCOMMAND : other == 7 ? IEQUALIFIER_RCOMMAND : 0;
            if (!up || !(q & oq)) bb_canvas_key_event(generic[k], !up);
        }
        int32_t a[2] = { side[k], vb_shift(q) };
        fire(f, "Form", up ? "KeyUp" : "KeyDown", 2, a);
        return;
    }
    if (raw == 0x5F && !up && bbf_app_help_key(f)) return;     /* Help with App.HelpFile set */
    if (!up)
        for (int i = 0; i < f->nctls; i++)       /* a grid with the focus takes the keys */
            if (f->ctls[i]->kind == AFG_GRID && bbf_grid_focused(f->ctls[i]) && bbf_grid_key(f->ctls[i], raw, q)) return;
    int32_t a[2] = { vb_key(raw), vb_shift(q) };
    bb_canvas_key_event(a[0], !up);      /* canvas: Canvas.KeyDown(k) */
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
    case AFG_SLIDER:
    case AFG_SCROLLER:
        c->lastval = (int32)get_attr(c, c->kind == AFG_SLIDER ? SLIDER_Level : SCROLLER_Top);
        for (int i = 0; i < f->nupd;)           /* the release is a Change, not another Scroll */
            if (f->upd[i] == c->gid) memmove(f->upd + i, f->upd + i + 1, (--f->nupd - i) * sizeof *f->upd);
            else i++;
        fire0(c, "Change");
        break;
    case AFG_INTEGER:
    case AFG_TEXTEDITOR:
        fire0(c, "Change");
        break;
    case AFG_LISTBROWSER: {
        uint32 rel = get_attr(c, LISTBROWSER_RelEvent);
        if (rel & LBRE_TITLECLICK) {
            int32_t col = bbf_list_title_click(c);
            fire(f, c->name, "ColumnClick", 1, &col);
            break;
        }
        c->sel = (int32)get_attr(c, LISTBROWSER_Selected);
        fire0(c, "Click");
        if (!ending && (rel & LBRE_DOUBLECLICK)) fire0(c, "DblClick");
        break;
    }
    case AFG_GETFILE:
        if (IIntuition->IDoMethod(c->obj, GFILE_REQUEST, f->win)) fire0(c, "Change");
        break;
    default:
        bbf_ext_gadget_up(f, c, code);
        break;
    }
}

static void updates(bb_form *f)
{
    while (f->nupd && f->loaded && !ending) {
        uint16 gid = f->upd[0];
        memmove(f->upd, f->upd + 1, --f->nupd * sizeof *f->upd);
        bb_ctl *c = bbf_ctl_by_gid(f, gid);
        if (!c) continue;
        if (c->kind == AFG_GRID) {
            bbf_grid_update(f, c, gid >> BBF_PART_SHIFT);
            continue;
        }
        if (c->kind == AFG_STRING) {
            const char *now = (const char *)get_attr(c, STRINGA_TextVal);
            if (!now) now = "";
            if (!c->text || strcmp(c->text, now)) {
                free(c->text);
                c->text = xstrdup(now);
                fire0(c, "Change");
            }
        } else if (c->kind == AFG_TEXTEDITOR) {
            bbf_editor_update(c);
        } else if (c->kind == AFG_SLIDER || c->kind == AFG_SCROLLER) {
            int32 v = (int32)get_attr(c, c->kind == AFG_SLIDER ? SLIDER_Level : SCROLLER_Top);
            if (v != c->lastval) {
                c->lastval = v;
                fire0(c, "Scroll");
            }
        }
    }
}

void bbf_handle_form(bb_form *f)
{
    uint32 result;
    uint16 code = 0;
    while (f->loaded && (f->win || f->iconified) && !ending &&
           (result = IIntuition->IDoMethod(f->winobj, WM_HANDLEINPUT, &code)) != WMHI_LASTMSG) {
        uint32 cl = result & WMHI_CLASSMASK;
        if (cl == WMHI_UNICONIFY) {
            f->win = (struct Window *)IIntuition->IDoMethod(f->winobj, WM_OPEN);
            f->iconified = 0;
            if (f->win) {
                bbf_app_window_open(f);
                canvas_refresh_all(f);
                fire(f, "Form", "Resize", 0, NULL);
            }
            continue;
        }
        if (cl == WMHI_ICONIFY) {
            box_save(f);
            bbf_app_window_close(f);
            IIntuition->IDoMethod(f->winobj, WM_ICONIFY);
            f->win = NULL;
            f->iconified = 1;
            fire(f, "Form", "Resize", 0, NULL);
            continue;
        }
        /* not the form on top of a modal stack: no input (a busy pointer is shown) */
        if (modal_top && f != modal_top && cl != WMHI_NEWSIZE) continue;
        if (!f->enabled && cl != WMHI_NEWSIZE) continue;
        switch (result & WMHI_CLASSMASK) {
        case WMHI_CLOSEWINDOW:
            unload(f, 0);
            break;
        case WMHI_GADGETUP: {
            bbf_last_part = (result & WMHI_GADGETMASK) >> BBF_PART_SHIFT;
            bb_ctl *c = bbf_ctl_by_gid(f, result & WMHI_GADGETMASK);
            if (c && c->kind != AFG_GRID)
                for (int i = 0; i < f->nctls; i++)
                    if (f->ctls[i]->kind == AFG_GRID) bbf_grid_blur(f->ctls[i]);
            if (c) gadget_up(f, c, code);
            break;
        }
        case WMHI_RAWKEY:
            raw_key(f, result & WMHI_KEYMASK);
            break;
        case WMHI_MENUPICK:
            bbf_menus_pick(f);
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
                canvas_refresh_all(f);       /* canvas */
                fire(f, "Form", "Resize", 0, NULL);
            }
            break;
        }
        updates(f);
        if (f->nmq) mouse_events_handle(f);
    }
    updates(f);
    if (f->nmq) mouse_events_handle(f);
}

static void check_edits(bb_form *f)
{
    for (int i = 0; i < f->nctls && f->loaded && !ending; i++) {
        bb_ctl *c = f->ctls[i];
        if (c->kind != AFG_STRING || !c->edited) continue;
        c->edited = 0;
        if (f->nupd < 32) f->upd[f->nupd++] = (uint16)c->gid;
    }
    updates(f);
}

static void edits_handle(void)
{
    for (bb_form *f = forms; f && !ending; f = f->next)
        if (f->loaded) check_edits(f);
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
    if (edit_sigbit >= 0) sigs |= 1u << edit_sigbit;
    if (iconify_port) sigs |= 1u << iconify_port->mp_SigBit;
    sigs |= bbf_app_sigmask();          /* AppWindow/AppIcon messages, the ARexx port, help */
    uint32 got = wait ? IExec->Wait(sigs) : IExec->SetSignal(0, sigs) & sigs;
    bbf_app_signals(got);
    if (edit_sigbit >= 0 && (got & (1u << edit_sigbit))) edits_handle();
    if (got & SIGBREAKF_CTRL_C) {
        ending = 1;
        end_code = 0;
    }
    if (timer_port && (got & (1u << timer_port->mp_SigBit))) timers_handle();
    for (bb_form *f = forms; f && !ending; f = f->next)
        if (f->loaded && (f->win || f->iconified)) bbf_handle_form(f);
}

/* Show vbModal */
int bb_form_show_modal(bb_form *f)
{
    bb_form *prev = modal_top;
    int e = bb_form_show(f);
    if (e) return e;
    modal_top = f;
    for (bb_form *o = forms; o; o = o->next)
        if (o != f && o->win) IIntuition->SetAttrs(o->winobj, WA_BusyPointer, TRUE, TAG_DONE);
    f->modal_depth++;
    while (!ending && f->loaded && (f->win || f->iconified)) pump(1);
    f->modal_depth--;
    modal_top = prev;
    for (bb_form *o = forms; o; o = o->next)
        if (o->win && o != prev) IIntuition->SetAttrs(o->winobj, WA_BusyPointer, prev ? TRUE : !o->enabled, TAG_DONE);
    if (prev && prev->win) IIntuition->ActivateWindow(prev->win);
    return 0;
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
    if (edit_sigbit >= 0) IExec->FreeSignal(edit_sigbit);
    edit_sigbit = -1;
    if (iconify_port) IExec->FreeSysObject(ASOT_PORT, iconify_port);
    iconify_port = NULL;
    modal_top = NULL;
    if (IKM) IExec->DropInterface((struct Interface *)IKM);
    if (KeymapLib) IExec->CloseLibrary(KeymapLib);
    IKM = NULL;
    KeymapLib = NULL;
    bbf_ext_cleanup();
    bbf_app_cleanup();
    if (ILB) IExec->DropInterface((struct Interface *)ILB);
    if (ICH) IExec->DropInterface((struct Interface *)ICH);
    if (ILO) IExec->DropInterface((struct Interface *)ILO);
    ILB = bbf_ILB = NULL;
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

struct Window *bbf_front_window(void)
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
    struct Window *w = bbf_front_window();
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

/* InputBox: a small form of its own (requester.class's string requester doesn't end on
 * Return on OS 4.1 FE, whatever REQS_ReturnEnds says). Modal: the other forms' windows get
 * a busy pointer and their events wait until it closes. */
struct ibox {
    int done, ok, focused;
};

static int ibox_event(void *ud, bb_form *f, const char *ctl, const char *event, int argc, int32_t *args)
{
    struct ibox *b = ud;
    if (getenv("BB_DEBUG_FORMS")) printf("# inputbox event %s_%s %ld\n", ctl, event, argc ? (long)args[0] : 0L);
    if ((!strcmp(ctl, "ok") && !strcmp(event, "Click")) ||
        (!strcmp(ctl, "answer") && !strcmp(event, "KeyPress") && argc && args[0] == 13))
        b->done = b->ok = 1;
    else if (!strcmp(ctl, "cancel") && !strcmp(event, "Click"))
        b->done = 1;
    else if (!strcmp(ctl, "Form") && !strcmp(event, "Unload"))
        b->done = 1;
    else if (!strcmp(ctl, "Form") && !strcmp(event, "KeyDown") && argc && args[0] == 27)
        b->done = 1;
    else if (!strcmp(ctl, "Form") && !strcmp(event, "Activate") && !b->focused) {
        /* typing goes to the field; only once: activating it again selects its text */
        b->focused = 1;
        bb_ctl_call(bb_form_ctl(f, "answer"), "SetFocus", 0, NULL, NULL);
    }
    return 0;
}

static void afg_quote(char *out, size_t n, const char *s)
{
    size_t o = 0;
    if (o < n - 1) out[o++] = '"';
    for (; *s && o < n - 3; s++) {
        if (*s == '"' || *s == '\\') out[o++] = '\\';
        if (*s == '\n') {
            out[o++] = '\\';
            out[o++] = 'n';
            continue;
        }
        out[o++] = *s;
    }
    out[o++] = '"';
    out[o] = 0;
}

void bbf_form_discard(bb_form *f)
{
    f->fn = NULL;
    f->loaded = 0;
    for (bb_form **pp = &forms; *pp; pp = &(*pp)->next)
        if (*pp == f) {
            *pp = f->next;
            break;
        }
    form_free(f);
}

/* a requester with the program's own buttons ("_Save|_Discard|_Cancel"): returns the number of
   the button chosen, 1 = leftmost (requester.class numbers them 1, 2, ... and the last 0) */
int bb_ui_request(const char *prompt, const char *buttons, const char *title, int icon)
{
    int img = REQIMAGE_DEFAULT;
    switch (icon & 0x70) {
    case 16: img = REQIMAGE_ERROR; break;
    case 32: img = REQIMAGE_QUESTION; break;
    case 48: img = REQIMAGE_WARNING; break;
    case 64: img = REQIMAGE_INFO; break;
    }
    int n = 1;
    for (const char *p = buttons; p && *p; p++) n += *p == '|';
    tags t = { 0 };
    tg(&t, REQ_Type, REQTYPE_INFO);
    tg(&t, REQ_TitleText, (uint32)(title && *title ? title : prog_name()));
    tg(&t, REQ_BodyText, (uint32)(prompt ? prompt : ""));
    tg(&t, REQ_GadgetText, (uint32)(buttons && *buttons ? buttons : "_OK"));
    tg(&t, REQ_Image, img);
    uint32 r = open_req(&t);
    return r == 0 ? n : (int)r;
}

char *bb_ui_inputbox(const char *prompt, const char *title, const char *def)
{
    size_t plen = strlen(prompt ? prompt : "") + strlen(def ? def : "") + strlen(title ? title : "");
    size_t cap = plen * 2 + 1024;
    char *afg = malloc(cap), *q = malloc(plen * 2 + 64);
    if (!afg || !q) {
        free(afg);
        free(q);
        return NULL;
    }
    afg_quote(q, plen * 2 + 64, title && *title ? title : prog_name());
    int n = snprintf(afg, cap, "window name=_inputbox title=%s width=320 resizable=0\nvlayout id=root\n", q);
    /* one label per line of the prompt */
    const char *p = prompt ? prompt : "";
    do {
        const char *nl = strchr(p, '\n');
        size_t len = nl ? (size_t)(nl - p) : strlen(p);
        char *line = malloc(len + 2);
        memcpy(line, p, len);
        line[len] = 0;
        if (!len) strcpy(line, " ");
        afg_quote(q, plen * 2 + 64, line);
        free(line);
        n += snprintf(afg + n, cap - n, "  label text=%s weight=0\n", q);
        p = nl ? nl + 1 : NULL;
    } while (p);
    afg_quote(q, plen * 2 + 64, def ? def : "");
    n += snprintf(afg + n, cap - n,
                  "  string id=answer text=%s maxchars=1023 weight=0\n"
                  "  hlayout weight=0 even=1\n    button id=ok text=_OK\n    space\n    button id=cancel text=_Cancel\n", q);
    free(q);

    struct ibox box = { 0, 0 };
    char err[200];
    bb_form *f = bb_form_load(afg, "InputBox", ibox_event, NULL, &box, err, sizeof err);
    free(afg);
    if (!f) return NULL;
    for (bb_form *o = forms; o; o = o->next)
        if (o != f && o->win) IIntuition->SetAttrs(o->winobj, WA_BusyPointer, TRUE, TAG_DONE);
    char *result = NULL;
    if (bb_form_show(f) == 0) {
        bb_ctl *a = bb_form_ctl(f, "answer");
        IIntuition->ActivateWindow(f->win);
        uint32 sig = 0;
        IIntuition->GetAttr(WINDOW_SigMask, f->winobj, &sig);
        int was_ending = ending;
        uint32 esig = edit_sigbit >= 0 ? 1u << edit_sigbit : 0;
        while (!box.done && f->loaded && f->win && !ending) {
            uint32 got = IExec->Wait(sig | esig | SIGBREAKF_CTRL_C);
            if (got & SIGBREAKF_CTRL_C) break;
            if (got & esig) check_edits(f);
            bbf_handle_form(f);
        }
        if (box.ok) {
            const char *t = (const char *)get_attr(a, STRINGA_TextVal);
            result = xstrdup(t ? t : "");
        }
        ending = was_ending;
    }
    bbf_form_discard(f);    /* free it now, without events */
    for (bb_form *o = forms; o; o = o->next)
        if (o->win) IIntuition->SetAttrs(o->winobj, WA_BusyPointer, !o->enabled, TAG_DONE);
    return result;
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

/* canvas: the window and the control's box inside it, for canvas_os4.c */
int bb_ctl_os_window(bb_ctl *c, void **window, int *x, int *y, int *w, int *h)
{
    struct Window *win = c->form->win;
    struct Gadget *g = (struct Gadget *)c->obj;
    if (!win || !g || !c->form->loaded) return 0;
    *window = win;
    *x = g->LeftEdge;
    *y = g->TopEdge;
    *w = g->Width;
    *h = g->Height;
    return 1;
}
