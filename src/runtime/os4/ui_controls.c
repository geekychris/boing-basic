/* Richer controls (docs/ui.md section 4): the TextEditor's selection, styles, clipboard, undo,
 * find/replace and files; the ListBrowser's columns, sorting, multiple selection and row data.
 * Tabs, TreeView and Grid are in ui_tabs.c, ui_tree.c and ui_grid.c. */
#include "forms_int.h"
#include "../fpath.h"

/* --- TextEditor ---------------------------------------------------------------------------- */

static uint32 ed_method(bb_ctl *c, Msg m)
{
    return IIntuition->DoGadgetMethodA((struct Gadget *)c->obj, c->form->win, NULL, m);
}

static int ed_arexx(bb_ctl *c, const char *cmd)
{
    ed_method(c, (Msg) & (struct GP_TEXTEDITOR_ARexxCmd){ GM_TEXTEDITOR_ARexxCmd, NULL, (STRPTR)cmd });
    return 0;
}

static char *ed_text(bb_ctl *c)
{
    STRPTR s = (STRPTR)ed_method(c, (Msg) & (struct GP_TEXTEDITOR_ExportText){ GM_TEXTEDITOR_ExportText, NULL });
    char *o = xstrdup(s ? (char *)s : "");
    if (s) IExec->FreeVec(s);
    return o;
}

/* character offset <-> (column, line) of the exported text */
static int32 ed_offset(const char *t, uint32 x, uint32 y)
{
    int32 o = 0;
    for (uint32 l = 0; l < y && t[o]; l++) {
        while (t[o] && t[o] != '\n') o++;
        if (t[o]) o++;
    }
    for (uint32 i = 0; i < x && t[o] && t[o] != '\n'; i++) o++;
    return o;
}

static void ed_pos(const char *t, int32 off, uint32 *x, uint32 *y)
{
    *x = *y = 0;
    for (int32 i = 0; i < off && t[i]; i++) {
        if (t[i] == '\n') {
            (*y)++;
            *x = 0;
        } else
            (*x)++;
    }
}

/* the selection as offsets; 0 if nothing is marked (start = end = the cursor) */
static int ed_sel(bb_ctl *c, const char *t, int32 *start, int32 *end)
{
    ULONG sx = 0, sy = 0, ex = 0, ey = 0;
    int marked = ed_method(c, (Msg) & (struct GP_TEXTEDITOR_BlockInfo){ GM_TEXTEDITOR_BlockInfo, NULL, &sx, &sy, &ex, &ey }) != 0;
    if (!marked) {
        sx = ex = get_attr(c, GA_TEXTEDITOR_CursorX);
        sy = ey = get_attr(c, GA_TEXTEDITOR_CursorY);
    }
    *start = ed_offset(t, sx, sy);
    *end = ed_offset(t, ex, ey) + (marked ? 1 : 0);    /* BlockInfo's stop is the last marked character */
    if (*end < *start) {
        int32 x = *start;
        *start = *end;
        *end = x;
    }
    return marked;
}

static void ed_mark(bb_ctl *c, const char *t, int32 start, int32 end)
{
    uint32 sx, sy, ex, ey;
    ed_pos(t, start, &sx, &sy);
    ed_pos(t, end, &ex, &ey);
    if (start == end) {
        set_attr(c, GA_TEXTEDITOR_CursorY, sy);
        set_attr(c, GA_TEXTEDITOR_CursorX, sx);
    } else
        ed_method(c, (Msg) & (struct GP_TEXTEDITOR_MarkText){ GM_TEXTEDITOR_MarkText, NULL, sx, sy, ex, ey });
}

#define IS(a) (!strcasecmp(prop, a))

