/* ui_controls_test - the richer controls of docs/ui.md section 4: TextEditor selection, styles,
 * find/replace, undo; ListBrowser columns, Cell, sorting, multi-select, ItemData; tabs; TreeView;
 * Grid (TextMatrix, typing into a cell with injected keys, AfterEdit, cursor keys, AddItem);
 * a splitter layout. Prints TAP-like lines and PASS/FAIL. */
#define MAIN_TITLE "Boing controls test - running"
#include "test_inject.h"
#include "bb_forms.h"
#include "os4/forms_int.h"     /* the listbrowser's nodes, read back below */

static const char __attribute__((used)) stack_cookie[] = "$STACK:262144";

static const char *afg =
    "window name=main title=\"Boing controls test\" width=480 height=360\n"
    "vlayout id=root\n"
    "  hlayout splitter=1\n"
    "    texteditor id=ed text=\"Hello world\\nsecond line\" minheight=60\n"
    "    listbrowser id=files columns=\"Name|Size\" widths=\"70|30\" sortable=1 multiselect=1 items=\"b.txt\t300|a.txt\t1000|c.txt\t20\"\n"
    "  tabs id=pages weight=0\n"
    "    vlayout title=\"One\"\n"
    "      label text=\"Page one\"\n"
    "    vlayout title=\"Two\"\n"
    "      label text=\"Page two\"\n"
    "  hlayout\n"
    "    treeview id=tree minwidth=120\n"
    "    grid id=sheet rows=6 cols=4 fixedrows=1 fixedcols=1 colwidth=60 editable=1 headers=1\n"
    "  timer id=tick interval=400\n"
    "  timer id=guard interval=120000\n";

static bb_form *form;
static int step, afteredits, enters, colclicks, edchanges, nodeclicks;

static bb_ctl *C(const char *name) { return strcasecmp(name, "Form") ? bb_form_ctl(form, name) : bb_form_self(form); }
static int geti(const char *ctl, const char *prop, int idx)
{
    bb_fval v;
    return bb_ctl_get(C(ctl), prop, idx, &v) ? -9999 : v.i;
}
static const char *gets_(const char *ctl, const char *prop, int idx)
{
    static char buf[512];
    bb_fval v;
    if (bb_ctl_get(C(ctl), prop, idx, &v)) return "<error>";
    snprintf(buf, sizeof buf, "%s", v.s);
    return buf;
}
static const char *gets2(const char *ctl, const char *prop, int i, int j)
{
    static char buf[512];
    bb_fval v;
    if (bb_ctl_get2(C(ctl), prop, i, j, &v)) return "<error>";
    snprintf(buf, sizeof buf, "%s", v.s);
    return buf;
}
static int seti(const char *ctl, const char *prop, int idx, int i)
{
    bb_fval v = { BB_FV_INT, i, NULL, NULL };
    return bb_ctl_set(C(ctl), prop, idx, &v);
}
static int sets(const char *ctl, const char *prop, int idx, const char *s)
{
    bb_fval v = { BB_FV_STR, 0, s, NULL };
    return bb_ctl_set(C(ctl), prop, idx, &v);
}
static int sets2(const char *ctl, const char *prop, int i, int j, const char *s)
{
    bb_fval v = { BB_FV_STR, 0, s, NULL };
    return bb_ctl_set2(C(ctl), prop, i, j, &v);
}
static int calls(const char *ctl, const char *m, int argc, const char *a0, const char *a1, const char *a2, bb_fval *r)
{
    bb_fval a[3] = { { BB_FV_STR, 0, a0, NULL }, { BB_FV_STR, 0, a1, NULL }, { BB_FV_STR, 0, a2, NULL } };
    bb_fval rr;
    return bb_ctl_call(C(ctl), m, argc, a, r ? r : &rr);
}

static void script(void);
static int on_event(void *ud, bb_form *f, const char *ctl, const char *ev, int argc, int32_t *args)
{
    if (!strcasecmp(ctl, "guard") && !strcasecmp(ev, "Timer")) {
        /* a step got stuck: fail and close everything rather than leave a window behind */
        printf("not ok - the test took more than 2 minutes (guard timer)\n");
        fails++;
        bb_forms_end();
        return 0;
    }
    (void)ud; (void)f; (void)argc; (void)args;
    if (!strcasecmp(ctl, "sheet") && !strcasecmp(ev, "AfterEdit")) afteredits++;
    if (!strcasecmp(ctl, "sheet") && !strcasecmp(ev, "EnterCell")) enters++;
    if (!strcasecmp(ctl, "files") && !strcasecmp(ev, "ColumnClick")) colclicks++;
    if (!strcasecmp(ctl, "ed") && !strcasecmp(ev, "Change")) edchanges++;
    if (!strcasecmp(ctl, "tree") && !strcasecmp(ev, "NodeClick")) nodeclicks++;
    if (!strcasecmp(ctl, "tick") && !strcasecmp(ev, "Timer")) script();
    return 0;
}

