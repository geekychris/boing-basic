/* desk_hotkey: inject ctrl alt shift F9 (for tests-os4/desk/run.sh) */
#include <proto/exec.h>
#include <devices/input.h>
#include <devices/inputevent.h>
#include <string.h>
int main(void)
{
    struct MsgPort *p = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    struct IOStdReq *r = IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Size, sizeof(struct IOStdReq), ASOIOR_ReplyPort, p, TAG_DONE);
    if (!r || IExec->OpenDevice("input.device", 0, (struct IORequest *)r, 0)) return 20;
    struct InputEvent ie;
    memset(&ie, 0, sizeof ie);
    ie.ie_Class = IECLASS_RAWKEY;
    ie.ie_Code = 0x58;     /* F9 */
    ie.ie_Qualifier = IEQUALIFIER_CONTROL | IEQUALIFIER_LALT | IEQUALIFIER_LSHIFT;
    r->io_Command = IND_WRITEEVENT; r->io_Data = &ie; r->io_Length = sizeof ie;
    IExec->DoIO((struct IORequest *)r);
    ie.ie_Code |= IECODE_UP_PREFIX;
    IExec->DoIO((struct IORequest *)r);
    IExec->CloseDevice((struct IORequest *)r);
    IExec->FreeSysObject(ASOT_IOREQUEST, r);
    IExec->FreeSysObject(ASOT_PORT, p);
    return 0;
}
