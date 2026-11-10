/* wb_mkproj FILE TOOL [TOOLTYPE ...]: a project icon FILE.info with TOOL as its default tool and
 * the given tooltypes (for tests-os4/wbproj) */
#include <proto/exec.h>
#include <proto/icon.h>
#include <workbench/workbench.h>
#include <stdio.h>
int main(int argc, char **argv)
{
    struct Library *ib = IExec->OpenLibrary("icon.library", 44);
    struct IconIFace *ii = ib ? (void *)IExec->GetInterface(ib, "main", 1, NULL) : NULL;
    if (!ii || argc < 3) return 20;
    struct DiskObject *d = ii->GetDefDiskObject(WBPROJECT);
    if (!d) return 20;
    STRPTR tt[16];
    int n = 0;
    for (int i = 3; i < argc && n < 15; i++) tt[n++] = argv[i];
    tt[n] = NULL;
    STRPTR *old = d->do_ToolTypes;
    char *oldtool = d->do_DefaultTool;
    d->do_DefaultTool = argv[2];
    d->do_ToolTypes = tt;
    d->do_CurrentX = d->do_CurrentY = NO_ICON_POSITION;
    int ok = ii->PutDiskObject(argv[1], d);
    d->do_ToolTypes = old;
    d->do_DefaultTool = oldtool;
    ii->FreeDiskObject(d);
    printf("PutDiskObject %s: %d\n", argv[1], ok);
    IExec->DropInterface((struct Interface *)ii);
    IExec->CloseLibrary(ib);
    return ok ? 0 : 10;
}
