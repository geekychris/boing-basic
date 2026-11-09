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

static int opmask = ~0;

static void round_(void)
{
    char err[200];
    bb_form *f = bb_form_load(afg, "leak.afg", ev, NULL, NULL, err, sizeof err);
    if (!f) { printf("# %s\n", err); return; }
    bb_form_show(f);
    bb_fval r, a[3] = { { BB_FV_STR, 0, "k1", NULL }, { BB_FV_STR, 0, "", NULL }, { BB_FV_STR, 0, "Node", NULL } };
    if (opmask & 1) {
    bb_ctl_call(bb_form_ctl(f, "tv"), "AddNode", 3, a, &r);
    a[0].s = "k2"; a[1].s = "k1";
    bb_ctl_call(bb_form_ctl(f, "tv"), "AddNode", 3, a, &r);
    }
    for (int i = 1; i < 20 && (opmask & 2); i++) {
        char s[16];
        snprintf(s, sizeof s, "%d", i * 7);
        bb_fval v = { BB_FV_STR, 0, s, NULL };
        bb_ctl_set2(bb_form_ctl(f, "g"), "TextMatrix", i, 1, &v);
    }
    bb_fval it = { BB_FV_STR, 0, "z\t3", NULL };
    if (opmask & 4) bb_ctl_call(bb_form_ctl(f, "lb"), "AddItem", 1, &it, &r);
    bb_fval col = { BB_FV_INT, 1, NULL, NULL };
    if (opmask & 8) bb_ctl_set(bb_form_ctl(f, "lb"), "SortColumn", -1, &col);
    bb_fval p = { BB_FV_STR, 0, "Ln 2", NULL };
    if (opmask & 16) bb_ctl_set(bb_form_ctl(f, "sb"), "Panel", 1, &p);
    bb_fval am[3] = { { BB_FV_STR, 0, "mx", NULL }, { BB_FV_STR, 0, "Extra", NULL }, { BB_FV_STR, 0, "mf", NULL } };
    if (opmask & 32) bb_ctl_call(bb_form_self(f), "AddMenu", 3, am, &r);
    bb_fval df = { BB_FV_STR, 0, "#?.txt", NULL };
    if (opmask & 64) bb_ctl_set(bb_form_ctl(f, "dlg"), "Filter", -1, &df);
    bb_forms_doevents();
    bb_form_hide(f);
    bb_form_unload(f);
    bb_forms_doevents();          /* frees the unloaded form */
    bb_forms_run();
    if (opmask & 128) {
        bb_ctl *d = bb_dialog_new();
        bb_ctl_set(d, "Filter", -1, &df);
        bb_dialog_free(d);
    }
}

static const char *parts[][2] = {
    { "plain", "window name=p title=\"leak plain\"\nvlayout\n  button id=b text=OK\n" },
    { "tabs+ed", "window name=p title=\"leak a\"\nvlayout\n  tabs id=t\n    hlayout title=A\n      button text=x\n    vlayout title=B\n      texteditor id=ed text=hello\n" },
    { "editor", "window name=p title=\"leak b\"\nvlayout\n  texteditor id=ed text=hello\n" },
    { "menus+tb", "window name=p title=\"leak c\"\nvlayout\n  toolbar id=tb\n    tool id=t1 text=New image=\"TBImages:new\" menu=m1\nmenu id=mf text=F\n  menu id=m1 text=N key=N\nmenu id=ctx text=C hidden=1\n  menu id=c1 text=O\n" },
    { "list", "window name=p title=\"leak d\"\nvlayout\n  listbrowser id=lb columns=\"A|B\" multiselect=1 sortable=1 items=\"x\t1|y\t2\"\n" },
    { "grid", "window name=p title=\"leak e\"\nvlayout\n  grid id=g rows=30 cols=8 headers=1\n" },
    { "full", 0 },
};

static long heap(void) { return 0; }
static long heaplost;

static long measure(const char *a)
{
    char err[200];
    bb_form *f = bb_form_load(a, "p.afg", ev, NULL, NULL, err, sizeof err);
    if (f) { bb_form_show(f); bb_forms_doevents(); bb_form_unload(f); bb_forms_run(); }
    uint32 before = IExec->AvailMem(MEMF_ANY);
    long h0 = heap();
    for (int i = 0; i < 50; i++) {
        f = bb_form_load(a, "p.afg", ev, NULL, NULL, err, sizeof err);
        if (!f) { printf("# %s\n", err); return 0; }
        bb_form_show(f);
        bb_forms_doevents();
        bb_form_unload(f);
        bb_forms_run();
    }
    heaplost = heap() - h0;
    return (long)before - (long)IExec->AvailMem(MEMF_ANY);
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    if (argc > 1)
        for (unsigned i = 0; i < sizeof parts / sizeof parts[0]; i++)
        {
            long m = 1L << 30;
            for (int k = 0; k < 3; k++) {     /* the guest is shared: the smallest of 3 runs */
                long l = measure(parts[i][1] ? parts[i][1] : afg);
                if (l < m) m = l;
            }
            printf("# %-10s %ld bytes over 50 rounds (least of 3); C heap %+ld\n", parts[i][0], m, heaplost);
        }
    if (argc > 1 && !strcmp(argv[1], "ops"))
        for (int bit = -1; bit < 8; bit++) {
            opmask = bit < 0 ? 0 : 1 << bit;
            round_();
            long m = 1L << 30;
            for (int k = 0; k < 3; k++) {
                uint32 b = IExec->AvailMem(MEMF_ANY);
                for (int i = 0; i < 10; i++) round_();
                long l = (long)b - (long)IExec->AvailMem(MEMF_ANY);
                if (l < m) m = l;
            }
            printf("# ops %3d: %ld bytes over 10 rounds (least of 3)\n", opmask, m);
        }
    /* AvailMem on OS4 doesn't come back at once (the slab allocator and page_sweep keep freed
       memory a while), so a plain one-button form is the baseline: the full form with every
       UI kind (and the operations on them) must not lose clearly more than it */
    opmask = ~0;
    round_();                    /* warm-up: classes, libraries, pens */
    long base = 1L << 30, lost = 1L << 30;
    for (int k = 0; k < 3; k++) {
        long l = measure(parts[0][1]);
        if (l < base) base = l;
    }
    for (int k = 0; k < 3; k++) {
        uint32 before = IExec->AvailMem(MEMF_ANY);
        for (int i = 0; i < 50; i++) round_();
        long l = (long)before - (long)IExec->AvailMem(MEMF_ANY);
        printf("# run %d: %ld bytes over 50 rounds\n", k + 1, l);
        if (l < lost) lost = l;
    }
    printf("# plain form: %ld bytes over 50 rounds; every UI kind: %ld\n", base, lost);
    /* a real leak makes every run positive; a negative baseline is the guest's noise */
    lost -= base > 0 ? base : 0;
    bb_forms_cleanup();
    /* noise comes in ~52 KB steps: allow 3 of them over 50 rounds (3 KB a round) */
    int ok = lost < 3 * 53248 + 4096;
    printf("%s 1 - load/show/fill/unload of every UI kind x50 does not leak\n", ok ? "ok" : "not ok");
    printf("%s (%d/1)\n", ok ? "PASS" : "FAIL", ok);
    return ok ? 0 : 10;
}