static int gx, gy, gw, gh;
static void script(void)
{
    switch (step++) {
    case 0:
        /* click data cell (1, 1) of the grid: fixed column ~38 px + a bit, below the title row */
        if (ready_mouse() && bb_ctl_screen_box(C("sheet"), &gx, &gy, &gw, &gh)) {
            printf("# grid box %d,%d %dx%d\n", gx, gy, gw, gh);
            click_at(gx + 4 + 38 + 20, gy + 4 + 18 + 9);
        } else
            step = 3;
        break;
    case 1:
        printf("# grid Row %d Col %d\n", geti("sheet", "Row", -1), geti("sheet", "Col", -1));
        check(geti("sheet", "Row", -1) == 1 && geti("sheet", "Col", -1) == 1, "a click selects grid cell (1, 1)");
        key(0x20); key(0x35); key(0x35); key(0x44);       /* a b b Return */
        break;
    case 2:
        printf("# TextMatrix(1,1) = \"%s\" AfterEdit %d Row %d\n", gets2("sheet", "TextMatrix", 1, 1), afteredits, geti("sheet", "Row", -1));
        check(!strcmp(gets2("sheet", "TextMatrix", 1, 1), "abb"), "typing into the cell + Return: TextMatrix(1, 1) = \"abb\"");
        check(afteredits == 1, "sheet_AfterEdit fired once");
        check(geti("sheet", "Row", -1) == 2, "Return moved to the next row");
        key(0x4E);                                         /* cursor right */
        break;
    case 3:
        check(geti("sheet", "Col", -1) == 2, "cursor right moves to column 2");
        seti("tick", "Enabled", -1, 0);
        bb_form_unload(form);
        break;
    }
}

