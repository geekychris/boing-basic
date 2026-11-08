/* declare_test - the Declare glue calls OS functions through their interface slots and gets
 * the same results as the direct calls. Prints "ok <n>" per check and "PASS"/"FAIL" at the end. */
#include <stdio.h>
#include <string.h>

#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/utility.h>
#include <proto/graphics.h>

#include "bb_declare.h"

/* run from a background CLI (run >NIL:) the default stack is only a few KB */
static const char __attribute__((used)) stack_cookie[] = "$STACK:262144";

static int fails, n;

static void check(int ok, const char *what)
{
    n++;
    printf("%s %d - %s\n", ok ? "ok" : "not ok", n, what);
    if (!ok) fails++;
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);   /* progress shows when redirected to a file */
    bb_decl *d;
    int e;

    /* exec FindTask(NULL), by name through the slot table */
    e = bb_decl_resolve("exec.library", "main", 0, "FindTask", NULL, &d);
    check(e == 0, "resolve exec FindTask by name");
    if (!e) {
        uint32_t a[1] = { 0 };
        check(bb_decl_call(d, 1, a) == (uint32_t)IExec->FindTask(NULL), "FindTask(NULL) = this task");
    }

    /* utility Stricmp by alias "#n" (looked up) */
    e = bb_decl_resolve("utility.library", NULL, 0, "MyStricmp", "Stricmp", &d);
    check(e == 0, "resolve utility Stricmp by alias name");
    if (!e) {
        uint32_t a[2] = { (uint32_t)"Boing", (uint32_t)"BOING" };
        check(bb_decl_call(d, 2, a) == 0, "Stricmp(Boing, BOING) = 0");
        a[1] = (uint32_t)"Ball";
        check((int32_t)bb_decl_call(d, 2, a) > 0, "Stricmp(Boing, Ball) > 0");
    }

    /* dos: open a file through Declares with slots from genbind (Open #4, Write #7, Close #5) */
    bb_decl *dopen, *dwrite, *dclose;
    check(bb_decl_resolve("dos.library", "main", 50, "Dos_Open", "#4", &dopen) == 0, "resolve dos #4 Open");
    check(bb_decl_resolve("dos.library", "main", 50, "Dos_Write", "#7", &dwrite) == 0, "resolve dos #7 Write");
    check(bb_decl_resolve("dos.library", "main", 50, "Dos_Close", "#5", &dclose) == 0, "resolve dos #5 Close");
    {
        uint32_t a[3] = { (uint32_t)"T:boing_declare_test", MODE_NEWFILE };
        BPTR fh = (BPTR)bb_decl_call(dopen, 2, a);
        check(fh != 0, "Open T:boing_declare_test");
        a[0] = fh; a[1] = (uint32_t)"hello"; a[2] = 5;
        check(bb_decl_call(dwrite, 3, a) == 5, "Write 5 bytes");
        a[0] = fh;
        check(bb_decl_call(dclose, 1, a) != 0, "Close");
        int64 size = -1;
        struct ExamineData *ed = IDOS->ExamineObjectTags(EX_StringNameInput, "T:boing_declare_test", TAG_DONE);
        if (ed) { size = ed->FileSize; IDOS->FreeDosObject(DOS_EXAMINEDATA, ed); }
        check(size == 5, "the file has 5 bytes");
        IDOS->Delete("T:boing_declare_test");
    }

    /* 11 arguments (8 in registers, 3 on the stack): graphics BltBitMap, slot #4 */
    e = bb_decl_resolve("graphics.library", "main", 0, "BltBitMap", "#4", &d);
    check(e == 0, "resolve graphics #4 BltBitMap");
    if (!e) {
        struct BitMap *src = IGraphics->AllocBitMapTags(32, 32, 8, BMATags_Clear, TRUE, TAG_DONE);
        struct BitMap *dst = IGraphics->AllocBitMapTags(32, 32, 8, BMATags_Clear, TRUE, BMATags_Friend, src,
                                                        TAG_DONE);
        struct RastPort srp, drp;
        IGraphics->InitRastPort(&srp);
        IGraphics->InitRastPort(&drp);
        srp.BitMap = src;
        drp.BitMap = dst;
        IGraphics->SetAPen(&srp, 5);
        IGraphics->RectFill(&srp, 0, 0, 31, 31);
        uint32_t a[11] = { (uint32_t)src, 0, 0, (uint32_t)dst, 3, 4, 10, 10, 0xC0, 0xFF, 0 };
        bb_decl_call(d, 11, a);
        check(IGraphics->ReadPixel(&drp, 5, 6) == 5 && IGraphics->ReadPixel(&drp, 12, 13) == 5,
              "BltBitMap copied the 10x10 block to (3,4)");
        check(IGraphics->ReadPixel(&drp, 2, 4) == 0 && IGraphics->ReadPixel(&drp, 13, 14) == 0,
              "and nothing outside it (stack arguments arrived)");
        IGraphics->FreeBitMap(src);
        IGraphics->FreeBitMap(dst);
    }

    check(bb_decl_resolve("exec.library", "main", 0, "NoSuchFunction", NULL, &d) == 453, "unknown function = 453");
    check(bb_decl_resolve("nosuch.library", "main", 0, "Foo", "#5", &d) == 48, "missing library = 48");
    check(bb_decl_resolve("dos.library", "main", 9999, "Open", "#4", &d) == 48, "version too new = 48");
    check(bb_decl_resolve("dos.library", "main", 0, "Bad", "#99999", &d) == 453, "slot past the end = 453");

    /* a device's interface: timer.device GetSysTime (slot 7 in timer.xml?) by name */
    e = bb_decl_resolve("timer.device", "main", 0, "GetSysTime", NULL, &d);
    check(e == 0, "resolve timer.device GetSysTime");
    if (!e) {
        struct TimeVal tv = { 0, 0 };
        uint32_t a[1] = { (uint32_t)&tv };
        bb_decl_call(d, 1, a);
        check(tv.Seconds > 0, "GetSysTime filled in the time");
    }

    bb_decl_cleanup();
    printf("%s (%d/%d)\n", fails ? "FAIL" : "PASS", n - fails, n);
    return fails ? 10 : 0;
}