int bbf_editor_get(bb_ctl *c, const char *prop, bb_fval *out)
{
    if (IS("CurrentLine")) return ret_int(out, (int32)get_attr(c, GA_TEXTEDITOR_CursorY));
    if (IS("CurrentColumn")) return ret_int(out, (int32)get_attr(c, GA_TEXTEDITOR_CursorX));
    if (IS("Modified")) return ret_int(out, vb_bool(get_attr(c, GA_TEXTEDITOR_HasChanged)));
    if (IS("FixedFont")) return ret_int(out, vb_bool(get_attr(c, GA_TEXTEDITOR_FixedFont)));
    if (IS("TabSize")) return ret_int(out, (int32)get_attr(c, GA_TEXTEDITOR_TabSize));
    if (IS("Bold")) return ret_int(out, vb_bool(get_attr(c, GA_TEXTEDITOR_StyleBold)));
    if (IS("Italic")) return ret_int(out, vb_bool(get_attr(c, GA_TEXTEDITOR_StyleItalic)));
    if (IS("Underline")) return ret_int(out, vb_bool(get_attr(c, GA_TEXTEDITOR_StyleUnderline)));
    if (IS("CanUndo")) return ret_int(out, vb_bool(get_attr(c, GA_TEXTEDITOR_UndoAvailable)));
    if (IS("CanRedo")) return ret_int(out, vb_bool(get_attr(c, GA_TEXTEDITOR_RedoAvailable)));
    if (IS("SelStart") || IS("SelLength") || IS("SelText")) {
        char *t = ed_text(c);
        int32 a, b;
        ed_sel(c, t, &a, &b);
        int r;
        if (IS("SelStart")) r = ret_int(out, a);
        else if (IS("SelLength")) r = ret_int(out, b - a);
        else {
            t[b] = 0;
            r = ret_str(c, out, t + a);
        }
        free(t);
        return r;
    }
    return 438;
}

int bbf_editor_set(bb_ctl *c, const char *prop, const bb_fval *v)
{
    char buf[16];
    if (IS("CurrentLine")) { set_attr(c, GA_TEXTEDITOR_CursorY, vint(v)); return 0; }
    if (IS("CurrentColumn")) { set_attr(c, GA_TEXTEDITOR_CursorX, vint(v)); return 0; }
    if (IS("Modified")) { set_attr(c, GA_TEXTEDITOR_HasChanged, vint(v) != 0); return 0; }
    if (IS("FixedFont")) { set_attr(c, GA_TEXTEDITOR_FixedFont, vint(v) != 0); return 0; }
    if (IS("TabSize")) { set_attr(c, GA_TEXTEDITOR_TabSize, vint(v)); return 0; }
    if (IS("Bold")) { set_attr(c, GA_TEXTEDITOR_StyleBold, vint(v) != 0); return 0; }
    if (IS("Italic")) { set_attr(c, GA_TEXTEDITOR_StyleItalic, vint(v) != 0); return 0; }
    if (IS("Underline")) { set_attr(c, GA_TEXTEDITOR_StyleUnderline, vint(v) != 0); return 0; }
    if (IS("SelStart") || IS("SelLength")) {
        char *t = ed_text(c);
        int32 a, b, n = strlen(t);
        ed_sel(c, t, &a, &b);
        if (IS("SelStart")) {
            a = vint(v);
            b = a;           /* VB: setting SelStart drops the selection */
        } else
            b = a + vint(v);
        if (a < 0) a = 0;
        if (a > n) a = n;
        if (b < a) b = a;
        if (b > n) b = n;
        ed_mark(c, t, a, b);
        free(t);
        return 0;
    }
    if (IS("SelText")) {
        /* replace the selection (or insert at the cursor) */
        char *t = ed_text(c);
        int32 a, b;
        int marked = ed_sel(c, t, &a, &b);
        const char *s = vstr(v, buf);
        if (!marked)
            ed_method(c, (Msg) & (struct GP_TEXTEDITOR_InsertText){ GM_TEXTEDITOR_InsertText, NULL, (STRPTR)s,
                                                                    GV_TEXTEDITOR_InsertText_Cursor });
        else      /* the marked block is replaced (as after a Search) */
            ed_method(c, (Msg) & (struct GP_TEXTEDITOR_Replace){ GM_TEXTEDITOR_Replace, NULL, (STRPTR)s, 0 });
        (void)a;
        (void)b;
        free(t);
        fire0(c, "Change");
        return 0;
    }
    return 438;
}

#undef IS
#define IS(a) (!strcasecmp(method, a))

static int ed_find(bb_ctl *c, const char *s, int matchcase, int fromtop)
{
    ULONG fl = GF_TEXTEDITOR_Search_Next | (matchcase ? GF_TEXTEDITOR_Search_CaseSensitive : 0);
    if (fromtop) {            /* from the start: the cursor to the top, then "next" */
        set_attr(c, GA_TEXTEDITOR_CursorY, 0);
        set_attr(c, GA_TEXTEDITOR_CursorX, 0);
    }
    return ed_method(c, (Msg) & (struct GP_TEXTEDITOR_Search){ GM_TEXTEDITOR_Search, NULL, (STRPTR)s, fl }) != 0;
}