int main(void)
{
    setvbuf(stdout, NULL, _IOLBF, 0);
    char err[200];
    bb_fval r;
    if (!inject_open()) { printf("can't open input.device\nFAIL\n"); return 20; }
    form = bb_form_load(afg, "controls.afg", on_event, NULL, NULL, err, sizeof err);
    check(form != NULL, "the form loads");
    if (!form) { printf("# %s\nFAIL\n", err); return 20; }
    check(bb_form_show(form) == 0, "Show");
    sets("Form", "Caption", -1, MAIN_TITLE);

    /* listbrowser */
    check(geti("files", "ColumnCount", -1) == 2 && !strcmp(gets_("files", "ColumnTitle", 1), "Size"), "ColumnCount, ColumnTitle(1)");
    check(!strcmp(gets2("files", "Cell", 1, 1), "1000"), "Cell(1, 1) = \"1000\"");
    sets2("files", "Cell", 2, 0, "z.txt");
    check(!strcmp(gets2("files", "Cell", 2, 0), "z.txt") && !strcmp(gets2("files", "Cell", 2, 1), "20"), "Cell(2, 0) = \"z.txt\" keeps column 1");
    seti("files", "ItemData", 0, 111);
    seti("files", "ItemData", 1, 222);
    seti("files", "SortColumn", -1, 1);
    check(!strcmp(gets2("files", "Cell", 0, 1), "20") && !strcmp(gets2("files", "Cell", 2, 1), "1000"), "SortColumn = 1 sorts numerically");
    check(geti("files", "ItemData", 1) == 111 && geti("files", "ItemData", 2) == 222, "ItemData moved with its rows");
    seti("files", "SortOrder", -1, 1);
    check(!strcmp(gets2("files", "Cell", 0, 1), "1000"), "SortOrder = 1: descending");
    seti("files", "Selected", 0, -1);
    seti("files", "Selected", 2, -1);
    check(geti("files", "SelCount", -1) == 2 && geti("files", "Selected", 2) == -1 && geti("files", "Selected", 1) == 0, "multi-select: Selected(i), SelCount");
    bb_fval item = { BB_FV_STR, 0, "d.txt\t5", NULL };
    bb_ctl_call(C("files"), "AddItem", 1, &item, &r);
    check(geti("files", "ListCount", -1) == 4 && geti("files", "Selected", 2) == -1, "AddItem keeps the selection");
    {
        /* what listbrowser.gadget holds and draws: each node's column texts (LBNCA_Text), which
           must be the row's own cells, not the last cell in every column */
        bb_ctl *lc = C("files");
        int row = 0, bad = 0;
        for (struct Node *nd = lc->labels.lh_Head; nd->ln_Succ; nd = nd->ln_Succ, row++)
            for (int k = 0; k < 2; k++) {
                STRPTR txt = NULL;
                bbf_ILB->GetListBrowserNodeAttrs(nd, LBNA_Column, k, LBNCA_Text, &txt, TAG_DONE);
                const char *want = gets2("files", "Cell", row, k);
                if (!txt || strcmp((const char *)txt, want)) {
                    printf("# row %d column %d shows \"%s\", Cell is \"%s\"\n", row, k, txt ? (char *)txt : "(null)", want);
                    bad++;
                }
            }
        check(row == 4 && bad == 0, "every listbrowser column shows its own cell (node texts read back)");
    }

    /* texteditor */
    printf("# initial Text \"%s\"\n", gets_("ed", "Text", -1));
    seti("ed", "SelStart", -1, 6);
    printf("# after SelStart 6: Text \"%s\" CurrentColumn %d\n", gets_("ed", "Text", -1), geti("ed", "CurrentColumn", -1));
    seti("ed", "SelLength", -1, 5);
    printf("# after SelLength 5: Text \"%s\"\n", gets_("ed", "Text", -1));
    printf("# SelText \"%s\" SelStart %d SelLength %d\n", gets_("ed", "SelText", -1), geti("ed", "SelStart", -1), geti("ed", "SelLength", -1));
    check(!strcmp(gets_("ed", "SelText", -1), "world"), "SelStart 6 + SelLength 5: SelText = \"world\"");
    sets("ed", "SelText", -1, "Amiga");
    printf("# after SelText: \"%s\"\n", gets_("ed", "Text", -1));
    check(!strncmp(gets_("ed", "Text", -1), "Hello Amiga\n", 12), "SelText = \"Amiga\" replaces the selection");
    calls("ed", "Find", 1, "second", 0, 0, &r);
    printf("# after Find: \"%s\" SelText \"%s\"\n", gets_("ed", "Text", -1), gets_("ed", "SelText", -1));
    check(r.type == BB_FV_INT && r.i == -1, "Find(\"second\") = True");
    calls("ed", "Replace", 3, "line", "row", "1", &r);
    printf("# Replace returned %ld, text \"%s\"\n", (long)r.i, gets_("ed", "Text", -1));
    check(r.i == 1 && strstr(gets_("ed", "Text", -1), "second row") != NULL, "Replace \"line\", \"row\", True");
    check(geti("ed", "Modified", -1) == -1, "Modified = True after edits");
    seti("ed", "Modified", -1, 0);
    check(geti("ed", "Modified", -1) == 0, "Modified = False");
    seti("ed", "CurrentLine", -1, 1);
    check(geti("ed", "CurrentLine", -1) == 1, "CurrentLine = 1");

    /* tabs */
    check(geti("pages", "TabCount", -1) == 2 && !strcmp(gets_("pages", "TabCaption", 1), "Two"), "tabs: TabCount, TabCaption(1)");
    check(geti("pages", "PageFramed", 0) == 0 && geti("pages", "PageFramed", 1) == 0, "tab pages don't draw their title again as a frame label");
    seti("pages", "Tab", -1, 1);
    check(geti("pages", "Tab", -1) == 1, "pages.Tab = 1");

    /* treeview */
    calls("tree", "AddNode", 3, "root", "", "Work:", &r);
    calls("tree", "AddNode", 3, "docs", "root", "Documents", &r);
    calls("tree", "AddNode", 3, "pics", "root", "Pictures", &r);
    calls("tree", "AddNode", 3, "a", "docs", "letter.txt", &r);
    check(geti("tree", "NodeCount", -1) == 4, "AddNode x4: NodeCount = 4");
    check(calls("tree", "AddNode", 3, "root", "", "again", &r) == 457, "a duplicate key is error 457");
    sets("tree", "SelectedKey", -1, "a");
    check(!strcmp(gets_("tree", "SelectedKey", -1), "a") && nodeclicks == 1, "SelectedKey = \"a\" opens its parents and selects it");
    calls("tree", "NodeText", 1, "docs", 0, 0, &r);
    check(r.type == BB_FV_STR && !strcmp(r.s, "Documents"), "NodeText(\"docs\")");
    calls("tree", "NodeParent", 1, "a", 0, 0, &r);
    check(r.type == BB_FV_STR && !strcmp(r.s, "docs"), "NodeParent(\"a\") = \"docs\"");
    calls("tree", "RemoveNode", 1, "docs", 0, 0, &r);
    check(geti("tree", "NodeCount", -1) == 2, "RemoveNode removes the node and its children");

    /* grid */
    check(geti("sheet", "Rows", -1) == 6 && geti("sheet", "Cols", -1) == 4, "grid Rows, Cols");
    check(!strcmp(gets2("sheet", "TextMatrix", 0, 1), "A") && !strcmp(gets2("sheet", "TextMatrix", 2, 0), "2"), "headers=1: A, B... and 1, 2...");
    sets2("sheet", "TextMatrix", 3, 2, "42");
    check(!strcmp(gets2("sheet", "TextMatrix", 3, 2), "42"), "TextMatrix(3, 2) = \"42\"");
    bb_fval row = { BB_FV_STR, 0, "x\ty\tz", NULL };
    bb_ctl_call(C("sheet"), "AddItem", 1, &row, &r);
    check(geti("sheet", "Rows", -1) == 7 && !strcmp(gets2("sheet", "TextMatrix", 6, 2), "z"), "AddItem adds a row");
    seti("sheet", "ColWidth", 2, 90);
    check(geti("sheet", "ColWidth", 2) == 90, "ColWidth(2) = 90");

    bb_forms_run();
    bb_forms_cleanup();
    inject_close();
    printf("%s (%d/%d)\n", fails ? "FAIL" : "PASS", n - fails, n);
    return fails ? 10 : 0;
}
