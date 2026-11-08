/* forms_test - the ReAction forms runtime, from C: a form from .afg text opens, properties
 * read and write, a timer fires, a real mouse click (injected through input.device) on a
 * button calls its Click event, typed keys reach a string gadget's Change event, a list click
 * sets ListIndex, Unload can be cancelled. Prints TAP-like lines and PASS/FAIL. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include <exec/exec.h>
#include <devices/input.h>
#include <devices/inputevent.h>
#include <intuition/intuition.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/intuition.h>
#include <dos/dostags.h>
#include <intuition/intuitionbase.h>

#include "bb_forms.h"

/* run from a background CLI (run >NIL:) the default stack is only a few KB */
static const char __attribute__((used)) stack_cookie[] = "$STACK:262144";

static const char *afg =
    "# AmiForge GUI\n"
    "window name=main title=\"Boing forms test\" width=300 height=200\n"
    "vlayout id=root\n"
    "  hlayout title=\"Input\" frame=group\n"
    "    string id=name label=\"Name\" text=\"Amiga\"\n"
    "    checkbox id=fast text=\"_Fast\"\n"
    "  hlayout\n"
    "    listbrowser id=list items=\"Zero|One|Two\" minheight=60\n"
    "    vlayout weight=0\n"
    "      chooser id=pick items=\"Red|Green|Blue\" selected=1\n"
    "      slider id=speed min=0 max=10 level=3\n"
    "      fuelgauge id=gauge level=20\n"
    "  label id=status text=\"Ready\"\n"
    "  button id=ok text=\"_OK\" weight=0\n"
    "  timer id=tick interval=300\n";

static int fails, n;
static void check(int ok, const char *what)
{
    n++;
    printf("%s %d - %s\n", ok ? "ok" : "not ok", n, what);
    if (!ok) fails++;
}

static bb_form *form;
static int loads, clicks, changes, keypress13, listclicks, timers, unloads, cancel_next = 1, step;
static int scrolls, speedchanges, keydown = -1, keypress = -1, shift = -1;
static char log_[2048];

static bb_ctl *C(const char *name) { return strcasecmp(name, "Form") ? bb_form_ctl(form, name) : bb_form_self(form); }

static int geti(const char *ctl, const char *prop)
{
    bb_fval v;
    int e = bb_ctl_get(C(ctl), prop, -1, &v);
    return e ? -9999 : v.i;
}

static const char *gets_(const char *ctl, const char *prop, int idx)
{
    static char buf[256];
    bb_fval v;
    if (bb_ctl_get(C(ctl), prop, idx, &v)) return "<error>";
    snprintf(buf, sizeof buf, "%s", v.s);
    return buf;
}

static void seti(const char *ctl, const char *prop, int i)
{
    bb_fval v = { BB_FV_INT, i, NULL };
    bb_ctl_set(C(ctl), prop, -1, &v);
}

static void sets(const char *ctl, const char *prop, const char *s)
{
    bb_fval v = { BB_FV_STR, 0, s };
    bb_ctl_set(C(ctl), prop, -1, &v);
}

/* --- input injection ---------------------------------------------------------------------- */

static struct MsgPort *iport;
static struct IOStdReq *ireq;

static void inject(struct InputEvent *ie)
{
    ireq->io_Command = IND_WRITEEVENT;
    ireq->io_Data = ie;
    ireq->io_Length = sizeof *ie;
    IExec->DoIO((struct IORequest *)ireq);
}

/* The guest is shared: input is only injected when the target window is active on the
 * front screen, so nothing typed or clicked can reach the user's programs. */
static struct Window *find_window(const char *title)
{
    struct IntuitionBase *ib = (struct IntuitionBase *)IntuitionBase;
    struct Window *found = NULL;
    uint32 lock = IIntuition->LockIBase(0);
    struct Screen *front = ib->FirstScreen;
    for (struct Window *w = front ? front->FirstWindow : NULL; w; w = w->NextWindow)
        if (w->Title && !strcmp((const char *)w->Title, title)) found = w;
    IIntuition->UnlockIBase(lock);
    return found;
}

