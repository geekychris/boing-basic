/* boing started from Workbench: a .bas/.bbp/.bbc project icon whose default tool is boing gives
 * argc 0 and argv = the WBStartup. The first project is run like `boing run`, with a console
 * window that opens only when the program prints (AUTO) and waits to be closed at the end (WAIT).
 * (A file of its own: the compiler's headers clash with exec's.) */
#ifdef __amigaos4__
#include <proto/exec.h>
#include <proto/dos.h>
#include <workbench/startup.h>
#include <dos/dosextens.h>
#include <stdio.h>

static char *wb_args[4];

int bb_wb_start(int *argc, char ***argv)
{
    struct WBStartup *wbs = (struct WBStartup *)*argv;
    static char path[1024];
    if (*argc != 0 || !wbs || wbs->sm_NumArgs < 2) return 0;
    if (!IDOS->NameFromLock(wbs->sm_ArgList[1].wa_Lock, path, sizeof path)) return 0;
    IDOS->AddPart(path, (STRPTR)wbs->sm_ArgList[1].wa_Name, sizeof path);
    /* one console window for input and output: opened once, made the process's console, and
       stdin/stdout/stderr reopened on "*" (that console) */
    BPTR con = IDOS->Open("CON:20/40/640/240/Boing BASIC/AUTO/CLOSE/WAIT", MODE_NEWFILE);
    if (con) {
        IDOS->SetConsolePort(((struct FileHandle *)BADDR(con))->fh_MsgPort);
        IDOS->SelectInput(con);
        IDOS->SelectOutput(con);
        freopen("*", "w", stdout);
        freopen("*", "w", stderr);
        freopen("*", "r", stdin);
    }
    wb_args[0] = "boing";
    wb_args[1] = "run";
    wb_args[2] = path;
    *argc = 3;
    *argv = wb_args;
    return 1;
}
#endif
