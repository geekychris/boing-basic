/* ui_leak_test - memory leaks of the docs/ui.md controls: a form with menus, a toolbar with
 * pictures, a status bar, a grid, a tree, tabs, a columned list, a commondialog and a canvas
 * area is loaded, shown, filled, hidden and unloaded 20 times (after one warm-up round that
 * opens the classes and libraries); free memory must come back. PASS/FAIL. */
#include <stdio.h>
#include <string.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include "bb_forms.h"

static const char __attribute__((used)) stack_cookie[] = "$STACK:262144";

static const char *afg =
    "window name=leak title=\"Boing leak test\" width=400 height=300 iconify=1\n"
    "vlayout id=root\n"
    "  toolbar id=tb weight=0\n"
    "    tool id=t1 text=\"New\" image=\"TBImages:new\" menu=m1\n"
    "    tool separator=1\n"
    "    tool id=t2 text=\"Grid\" toggle=1\n"
    "  button id=pb text=\"Save\" image=\"TBImages:save\"\n"
    "  tabs id=tabs\n"
    "    hlayout title=\"A\" splitter=1\n"
    "      grid id=g rows=30 cols=8 headers=1\n"
    "      treeview id=tv\n"
    "    vlayout title=\"B\"\n"
    "      listbrowser id=lb columns=\"A|B\" multiselect=1 sortable=1 items=\"x\t1|y\t2\"\n"
    "      texteditor id=ed text=\"hello\"\n"
    "  image id=img file=\"TBImages:open\"\n"
    "  commondialog id=dlg\n"
    "  statusbar id=sb panels=\"a|b|c\"\n"
    "menu id=mf text=\"File\"\n"
    "  menu id=m1 text=\"New\" key=N\n"
    "  menu id=m2 text=\"Check\" checkable=1\n"
    "menu id=ctx text=\"Ctx\" hidden=1\n"
    "  menu id=c1 text=\"One\"\n";

static int ev(void *ud, bb_form *f, const char *ctl, const char *e, int argc, int32_t *args)
{
    (void)ud; (void)f; (void)ctl; (void)e; (void)argc; (void)args;
    return 0;
}

static void round_(void)
{
    char err[200];
    bb_form *f = bb_form_load(afg, "leak.afg", ev, NULL, NULL, err, sizeof err);
    if (!f) { printf("# %s\n", err); return; }
    bb_form_show(f);
    bb_fval r, a[3] = { { BB_FV_STR, 0, "k1", NULL }, { BB_FV_STR, 0, "", NULL }, { BB_FV_STR, 0, "Node", NULL } };
    bb_ctl_call(bb_form_ctl(f, "tv"), "AddNode", 3, a, &r);
    a[0].s = "k2"; a[1].s = "k1";
    bb_ctl_call(bb_form_ctl(f, "tv"), "AddNode", 3, a, &r);
    for (int i = 1; i < 20; i++) {
        char s[16];
        snprintf(s, sizeof s, "%d", i * 7);
        bb_fval v = { BB_FV_STR, 0, s, NULL };
        bb_ctl_set2(bb_form_ctl(f, "g"), "TextMatrix", i, 1, &v);
    }
    bb_fval it = { BB_FV_STR, 0, "z\t3", NULL };
    bb_ctl_call(bb_form_ctl(f, "lb"), "AddItem", 1, &it, &r);
    bb_fval col = { BB_FV_INT, 1, NULL, NULL };
    bb_ctl_set(bb_form_ctl(f, "lb"), "SortColumn", -1, &col);
    bb_fval p = { BB_FV_STR, 0, "Ln 2", NULL };
    bb_ctl_set(bb_form_ctl(f, "sb"), "Panel", 1, &p);
    bb_fval am[3] = { { BB_FV_STR, 0, "mx", NULL }, { BB_FV_STR, 0, "Extra", NULL }, { BB_FV_STR, 0, "mf", NULL } };
    bb_ctl_call(bb_form_self(f), "AddMenu", 3, am, &r);
    bb_fval df = { BB_FV_STR, 0, "#?.txt", NULL };
    bb_ctl_set(bb_form_ctl(f, "dlg"), "Filter", -1, &df);
    bb_forms_doevents();
    bb_form_hide(f);
    bb_form_unload(f);
    bb_forms_doevents();          /* frees the unloaded form */
    bb_forms_run();
    bb_ctl *d = bb_dialog_new();
    bb_ctl_set(d, "Filter", -1, &df);
    bb_dialog_free(d);
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    round_();                    /* warm-up: classes, libraries, pens */
    uint32 before = IExec->AvailMem(MEMF_ANY);
    for (int i = 0; i < 20; i++) round_();
    uint32 after = IExec->AvailMem(MEMF_ANY);
    long lost = (long)before - (long)after;
    printf("# free before %lu after %lu: %ld bytes lost over 20 rounds\n", (unsigned long)before, (unsigned long)after, lost);
    bb_forms_cleanup();
    /* allow some noise from other programs on the shared guest: under 64 KB over 20 rounds */
    int ok = lost < 65536;
    printf("%s 1 - load/show/fill/unload of every UI kind x20 does not leak\n", ok ? "ok" : "not ok");
    printf("%s (%d/1)\n", ok ? "PASS" : "FAIL", ok);
    return ok ? 0 : 10;
}