static int make_active(const char *title)
{
    for (int tries = 0; tries < 10; tries++) {
        struct Window *w = find_window(title);
        if (!w) return 0;                 /* not on the front screen: leave it alone */
        if (((struct IntuitionBase *)IntuitionBase)->ActiveWindow == w) return 1;
        IIntuition->ActivateWindow(w);
        IDOS->Delay(10);
    }
    return 0;
}

#define MAIN_TITLE "Boing forms test - running"
static int ready(void)
{
    int ok = make_active(MAIN_TITLE);
    if (!ok) printf("# skipped: the test window isn't active on the front screen\n");
    return ok;
}

static void click_at(int x, int y, int twice)
{
    struct Screen *scr = IIntuition->LockPubScreen(NULL);
    struct IEPointerPixel pp = { scr, { x, y } };
    struct InputEvent ie;
    for (int k = 0; k <= twice; k++) {
        memset(&ie, 0, sizeof ie);
        ie.ie_Class = IECLASS_NEWPOINTERPOS;
        ie.ie_SubClass = IESUBCLASS_PIXEL;
        ie.ie_EventAddress = &pp;
        inject(&ie);
        memset(&ie, 0, sizeof ie);
        ie.ie_Class = IECLASS_RAWMOUSE;
        ie.ie_Code = IECODE_LBUTTON;
        inject(&ie);
        ie.ie_Code = IECODE_LBUTTON | IECODE_UP_PREFIX;
        inject(&ie);
    }
    IIntuition->UnlockPubScreen(NULL, scr);
}

static void pointer(struct Screen *scr, int x, int y)
{
    struct IEPointerPixel pp = { scr, { x, y } };
    struct InputEvent ie;
    memset(&ie, 0, sizeof ie);
    ie.ie_Class = IECLASS_NEWPOINTERPOS;
    ie.ie_SubClass = IESUBCLASS_PIXEL;
    ie.ie_EventAddress = &pp;
    inject(&ie);
}

static void button(int up)
{
    struct InputEvent ie;
    memset(&ie, 0, sizeof ie);
    ie.ie_Class = IECLASS_RAWMOUSE;
    ie.ie_Code = IECODE_LBUTTON | (up ? IECODE_UP_PREFIX : 0);
    inject(&ie);
}

/* drag inside a control from fraction fx0 to fx1 of its width */
static void drag_ctl(const char *name, int fx0, int fx1)
{
    int x, y, w, h;
    if (!ready()) return;
    if (!bb_ctl_screen_box(C(name), &x, &y, &w, &h)) return;
    struct Screen *scr = IIntuition->LockPubScreen(NULL);
    pointer(scr, x + w * fx0 / 100, y + h / 2);
    button(0);
    for (int i = 1; i <= 8; i++) {
        pointer(scr, x + w * (fx0 + (fx1 - fx0) * i / 8) / 100, y + h / 2);
        IDOS->Delay(2);
    }
    button(1);
    IIntuition->UnlockPubScreen(NULL, scr);
}

