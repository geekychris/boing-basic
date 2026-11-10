/* key_inject TITLE COUNT RAWKEY [RAWKEY ...]: COUNT times, wait for a window titled TITLE
 * (up to 30 s), make it the active one, press the next raw key of the list (cycling: 0x44
 * Return, 0x45 Esc ...) and wait until the window has gone. For BASIC tests that open
 * requesters (tests-os4/palette): the program starts it with Shell "run ...". Keys only go
 * to that window while it is the active one. */
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/intuition.h>
#include <intuition/intuitionbase.h>
#include <devices/input.h>
#include <devices/inputevent.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static struct Window *find(const char *title)
{
    struct Window *found = NULL;
    struct Screen *s = IIntuition->LockPubScreen(NULL);
    IExec->Forbid();
    for (struct Window *w = s ? s->FirstWindow : NULL; w; w = w->NextWindow)
        if (w->Title && !strcmp((const char *)w->Title, title)) found = w;
    IExec->Permit();
    if (s) IIntuition->UnlockPubScreen(NULL, s);
    return found;
}

int main(int argc, char **argv)
{
    if (argc < 4) return 20;
    int count = atoi(argv[2]), nkeys = argc - 3;
    struct MsgPort *p = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    struct IOStdReq *r = IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Size, sizeof(struct IOStdReq),
                                                   ASOIOR_ReplyPort, p, TAG_DONE);
    if (!r || IExec->OpenDevice("input.device", 0, (struct IORequest *)r, 0)) return 20;
    for (int i = 0; i < count; i++) {
        struct Window *w = NULL;
        for (int t = 0; t < 150 && !(w = find(argv[1])); t++) IDOS->Delay(10);
        if (!w) break;
        IDOS->Delay(40);                     /* drawn and ready */
        int active = 0;
        for (int t = 0; t < 20 && !active; t++) {
            if (!(w = find(argv[1]))) break;
            if (((struct IntuitionBase *)IntuitionBase)->ActiveWindow == w) active = 1;
            else {
                IIntuition->ActivateWindow(w);
                IDOS->Delay(10);
            }
        }
        if (active) {
            struct InputEvent ie;
            memset(&ie, 0, sizeof ie);
            ie.ie_Class = IECLASS_RAWKEY;
            ie.ie_Code = (UWORD)strtol(argv[3 + i % nkeys], NULL, 0);
            r->io_Command = IND_WRITEEVENT;
            r->io_Data = &ie;
            r->io_Length = sizeof ie;
            IExec->DoIO((struct IORequest *)r);
            ie.ie_Code |= IECODE_UP_PREFIX;
            IExec->DoIO((struct IORequest *)r);
        }
        for (int t = 0; t < 150 && find(argv[1]); t++) IDOS->Delay(10);
    }
    IExec->CloseDevice((struct IORequest *)r);
    IExec->FreeSysObject(ASOT_IOREQUEST, r);
    IExec->FreeSysObject(ASOT_PORT, p);
    return 0;
}
