/* audio_os4.c - the Audio object's output on AmigaOS 4: ahi.device, fed by a mixer process.
 *
 * The process keeps two CMD_WRITE requests queued behind each other (ahir_Link, as in
 * amiga_mcp's amiga3d sound_ahi.c, MIT, Chris Collins) and sleeps in Wait() until one comes
 * back; then it mixes the next chunk into that request's buffer (bb_audio_mix with the mutex
 * held) and sends it again. No busy waiting, and the program needs no per-frame call.
 * The BASIC side takes the same mutex for every Audio call.
 *
 * Chunks are rate/25 frames (40 ms), so a new sound effect starts within 40..80 ms.
 * CpuLoad: the time spent mixing over the last second, from the EClock.
 */
#include <exec/exec.h>
#include <dos/dos.h>
#include <dos/dostags.h>
#include <devices/ahi.h>
#include <devices/timer.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/timer.h>
#include <string.h>
#include "../audio.h"

static APTR mutex;
static struct Task *parent;
static struct Task *mixer;
static int8 parent_sig = -1;
static volatile int state;              /* 0 starting, 1 running, -1 failed, 2 gone */
static int out_rate, chunk;
static volatile int cpu_load = -1;

void audio_plat_lock(void) { if (mutex) IExec->MutexObtain(mutex); }
void audio_plat_unlock(void) { if (mutex) IExec->MutexRelease(mutex); }
int audio_plat_cpu_load(void) { return cpu_load; }
const char *audio_plat_name(void) { return "ahi"; }

static void send(struct AHIRequest *r, int16 *buf, struct AHIRequest *link)
{
    r->ahir_Std.io_Command = CMD_WRITE;
    r->ahir_Std.io_Data = buf;
    r->ahir_Std.io_Length = (uint32)chunk * 4;
    r->ahir_Std.io_Offset = 0;
    r->ahir_Type = AHIST_S16S;
    r->ahir_Frequency = (uint32)out_rate;
    r->ahir_Volume = 0x10000;
    r->ahir_Position = 0x8000;
    r->ahir_Link = link;
    IExec->SendIO((struct IORequest *)r);
}

static uint64 eclock(struct TimerIFace *it, uint32 *freq)
{
    struct EClockVal ev;
    *freq = it->ReadEClock(&ev);
    return ((uint64)ev.ev_hi << 32) | ev.ev_lo;
}