/* keys typed by a separate process while this one sits in a requester */
static int later_keys[16], nlater, later_delay;
static struct Task *parent;
static void later_entry(void)
{
    int active = 0;
    struct MsgPort *p = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    struct IOStdReq *r = IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Size, sizeof(struct IOStdReq),
                                                   ASOIOR_ReplyPort, p, TAG_DONE);
    if (r && !IExec->OpenDevice("input.device", 0, (struct IORequest *)r, 0)) {
        IDOS->Delay(later_delay);
        for (int t = 0; t < 30 && !active; t++) {
            active = make_active("forms_test");     /* the requester / InputBox (program name) */
            if (!active) IDOS->Delay(10);
        }
        if (!active) IExec->Signal(parent, SIGBREAKF_CTRL_C);   /* ends the InputBox */
        IDOS->Delay(15);    /* let the string gadget take the input */
        for (int i = 0; active && i < nlater; i++) {
            if (((struct IntuitionBase *)IntuitionBase)->ActiveWindow != find_window("forms_test")) break;
            struct InputEvent ie;
            memset(&ie, 0, sizeof ie);
            ie.ie_Class = IECLASS_RAWKEY;
            ie.ie_Code = later_keys[i];
            r->io_Command = IND_WRITEEVENT;
            r->io_Data = &ie;
            r->io_Length = sizeof ie;
            IExec->DoIO((struct IORequest *)r);
            ie.ie_Code |= IECODE_UP_PREFIX;
            IExec->DoIO((struct IORequest *)r);
            IDOS->Delay(5);
        }
        IExec->CloseDevice((struct IORequest *)r);
    }
    if (r) IExec->FreeSysObject(ASOT_IOREQUEST, r);
    if (p) IExec->FreeSysObject(ASOT_PORT, p);
}

static void keys_later(int delay, const int *k, int n)
{
    later_delay = delay;
    parent = IExec->FindTask(NULL);
    nlater = n;
    memcpy(later_keys, k, n * sizeof *k);
    IDOS->CreateNewProcTags(NP_Entry, later_entry, NP_Name, "bb forms_test keys", NP_Child, TRUE, TAG_DONE);
}

static void click_ctl(const char *name, int dy, int twice)
{
    int x, y, w, h;
    if (!ready()) return;
    if (!bb_ctl_screen_box(C(name), &x, &y, &w, &h)) return;
    click_at(x + w / 2, dy >= 0 ? y + dy : y + h / 2, twice);
}

static int key_checked = 1;
static void key(int raw)
{
    struct InputEvent ie;
    if (key_checked && !ready()) return;
    memset(&ie, 0, sizeof ie);
    ie.ie_Class = IECLASS_RAWKEY;
    ie.ie_Code = raw;
    inject(&ie);
    ie.ie_Code = raw | IECODE_UP_PREFIX;
    inject(&ie);
    IDOS->Delay(6);         /* typing speed: one keystroke per IntuiTick or so */
}

/* --- the events --------------------------------------------------------------------------- */

static void script(void);

static int on_event(void *ud, bb_form *f, const char *ctl, const char *ev, int argc, int32_t *args)
{
    (void)ud;
    (void)f;
    char line[80];
    snprintf(line, sizeof line, "%s_%s ", ctl, ev);
    if (strlen(log_) + strlen(line) < sizeof log_ - 1) strcat(log_, line);
    if (!strcasecmp(ctl, "Form") && !strcasecmp(ev, "Load")) loads++;
    if (!strcasecmp(ctl, "ok") && !strcasecmp(ev, "Click")) {
        clicks++;
        sets("status", "Caption", "Clicked");
    }
    if (!strcasecmp(ctl, "name") && !strcasecmp(ev, "Change")) changes++;
    if (!strcasecmp(ctl, "name") && !strcasecmp(ev, "KeyPress") && argc == 1 && args[0] == 13) keypress13++;
    if (!strcasecmp(ctl, "list") && !strcasecmp(ev, "Click")) listclicks++;
    if (!strcasecmp(ctl, "speed") && !strcasecmp(ev, "Scroll")) scrolls++;
    if (!strcasecmp(ctl, "speed") && !strcasecmp(ev, "Change")) speedchanges++;
    if (!strcasecmp(ctl, "Form") && !strcasecmp(ev, "KeyDown")) {
        keydown = args[0];
        shift = args[1];
    }
    if (!strcasecmp(ctl, "Form") && !strcasecmp(ev, "KeyPress")) keypress = args[0];
    if (!strcasecmp(ctl, "Form") && !strcasecmp(ev, "Unload")) {
        unloads++;
        if (cancel_next) {
            args[0] = -1;     /* Cancel = True */
            cancel_next = 0;
        }
    }
    if (!strcasecmp(ctl, "tick") && !strcasecmp(ev, "Timer")) {
        timers++;
        script();
    }
    return 0;
}

