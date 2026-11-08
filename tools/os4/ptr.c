/* ptr X Y [click|double] - move the pointer to (X, Y) on the front screen and click, through
 * input.device (for driving tests on the guest; QEMU's relative mouse is accelerated). */
#include <stdlib.h>
#include <string.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/intuition.h>
#include <devices/input.h>
#include <devices/inputevent.h>

int main(int argc, char **argv)
{
    if (argc < 3) return 5;
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
    int clicks = argc > 3 ? (!strcmp(argv[3], "double") ? 2 : 1) : 0;
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
    return 0;
}