static int32 mixer_main(STRPTR args, int32 len, struct ExecBase *sysbase)
{
    struct MsgPort *port = NULL;
    struct AHIRequest *req[2] = { NULL, NULL };
    struct TimeRequest *tr = NULL;
    struct TimerIFace *itimer = NULL;
    int16 *buf[2] = { NULL, NULL };
    int busy[2] = { 0, 0 }, dev_open = 0, timer_open = 0, i;
    uint32 freq = 0;
    uint64 win_start = 0, busy_ticks = 0;

    port = IExec->AllocSysObjectTags(ASOT_PORT, TAG_DONE);
    if (port) req[0] = IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_ReplyPort, port,
                                                 ASOIOR_Size, sizeof(struct AHIRequest), TAG_DONE);
    if (req[0]) {
        req[0]->ahir_Version = 4;
        dev_open = IExec->OpenDevice((CONST_STRPTR)AHINAME, AHI_DEFAULT_UNIT, (struct IORequest *)req[0], 0) == 0;
    }
    if (dev_open) req[1] = IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_Duplicate, req[0], TAG_DONE);
    for (i = 0; i < 2 && req[1]; i++)
        buf[i] = IExec->AllocVecTags((uint32)chunk * 4, AVT_Type, MEMF_SHARED, AVT_ClearWithValue, 0, TAG_DONE);
    if (port) tr = IExec->AllocSysObjectTags(ASOT_IOREQUEST, ASOIOR_ReplyPort, port,
                                             ASOIOR_Size, sizeof(struct TimeRequest), TAG_DONE);
    if (tr && IExec->OpenDevice(TIMERNAME, UNIT_ECLOCK, (struct IORequest *)tr, 0) == 0) {
        timer_open = 1;
        itimer = (struct TimerIFace *)IExec->GetInterface((struct Library *)tr->Request.io_Device, "main", 1, NULL);
    }

    if (!buf[0] || !buf[1]) {
        state = -1;
    } else {
        state = 1;
        if (itimer) win_start = eclock(itimer, &freq);
    }
    IExec->Signal(parent, 1UL << parent_sig);

    if (state == 1) {
        for (i = 0; i < 2; i++) {
            IExec->MutexObtain(mutex);
            bb_audio_mix(buf[i], chunk);
            IExec->MutexRelease(mutex);
            send(req[i], buf[i], i ? req[0] : NULL);
            busy[i] = 1;
        }
        for (;;) {
            uint32 sigs = IExec->Wait((1UL << port->mp_SigBit) | SIGBREAKF_CTRL_C);
            if (sigs & SIGBREAKF_CTRL_C) break;
            for (i = 0; i < 2; i++) {
                if (!busy[i] || !IExec->CheckIO((struct IORequest *)req[i])) continue;
                IExec->WaitIO((struct IORequest *)req[i]);
                busy[i] = 0;
                {
                    uint64 t0 = itimer ? eclock(itimer, &freq) : 0;
                    IExec->MutexObtain(mutex);
                    bb_audio_mix(buf[i], chunk);
                    IExec->MutexRelease(mutex);
                    if (itimer) {
                        uint64 t1 = eclock(itimer, &freq);
                        busy_ticks += t1 - t0;
                        if (freq && t1 - win_start >= freq) {
                            cpu_load = (int)(busy_ticks * 1000 / (t1 - win_start));
                            win_start = t1;
                            busy_ticks = 0;
                        }
                    }
                }
                send(req[i], buf[i], busy[1 - i] ? req[1 - i] : NULL);
                busy[i] = 1;
            }
        }
    }

    for (i = 0; i < 2; i++)
        if (busy[i]) {
            if (!IExec->CheckIO((struct IORequest *)req[i])) IExec->AbortIO((struct IORequest *)req[i]);
            IExec->WaitIO((struct IORequest *)req[i]);
        }
    if (itimer) IExec->DropInterface((struct Interface *)itimer);
    if (timer_open) IExec->CloseDevice((struct IORequest *)tr);
    if (tr) IExec->FreeSysObject(ASOT_IOREQUEST, tr);
    if (dev_open) IExec->CloseDevice((struct IORequest *)req[0]);
    for (i = 1; i >= 0; i--) if (req[i]) IExec->FreeSysObject(ASOT_IOREQUEST, req[i]);
    for (i = 0; i < 2; i++) if (buf[i]) IExec->FreeVec(buf[i]);
    if (port) IExec->FreeSysObject(ASOT_PORT, port);

    IExec->Forbid();                    /* the parent may unload us once it has the signal */
    state = 2;
    IExec->Signal(parent, 1UL << parent_sig);
    (void)args; (void)len; (void)sysbase;
    return 0;
}

int audio_plat_open(int rate)
{
    struct Process *pr;
    if (mixer) return 1;
    if (!mutex) mutex = IExec->AllocSysObjectTags(ASOT_MUTEX, ASOMUTEX_Recursive, TRUE, TAG_DONE);
    if (!mutex) return 0;
    parent = IExec->FindTask(NULL);
    parent_sig = IExec->AllocSignal(-1);
    if (parent_sig < 0) return 0;
    out_rate = rate;
    chunk = rate / 25;
    state = 0;
    cpu_load = -1;
    IExec->SetSignal(0, 1UL << parent_sig);
    pr = IDOS->CreateNewProcTags(NP_Entry, (APTR)mixer_main, NP_Name, "Boing BASIC audio",
                                 NP_Priority, 10, NP_StackSize, 32768, NP_Child, TRUE,
                                 NP_Input, 0, NP_Output, 0, NP_CloseInput, FALSE,
                                 NP_CloseOutput, FALSE, TAG_DONE);
    if (!pr) { IExec->FreeSignal(parent_sig); parent_sig = -1; return 0; }
    while (state == 0) IExec->Wait(1UL << parent_sig);
    if (state != 1) {
        while (state != 2) IExec->Wait(1UL << parent_sig);
        IExec->FreeSignal(parent_sig);
        parent_sig = -1;
        return 0;
    }
    mixer = (struct Task *)pr;
    return 1;
}

void audio_plat_close(void)
{
    if (!mixer) return;
    IExec->Signal(mixer, SIGBREAKF_CTRL_C);
    while (state != 2) IExec->Wait(1UL << parent_sig);
    mixer = NULL;
    IExec->FreeSignal(parent_sig);
    parent_sig = -1;
}