/* one step per timer tick, so the window has drawn and the injected input is handled */
static void script(void)
{
    switch (step++) {
    case 0:
        check(timers == 1, "the timer fired");
        click_ctl("ok", -1, 0);
        break;
    case 1:
        check(clicks == 1, "a click on the OK button called ok_Click");
        check(!strcmp(gets_("status", "Caption", -1), "Clicked"), "the Click sub changed the label's Caption");
        bb_ctl_call(C("name"), "SetFocus", 0, NULL, NULL);
        break;
    case 2:
        /* the string gadget is active: select all (Amiga-X clears in OS4? use Backspace x5) */
        for (int i = 0; i < 5; i++) key(0x41);
        key(0x25);   /* h */
        key(0x17);   /* i */
        key(0x44);   /* Return */
        break;
    case 3:
        check(!strcmp(gets_("name", "Text", -1), "hi"), "typing replaced the text: name.Text = \"hi\"");
        printf("# name_Change count %d\n", changes);
        check(changes >= 7, "name_Change on every keystroke (code once + 5 Backspaces + h + i)");
        check(keypress13 >= 1, "name_KeyPress(13) on Return");
        click_ctl("list", 6, 0);           /* first row */
        break;
    case 4:
        check(listclicks >= 1, "list_Click on a row");
        check(geti("list", "ListIndex") == 0, "list.ListIndex = 0 after clicking the first row");
        check(!strcmp(gets_("list", "Text", -1), "Zero"), "list.Text = \"Zero\"");
        drag_ctl("speed", 70, 20);
        break;
    case 5:
        check(scrolls >= 1, "dragging the slider fires speed_Scroll");
        check(speedchanges >= 2, "releasing it fires speed_Change");
        check(geti("speed", "Value") < 7, "the slider moved left");
        key(0x20);                          /* "a", no gadget active */
        break;
    case 6:
        check(keydown == 65 && shift == 0, "Form_KeyDown(vbKeyA = 65, 0)");
        check(keypress == 97, "Form_KeyPress(97 = \"a\")");
        seti("fast", "Visible", 0);
        check(geti("fast", "Visible") == 0, "fast.Visible = False");
        seti("fast", "Visible", 1);
        if (ready()) {           /* requesters only while we have the front screen */
            int k[1] = { 0x36 };            /* N: the requester's _No */
            keys_later(60, k, 1);
            check(bb_ui_msgbox("Boing forms test: MsgBox", 4 + 32, NULL) == 7, "MsgBox vbYesNo: N gives vbNo (7)");
            int k2[3] = { 0x35, 0x20, 0x44 };   /* b, a, Return */
            keys_later(100, k2, 3);
            char *s = bb_ui_inputbox("Boing forms test: InputBox", NULL, "");
            check(s && !strcmp(s, "ba"), "InputBox: typed \"ba\" + Return");
            printf("# InputBox returned %s%s%s\n", s ? "\"" : "", s ? s : "NULL", s ? "\"" : "");
            free(s);
        }
        bb_form_unload(form);
        check(unloads == 1 && geti("Form", "Visible") == -1, "Form_Unload with Cancel = True kept the form");
        break;
    case 7:
        seti("tick", "Enabled", 0);
        bb_form_unload(form);
        break;
    }
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);   /* progress shows when redirected to a file */
    char err[200];
    iport = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    ireq = IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Size, sizeof(struct IOStdReq), ASOIOR_ReplyPort, iport,
                                     TAG_DONE);
    if (!ireq || IExec->OpenDevice("input.device", 0, (struct IORequest *)ireq, 0)) {
        printf("can't open input.device\nFAIL\n");
        return 20;
    }

    form = bb_form_load(afg, "test.afg", on_event, NULL, NULL, err, sizeof err);
    check(form != NULL, "the form loads");
    if (!form) {
        printf("# %s\nFAIL\n", err);
        return 20;
    }
    check(loads == 1, "Form_Load fired");
    check(!strcmp(bb_form_name(form), "main"), "the form's name is main");

    /* properties before Show */
    check(!strcmp(gets_("name", "Text", -1), "Amiga"), "name.Text from the .afg");
    check(geti("list", "ListCount") == 3, "list.ListCount = 3");
    check(!strcmp(gets_("list", "List", 2), "Two"), "list.List(2) = \"Two\"");
    check(geti("pick", "ListIndex") == 1, "pick.ListIndex = 1 (selected=1)");
    check(!strcmp(gets_("pick", "Text", -1), "Green"), "pick.Text = \"Green\"");
    check(geti("speed", "Value") == 3, "speed.Value = 3");
    check(geti("fast", "Value") == 0, "fast.Value = 0");

    check(bb_form_show(form) == 0, "Show opens the window");
    check(geti("Form", "Visible") == -1, "Me.Visible = True");
    check(geti("Form", "Width") >= 300, "Me.Width >= 300");

    /* properties on the open window */
    sets("name", "Text", "Boing");
    check(!strcmp(gets_("name", "Text", -1), "Boing"), "name.Text = \"Boing\" round trip");
    seti("fast", "Value", 1);
    check(geti("fast", "Value") == 1, "fast.Value = 1 round trip");
    bb_fval item = { BB_FV_STR, 0, "Three" };
    bb_ctl_call(C("list"), "AddItem", 1, &item, NULL);
    check(geti("list", "ListCount") == 4 && !strcmp(gets_("list", "List", 3), "Three"), "list.AddItem \"Three\"");
    bb_fval idx = { BB_FV_INT, 1, NULL };
    bb_ctl_call(C("list"), "RemoveItem", 1, &idx, NULL);
    check(geti("list", "ListCount") == 3 && !strcmp(gets_("list", "List", 1), "Two"), "list.RemoveItem 1");
    seti("speed", "Value", 7);
    check(geti("speed", "Value") == 7, "speed.Value = 7");
    seti("gauge", "Value", 80);
    check(geti("gauge", "Value") == 80, "gauge.Value = 80");
    seti("ok", "Enabled", 0);
    check(geti("ok", "Enabled") == 0, "ok.Enabled = False");
    seti("ok", "Enabled", 1);
    check(geti("ok", "Enabled") == -1, "ok.Enabled = True");
    sets("Form", "Caption", "Boing forms test - running");
    check(!strcmp(gets_("Form", "Caption", -1), "Boing forms test - running"), "Me.Caption round trip");
    bb_fval junk;
    check(bb_ctl_get(C("ok"), "NoSuchProperty", -1, &junk) == 438, "unknown property = error 438");
    check(bb_ctl_get(C("list"), "List", 99, &junk) == 381, "List(99) = error 381");
    check(C("nosuch") == NULL, "unknown control = NULL");

    int r = bb_forms_run();
    check(r == 0, "the event loop ended when the form was unloaded");
    check(unloads == 2, "Form_Unload fired twice (cancelled, then not)");
    check(bb_form_find("main") == NULL, "the form is gone");
    bb_forms_cleanup();
    printf("# events: %s\n", log_);

    IExec->CloseDevice((struct IORequest *)ireq);
    IExec->FreeSysObject(ASOT_IOREQUEST, ireq);
    IExec->FreeSysObject(ASOT_PORT, iport);
    printf("%s (%d/%d)\n", fails ? "FAIL" : "PASS", n - fails, n);
    return fails ? 10 : 0;
}