int bbf_editor_call(bb_ctl *c, const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    char b0[16], b1[16];
    if (IS("Cut")) return ed_arexx(c, "CUT");
    if (IS("Copy")) return ed_arexx(c, "COPY");
    if (IS("Paste")) return ed_arexx(c, "PASTE");
    if (IS("Undo")) return ed_arexx(c, "UNDO");
    if (IS("Redo")) return ed_arexx(c, "REDO");
    if (IS("Clear")) {
        ed_method(c, (Msg) & (struct GP_TEXTEDITOR_ClearText){ GM_TEXTEDITOR_ClearText, NULL });
        fire0(c, "Change");
        return 0;
    }
    if (IS("SelectAll")) {
        char *t = ed_text(c);
        ed_mark(c, t, 0, strlen(t));
        free(t);
        return 0;
    }
    if (IS("InsertText")) {
        if (argc < 1) return 450;
        ed_method(c, (Msg) & (struct GP_TEXTEDITOR_InsertText){ GM_TEXTEDITOR_InsertText, NULL, (STRPTR)vstr(&argv[0], b0),
                                                                GV_TEXTEDITOR_InsertText_Cursor });
        fire0(c, "Change");
        return 0;
    }
    if (IS("Find")) {
        if (argc < 1) return 450;
        int mc = argc > 1 && argv[1].type != BB_FV_NONE && vint(&argv[1]);
        int top = argc > 2 && argv[2].type != BB_FV_NONE && vint(&argv[2]);
        return ret_int(ret, vb_bool(ed_find(c, vstr(&argv[0], b0), mc, top)));
    }
    if (IS("Replace")) {
        /* Replace find, with [, all [, matchCase]]: returns how many were replaced */
        if (argc < 2) return 450;
        const char *f = vstr(&argv[0], b0), *w = vstr(&argv[1], b1);
        int all = argc > 2 && argv[2].type != BB_FV_NONE && vint(&argv[2]);
        int mc = argc > 3 && argv[3].type != BB_FV_NONE && vint(&argv[3]);
        int n = 0;
        /* by hand (search + replace) rather than GM_TEXTEDITOR_ReplaceAll, which needs 53.30 */
        int top = all;
        while (ed_find(c, f, mc, top)) {
            ed_method(c, (Msg) & (struct GP_TEXTEDITOR_Replace){ GM_TEXTEDITOR_Replace, NULL, (STRPTR)w, 0 });
            n++;
            top = 0;
            if (!all || n > 100000) break;
        }
        if (n) fire0(c, "Change");
        return ret_int(ret, n);
    }
    if (IS("LoadFile")) {
        if (argc < 1) return 450;
        FILE *fp = fopen(vstr(&argv[0], b0), "rb");
        if (!fp) return 53;
        fseek(fp, 0, SEEK_END);
        long n = ftell(fp);
        fseek(fp, 0, SEEK_SET);
        char *t = malloc(n + 1);
        n = fread(t, 1, n, fp);
        t[n] = 0;
        fclose(fp);
        set_attr(c, GA_TEXTEDITOR_Contents, (uint32)t);
        set_attr(c, GA_TEXTEDITOR_HasChanged, FALSE);
        free(t);
        fire0(c, "Change");
        return 0;
    }
    if (IS("SaveFile")) {
        if (argc < 1) return 450;
        FILE *fp = fopen(vstr(&argv[0], b0), "wb");
        if (!fp) return 75;
        char *t = ed_text(c);
        size_t n = strlen(t);
        int ok = fwrite(t, 1, n, fp) == n;
        fclose(fp);
        free(t);
        if (!ok) return 61;
        set_attr(c, GA_TEXTEDITOR_HasChanged, FALSE);
        return 0;
    }
    return 438;
}

/* IDCMPUPDATE from the editor (it notifies on cursor moves and edits) */
void bbf_editor_update(bb_ctl *c)
{
    int32 x = (int32)get_attr(c, GA_TEXTEDITOR_CursorX), y = (int32)get_attr(c, GA_TEXTEDITOR_CursorY);
    int32 len = (int32)get_attr(c, GA_TEXTEDITOR_Length);
    if (c->lastval != len) {
        c->lastval = len;
        fire0(c, "Change");
    }
    if (ending) return;
    if (x != c->interval || y != c->pending) {     /* the editor uses the timer fields for its cursor */
        c->interval = x;
        c->pending = y;
        fire0(c, "CursorMove");
    }
}

