/* ptr X Y [click|double|move] [TITLE]   |   ptr reaper - move the pointer to (X, Y) on the front screen and click,
 * through input.device (for driving tests on the guest; QEMU's relative mouse is accelerated).
 * With TITLE, only if a window with that title is on the front screen (it is activated
 * first); otherwise nothing happens and the return code is 5: the guest is shared, input
 * must not reach someone else's program. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/intuition.h>
#include <devices/input.h>
#include <devices/inputevent.h>
#include <intuition/intuitionbase.h>

/* "ptr reaper": close the front Grim Reaper requester by clicking its middle button (Kill)
 * at the bottom centre of its window. Prints the number closed. */
static int reaper(void)
{
    struct IntuitionBase *ib = (struct IntuitionBase *)IntuitionBase;
    struct Window *found = NULL;
    uint32 lock = IIntuition->LockIBase(0);
    for (struct Screen *sc = ib->FirstScreen; sc && !found; sc = sc->NextScreen)
        for (struct Window *w = sc->FirstWindow; w; w = w->NextWindow)
            if (w->Title && !strcmp((const char *)w->Title, "The Grim Reaper")) found = w;
    IIntuition->UnlockIBase(lock);
    if (!found) {
        printf("0\n");
        return 0;
    }
    char x[16], y[16], t[] = "The Grim Reaper", c[] = "click";
    snprintf(x, sizeof x, "%d", found->LeftEdge + found->Width / 2);
    snprintf(y, sizeof y, "%d", found->TopEdge + found->Height - 21);
    char *av[] = { "ptr", x, y, c, t, NULL };
    extern int ptr_main(int, char **);
    int r = ptr_main(5, av);
    printf("%d\n", r == 0);
    return r;
}

int ptr_main(int argc, char **argv);
int main(int argc, char **argv)
{
    if (argc == 2 && !strcmp(argv[1], "reaper")) return reaper();
    return ptr_main(argc, argv);
}

int ptr_main(int argc, char **argv)
{
    if (argc < 3) return 5;
    if (argc > 4) {
        struct IntuitionBase *ib = (struct IntuitionBase *)IntuitionBase;
        struct Window *found = NULL;
        uint32 lock = IIntuition->LockIBase(0);
        for (struct Window *w = ib->FirstScreen ? ib->FirstScreen->FirstWindow : NULL; w; w = w->NextWindow)
            if (w->Title && !strcmp((const char *)w->Title, argv[4])) found = w;
        IIntuition->UnlockIBase(lock);
        if (!found) return 5;
        for (int i = 0; i < 10 && ib->ActiveWindow != found; i++) {
            IIntuition->ActivateWindow(found);
            IDOS->Delay(10);
        }
        if (ib->ActiveWindow != found) return 5;
    }
    struct MsgPort *p = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    struct IOStdReq *r = IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Size, sizeof(struct IOStdReq),
                                                   ASOIOR_ReplyPort, p, TAG_DONE);
    if (!r || IExec->OpenDevice("input.device", 0, (struct IORequest *)r, 0)) return 10;
    struct Screen *scr = IIntuition->LockPubScreen(NULL);
    struct IEPointerPixel pp = { scr, { atoi(argv[1]), atoi(argv[2]) } };
    struct InputEvent ie;
    memset(&ie, 0, sizeof ie);
    ie.ie_Class = IECLASS_NEWPOINTERPOS;
    ie.ie_SubClass = IESUBCLASS_PIXEL;
    ie.ie_EventAddress = &pp;
    r->io_Command = IND_WRITEEVENT;
    r->io_Data = &ie;
    r->io_Length = sizeof ie;
    IExec->DoIO((struct IORequest *)r);
    int clicks = argc > 3 ? (!strcmp(argv[3], "double") ? 2 : !strcmp(argv[3], "move") ? 0 : 1) : 0;
    for (int i = 0; i < clicks; i++) {
        memset(&ie, 0, sizeof ie);
        ie.ie_Class = IECLASS_RAWMOUSE;
        ie.ie_Code = IECODE_LBUTTON;
        r->io_Data = &ie;
        IExec->DoIO((struct IORequest *)r);
        ie.ie_Code = IECODE_LBUTTON | IECODE_UP_PREFIX;
        IExec->DoIO((struct IORequest *)r);
        IDOS->Delay(5);
    }
    IIntuition->UnlockPubScreen(NULL, scr);
    IExec->CloseDevice((struct IORequest *)r);
    IExec->FreeSysObject(ASOT_IOREQUEST, r);
    IExec->FreeSysObject(ASOT_PORT, p);
    return 0;
}
