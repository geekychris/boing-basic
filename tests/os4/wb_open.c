/* wb_open PATH [FILE ...]: ask Workbench to open PATH as a double-click does, with the FILEs as
 * further selected icons (shift-click), for tests-os4/wbproj */
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/wb.h>
#include <workbench/workbench.h>
#include <stdio.h>
#include <string.h>
int main(int argc, char **argv)
{
    struct Library *wb = IExec->OpenLibrary("workbench.library", 44);
    struct WorkbenchIFace *iwb = wb ? (void *)IExec->GetInterface(wb, "main", 1, NULL) : NULL;
    if (!iwb || argc < 2) return 20;
    struct TagItem tags[2 * 8 + 1];
    BPTR locks[8];
    int n = 0, k = 0;
    for (int i = 2; i < argc && n < 8; i++, n++) {
        char dir[512];
        snprintf(dir, sizeof dir, "%s", argv[i]);
        *IDOS->PathPart(dir) = 0;
        locks[n] = IDOS->Lock(dir, SHARED_LOCK);
        tags[k].ti_Tag = WBOPENA_ArgLock; tags[k++].ti_Data = (uint32)locks[n];
        tags[k].ti_Tag = WBOPENA_ArgName; tags[k++].ti_Data = (uint32)IDOS->FilePart(argv[i]);
    }
    tags[k].ti_Tag = TAG_DONE;
    int ok = iwb->OpenWorkbenchObjectA(argv[1], tags);
    printf("OpenWorkbenchObject %s (+%d): %s\n", argv[1], n, ok ? "ok" : "failed");
    for (int i = 0; i < n; i++) IDOS->UnLock(locks[i]);
    IExec->DropInterface((struct Interface *)iwb);
    IExec->CloseLibrary(wb);
    return ok ? 0 : 10;
}