/* --- ListBrowser columns, sorting, multiple selection ---------------------------------------- */

static int ncells(const char *s)
{
    int n = 1;
    for (; *s; s++) n += *s == '\t';
    return n;
}

/* cell `col` of a tab-separated row into buf */
static const char *cell(const char *row, int col, char *buf, size_t n)
{
    for (int i = 0; i < col && row; i++) {
        row = strchr(row, '\t');
        if (row) row++;
    }
    if (!row) return "";
    const char *e = strchr(row, '\t');
    size_t l = e ? (size_t)(e - row) : strlen(row);
    if (l >= n) l = n - 1;
    memcpy(buf, row, l);
    buf[l] = 0;
    return buf;
}

void bbf_list_setup(bb_ctl *c, tags *t)
{
    afg_node *n = c->node;
    c->multi = afg_get_bool(n, "multiselect");
    c->sortable = afg_get_bool(n, "sortable");
    c->sortcol = -1;
    if (c->multi) tg(t, LISTBROWSER_MultiSelect, TRUE);
    if (!afg_has(n, "columns") || !bbf_ILB) return;
    char **titles, **widths;
    int nc = afg_split_items(afg_get(n, "columns"), &titles);
    int nw = afg_split_items(afg_get(n, "widths"), &widths);
    c->ncols = nc;
    c->coltitles = calloc(nc, sizeof *c->coltitles);
    tags ct = { 0 };
    for (int i = 0; i < nc; i++) {
        c->coltitles[i] = xstrdup(titles[i]);
        tg(&ct, LBCIA_Column, i);
        tg(&ct, LBCIA_Title, (uint32)c->coltitles[i]);
        tg(&ct, LBCIA_Weight, i < nw && atoi(widths[i]) > 0 ? atoi(widths[i]) : 100 / nc);
        if (c->sortable) tg(&ct, LBCIA_Sortable, TRUE);
        tg(&ct, LBCIA_DraggableSeparator, TRUE);
    }
    tg(&ct, TAG_DONE, 0);
    c->colinfo = bbf_ILB->AllocLBColumnInfoA(nc, ct.t);
    free(ct.t);
    afg_free_items(titles, nc);
    afg_free_items(widths, nw);
    if (c->colinfo) {
        tg(t, LISTBROWSER_ColumnInfo, (uint32)c->colinfo);
        tg(t, LISTBROWSER_ColumnTitles, TRUE);
        if (c->sortable) tg(t, LISTBROWSER_TitleClickable, TRUE);
    }
}

struct Node *bbf_list_node(bb_ctl *c, int i)
{
    int nc = c->ncols > 1 ? c->ncols : 1;
    tags t = { 0 };
    char buf[512];
    if (c->multi && c->msel && c->msel[i]) tg(&t, LBNA_Selected, TRUE);
    for (int k = 0; k < nc; k++) {
        tg(&t, LBNA_Column, k);
        tg(&t, LBNCA_CopyText, TRUE);
        tg(&t, LBNCA_Text, (uint32)(nc > 1 ? cell(c->items[i], k, buf, sizeof buf) : c->items[i]));
    }
    tg(&t, TAG_DONE, 0);
    struct Node *n = bbf_ILB->AllocListBrowserNodeA(nc, t.t);
    free(t.t);
    return n;
}

void bbf_list_sync_sel(bb_ctl *c)
{
    if (!c->multi || !bbf_ILB) return;
    int i = 0;
    for (struct Node *n = c->labels.lh_Head; n->ln_Succ && i < c->nitems; n = n->ln_Succ, i++) {
        uint32 s = 0;
        bbf_ILB->GetListBrowserNodeAttrs(n, LBNA_Selected, &s, TAG_DONE);
        c->msel[i] = s != 0;
    }
}

static struct Node *nth(bb_ctl *c, int i)
{
    struct Node *n = c->labels.lh_Head;
    for (; n->ln_Succ && i > 0; n = n->ln_Succ) i--;
    return n->ln_Succ ? n : NULL;
}

/* numbers compare as numbers, text without case */
static int cmp_cells(const char *a, const char *b)
{
    char *ea, *eb;
    double x = strtod(a, &ea), y = strtod(b, &eb);
    if (*a && *b && !*ea && !*eb) return x < y ? -1 : x > y;
    return strcasecmp(a, b);
}

