/* Shared by the OS4 UI tests: TAP-like checks and input injection through input.device that
 * only happens while the test's own window is the active one on the front screen (the guest is
 * shared with people and other programs). The test defines MAIN_TITLE before including this. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include <exec/exec.h>
#include <devices/input.h>
#include <devices/inputevent.h>
#include <intuition/intuition.h>
#include <intuition/intuitionbase.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/intuition.h>
#include <dos/dostags.h>

static int fails, n;
static void check(int ok, const char *what)
{
    n++;
    printf("%s %d - %s\n", ok ? "ok" : "not ok", n, what);
    if (!ok) fails++;
}

static struct MsgPort *iport;
static struct IOStdReq *ireq;

static int inject_open(void)
{
    iport = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    ireq = IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Size, sizeof(struct IOStdReq), ASOIOR_ReplyPort, iport,
                                     TAG_DONE);
    return ireq && !IExec->OpenDevice("input.device", 0, (struct IORequest *)ireq, 0);
}

static void inject_close(void)
{
    if (ireq) {
        IExec->CloseDevice((struct IORequest *)ireq);
        IExec->FreeSysObject(ASOT_IOREQUEST, ireq);
    }
    if (iport) IExec->FreeSysObject(ASOT_PORT, iport);
}

static void inject(struct InputEvent *ie)
{
    ireq->io_Command = IND_WRITEEVENT;
    ireq->io_Data = ie;
    ireq->io_Length = sizeof *ie;
    IExec->DoIO((struct IORequest *)ireq);
}

/* the window with this title on the Workbench (default public) screen; *front tells whether
   that screen is the frontmost one (mouse injection needs it) */
static struct Window *find_window_ex(const char *title, int *front)
{
    struct IntuitionBase *ib = (struct IntuitionBase *)IntuitionBase;
    struct Window *found = NULL;
    struct Screen *wb = IIntuition->LockPubScreen(NULL);
    uint32 lock = IIntuition->LockIBase(0);
    for (struct Window *w = wb ? wb->FirstWindow : NULL; w; w = w->NextWindow)
        if (w->Title && !strcmp((const char *)w->Title, title)) found = w;
    if (front) *front = ib->FirstScreen == wb;
    IIntuition->UnlockIBase(lock);
    if (wb) IIntuition->UnlockPubScreen(NULL, wb);
    return found;
}

static struct Window *find_window(const char *title) { return find_window_ex(title, NULL); }

static int make_active(const char *title)
{
    for (int tries = 0; tries < 10; tries++) {
        struct Window *w = find_window(title);
        if (!w) return 0;
        if (((struct IntuitionBase *)IntuitionBase)->ActiveWindow == w) return 1;
        IIntuition->ActivateWindow(w);
        IDOS->Delay(10);
    }
    return 0;
}

/* keys go to the active window: they may be injected when ours is active */
static int ready(void)
{
    int ok = make_active(MAIN_TITLE);
    if (!ok) {
        struct IntuitionBase *ib = (struct IntuitionBase *)IntuitionBase;
        printf("# skipped: the test window isn't the active one (active: \"%s\")\n",
               ib->ActiveWindow && ib->ActiveWindow->Title ? (char *)ib->ActiveWindow->Title : "?");
    }
    return ok;
}

/* the mouse also needs the Workbench screen in front, or the clicks land on another screen */
static __attribute__((unused)) int ready_mouse(void)
{
    int front = 0;
    if (!ready()) return 0;
    find_window_ex(MAIN_TITLE, &front);
    if (!front) {
        struct Screen *s = ((struct IntuitionBase *)IntuitionBase)->FirstScreen;
        printf("# skipped: another screen is in front (\"%s\")\n", s && s->DefaultTitle ? (char *)s->DefaultTitle : "?");
    }
    return front;
}

static void pointer(int x, int y)
{
    struct Screen *scr = IIntuition->LockPubScreen(NULL);
    struct IEPointerPixel pp = { scr, { x, y } };
    struct InputEvent ie;
    memset(&ie, 0, sizeof ie);
    ie.ie_Class = IECLASS_NEWPOINTERPOS;
    ie.ie_SubClass = IESUBCLASS_PIXEL;
    ie.ie_EventAddress = &pp;
    inject(&ie);
    IIntuition->UnlockPubScreen(NULL, scr);
}

static void mbutton(int code, int up)
{
    struct InputEvent ie;
    memset(&ie, 0, sizeof ie);
    ie.ie_Class = IECLASS_RAWMOUSE;
    ie.ie_Code = code | (up ? IECODE_UP_PREFIX : 0);
    if (code == IECODE_RBUTTON && !up) ie.ie_Qualifier = IEQUALIFIER_RBUTTON;
    inject(&ie);
}

static __attribute__((unused)) void click_at(int x, int y)
{
    pointer(x, y);
    mbutton(IECODE_LBUTTON, 0);
    mbutton(IECODE_LBUTTON, 1);
}

/* a key with qualifiers (IEQUALIFIER_RCOMMAND for menu shortcuts) */
static void key_q(int raw, int qual)
{
    struct InputEvent ie;
    if (!ready()) return;
    memset(&ie, 0, sizeof ie);
    ie.ie_Class = IECLASS_RAWKEY;
    ie.ie_Code = raw;
    ie.ie_Qualifier = qual;
    inject(&ie);
    ie.ie_Code = raw | IECODE_UP_PREFIX;
    inject(&ie);
    IDOS->Delay(6);
}

static __attribute__((unused)) void key(int raw) { key_q(raw, 0); }

/* keys typed by a separate process while this one sits in a requester (whose window title is
   `title`): only while that window is the active one */
static int later_keys[16], nlater, later_delay;
static const char *later_title;
static struct Task *later_parent;
static volatile int later_done;
static void later_entry(void)
{
    int active = 0;
    struct MsgPort *p = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    struct IOStdReq *r = IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Size, sizeof(struct IOStdReq),
                                                   ASOIOR_ReplyPort, p, TAG_DONE);
    if (r && !IExec->OpenDevice("input.device", 0, (struct IORequest *)r, 0)) {
        IDOS->Delay(later_delay);
        for (int t = 0; t < 30 && !active; t++) {
            active = make_active(later_title);
            if (!active) IDOS->Delay(10);
        }
        if (!active) printf("# keys_later: no active window \"%s\"\n", later_title);
        IDOS->Delay(15);
        for (int i = 0; active && i < nlater; i++) {
            if (((struct IntuitionBase *)IntuitionBase)->ActiveWindow != find_window(later_title)) break;
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
    later_done = 1;
}

static __attribute__((unused)) void keys_later(int delay, const char *title, const int *k, int n)
{
    later_delay = delay;
    later_title = title;
    later_parent = IExec->FindTask(NULL);
    later_done = 0;
    nlater = n;
    memcpy(later_keys, k, n * sizeof *k);
    IDOS->CreateNewProcTags(NP_Entry, later_entry, NP_Name, "bb ui test keys", NP_Child, TRUE, TAG_DONE);
}

static __attribute__((unused)) void keys_later_wait(void)
{
    for (int i = 0; i < 100 && !later_done; i++) IDOS->Delay(5);
}