static bb_ctl *sorting;
static int cmp_rows(const void *pa, const void *pb)
{
    int ia = *(const int *)pa, ib = *(const int *)pb;
    char ba[512], bb[512];
    int r = cmp_cells(cell(sorting->items[ia], sorting->sortcol, ba, sizeof ba), cell(sorting->items[ib], sorting->sortcol, bb, sizeof bb));
    if (!r) r = ia - ib;             /* stable */
    return sorting->sortorder ? -r : r;
}

static void list_rebuild(bb_ctl *c)
{
    /* through the regular path: AddItem's list_changed (detach, rebuild, reattach) */
    bb_fval none = { BB_FV_NONE, 0, NULL, NULL };
    (void)none;
    set_attr(c, LISTBROWSER_Labels, ~0u);
    struct Node *nd;
    while ((nd = IExec->RemHead(&c->labels))) bbf_ILB->FreeListBrowserNode(nd);
    for (int i = 0; i < c->nitems; i++) {
        struct Node *n = bbf_list_node(c, i);
        if (n) IExec->AddTail(&c->labels, n);
    }
    struct TagItem t[3] = { { LISTBROWSER_Labels, (uint32)&c->labels }, { c->multi ? TAG_IGNORE : LISTBROWSER_Selected, (uint32)c->sel },
                            { TAG_DONE, 0 } };
    if (c->form->win) IIntuition->SetGadgetAttrsA((struct Gadget *)c->obj, c->form->win, NULL, t);
    else IIntuition->SetAttrsA(c->obj, t);
}

static void list_sort(bb_ctl *c, int col, int order)
{
    bbf_list_sync_sel(c);
    c->sortcol = col;
    c->sortorder = order;
    int n = c->nitems;
    int *ix = malloc(n * sizeof *ix);
    for (int i = 0; i < n; i++) ix[i] = i;
    sorting = c;
    qsort(ix, n, sizeof *ix, cmp_rows);
    char **it = malloc(n * sizeof *it);
    uint8 *ms = malloc(n);
    int32 *id = malloc(n * sizeof *id);
    int newsel = -1;
    for (int i = 0; i < n; i++) {
        it[i] = c->items[ix[i]];
        ms[i] = c->msel[ix[i]];
        id[i] = c->idata[ix[i]];
        if (ix[i] == c->sel) newsel = i;
    }
    memcpy(c->items, it, n * sizeof *it);
    memcpy(c->msel, ms, n);
    memcpy(c->idata, id, n * sizeof *id);
    free(it);
    free(ms);
    free(id);
    free(ix);
    c->sel = newsel;
    list_rebuild(c);
}

int bbf_list_title_click(bb_ctl *c)
{
    int col = (int)get_attr(c, LISTBROWSER_RelColumn);
    if (c->sortable) list_sort(c, col, col == c->sortcol ? !c->sortorder : 0);
    return col;
}

#undef IS
#define IS(a) (!strcasecmp(prop, a))

int bbf_list_get(bb_ctl *c, const char *prop, int index, bb_fval *out)
{
    if (IS("ColumnCount")) return ret_int(out, c->ncols > 1 ? c->ncols : 1);
    if (IS("ColumnTitle")) {
        if (index < 0 || index >= c->ncols) return 381;
        return ret_str(c, out, c->coltitles[index]);
    }
    if (IS("Selected")) {
        if (index < 0 || index >= c->nitems) return 381;
        if (!c->multi) return ret_int(out, vb_bool((int32)get_attr(c, LISTBROWSER_Selected) == index));
        bbf_list_sync_sel(c);
        return ret_int(out, vb_bool(c->msel[index]));
    }
    if (IS("SelCount")) {
        if (!c->multi) return ret_int(out, (int32)get_attr(c, LISTBROWSER_Selected) >= 0);
        bbf_list_sync_sel(c);
        int k = 0;
        for (int i = 0; i < c->nitems; i++) k += c->msel[i];
        return ret_int(out, k);
    }
    if (IS("SortColumn")) return ret_int(out, c->sortcol);
    if (IS("SortOrder")) return ret_int(out, c->sortorder);
    if (IS("ItemData")) {
        if (index < 0 || index >= c->nitems) return 381;
        return ret_int(out, c->idata[index]);
    }
    if (IS("MultiSelect")) return ret_int(out, vb_bool(c->multi));
    return 438;
}

int bbf_list_set(bb_ctl *c, const char *prop, int index, const bb_fval *v)
{
    char buf[16];
    if (IS("Selected")) {
        if (index < 0 || index >= c->nitems) return 381;
        if (!c->multi) {
            set_attr(c, LISTBROWSER_Selected, vint(v) ? (uint32)index : (uint32)-1);
            c->sel = vint(v) ? index : -1;
            return 0;
        }
        bbf_list_sync_sel(c);
        c->msel[index] = vint(v) != 0;
        struct Node *n = nth(c, index);
        if (n) {
            set_attr(c, LISTBROWSER_Labels, ~0u);
            bbf_ILB->SetListBrowserNodeAttrs(n, LBNA_Selected, c->msel[index], TAG_DONE);
            set_attr(c, LISTBROWSER_Labels, (uint32)&c->labels);
        }
        return 0;
    }
    if (IS("SortColumn")) {
        int col = vint(v);
        if (col < 0 || col >= (c->ncols > 1 ? c->ncols : 1)) return 380;
        list_sort(c, col, c->sortorder);
        return 0;
    }
    if (IS("SortOrder")) {
        c->sortorder = vint(v) != 0;
        if (c->sortcol >= 0) list_sort(c, c->sortcol, c->sortorder);
        return 0;
    }
    if (IS("ItemData")) {
        if (index < 0 || index >= c->nitems) return 381;
        c->idata[index] = vint(v);
        return 0;
    }
    if (IS("ColumnTitle")) {
        if (index < 0 || index >= c->ncols) return 381;
        free(c->coltitles[index]);
        c->coltitles[index] = xstrdup(vstr(v, buf));
        set_attr(c, LISTBROWSER_ColumnInfo, ~0u);
        bbf_ILB->SetLBColumnInfoAttrs(c->colinfo, LBCIA_Column, index, LBCIA_Title, (uint32)c->coltitles[index], TAG_DONE);
        set_attr(c, LISTBROWSER_ColumnInfo, (uint32)c->colinfo);
        return 0;
    }
    if (IS("ColumnCount") || IS("SelCount")) return 383;
    return 438;
}

#undef IS
#define IS(a) (!strcasecmp(method, a))

int bbf_list_call(bb_ctl *c, const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    (void)ret;
    if (IS("Sort")) {
        int col = argc > 0 && argv[0].type != BB_FV_NONE ? vint(&argv[0]) : (c->sortcol >= 0 ? c->sortcol : 0);
        int order = argc > 1 && argv[1].type != BB_FV_NONE ? vint(&argv[1]) != 0 : c->sortorder;
        if (col < 0 || col >= (c->ncols > 1 ? c->ncols : 1)) return 5;
        list_sort(c, col, order);
        return 0;
    }
    return 438;
}

/* Cell(row, col) */
static int list_cell_set(bb_ctl *c, int row, int col, const char *s)
{
    if (row < 0 || row >= c->nitems || col < 0 || col >= (c->ncols > 1 ? c->ncols : 1)) return 381;
    char *r = c->items[row];
    int n = ncells(r);
    if (n < col + 1) n = col + 1;
    size_t cap = strlen(r) + strlen(s) + n + 2;
    char *o = malloc(cap), buf[512];
    o[0] = 0;
    for (int k = 0; k < n; k++) {
        if (k) strcat(o, "\t");
        strcat(o, k == col ? s : cell(r, k, buf, sizeof buf));
    }
    free(c->items[row]);
    c->items[row] = o;
    bbf_list_sync_sel(c);
    list_rebuild(c);
    return 0;
}

int bbf_get2(bb_ctl *c, const char *method, int i, int j, bb_fval *out)
{
    if (c->kind == AFG_LISTBROWSER && IS("Cell")) {
        char buf[512];
        if (i < 0 || i >= c->nitems || j < 0 || j >= (c->ncols > 1 ? c->ncols : 1)) return 381;
        return ret_str(c, out, cell(c->items[i], j, buf, sizeof buf));
    }
    return bbf_grid_get2(c, method, i, j, out);
}

int bbf_set2(bb_ctl *c, const char *method, int i, int j, const bb_fval *v)
{
    char buf[16];
    if (c->kind == AFG_LISTBROWSER && IS("Cell")) return list_cell_set(c, i, j, vstr(v, buf));
    return bbf_grid_set2(c, method, i, j, v);
}
