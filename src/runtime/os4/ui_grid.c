/* Grid (docs/ui.md section 4): an editable cell grid in the style of VB's MSFlexGrid, drawn
 * by the runtime with graphics.library into a space gadget, with ReAction scrollers. Only what
 * changes is redrawn: a cell edit or a move of the current cell repaints those cells; scrolling
 * and resizing repaint the visible area.
 *
 * Layout object: vlayout [ hlayout [ space (cells), vertical scroller ], horizontal scroller ].
 * The scrollers' gadget ids are the grid's id plus a part number << BBF_PART_SHIFT. */
#include "forms_int.h"
#include <proto/graphics.h>
#include <graphics/gfxmacros.h>

typedef struct grid {
    int rows, cols, frows, fcols;
    int row, col, toprow, leftcol;
    char **cells;              /* rows * cols, NULL = "" */
    int32 *fg, *bg;            /* VB colours, -1 = default */
    uint8 *bold;
    int32 *colw;
    int8 *align;               /* per column: -1 general, 0 left, 1 right, 2 centre */
    int rowh, defw;
    int editable, redraw, focus;
    int editing, ecur;
    char ebuf[1024];
    int sr1, sc1, sr2, sc2;    /* the selected range (sr1,sc1 = the anchor) */
    int dragging;
    Object *area, *vs, *hs;
    struct { int32 rgb; LONG pen; } pens[32];
    int npens;
    struct Screen *penscr;
    uint32 lsecs, lmicros;
    int lrow, lcol;
} grid;

static grid *G(bb_ctl *c) { return c->ext; }
#define CELL(g, r, c) ((g)->cells[(r) * (g)->cols + (c)])
#define IDX(g, r, c) ((r) * (g)->cols + (c))

/* --- storage ------------------------------------------------------------------------------- */

static void resize_grid(grid *g, int rows, int cols)
{
    if (rows < 0) rows = 0;
    if (cols < 0) cols = 0;
    size_t n = (size_t)rows * cols;
    char **cells = calloc(n ? n : 1, sizeof *cells);
    int32 *fg = malloc((n ? n : 1) * sizeof *fg), *bg = malloc((n ? n : 1) * sizeof *bg);
    uint8 *bold = calloc(n ? n : 1, 1);
    for (size_t i = 0; i < n; i++) fg[i] = bg[i] = -1;
    for (int r = 0; r < rows && r < g->rows; r++)
        for (int k = 0; k < cols && k < g->cols; k++) {
            int o = IDX(g, r, k), d = r * cols + k;
            cells[d] = g->cells[o];
            g->cells[o] = NULL;
            fg[d] = g->fg[o];
            bg[d] = g->bg[o];
            bold[d] = g->bold[o];
        }
    for (int i = 0; i < g->rows * g->cols; i++) free(g->cells[i]);
    free(g->cells);
    free(g->fg);
    free(g->bg);
    free(g->bold);
    g->cells = cells;
    g->fg = fg;
    g->bg = bg;
    g->bold = bold;
    g->colw = realloc(g->colw, (cols ? cols : 1) * sizeof *g->colw);
    g->align = realloc(g->align, (cols ? cols : 1) * sizeof *g->align);
    for (int k = g->cols; k < cols; k++) {
        g->colw[k] = g->defw;
        g->align[k] = -1;
    }
    g->rows = rows;
    g->cols = cols;
    if (g->frows > rows) g->frows = rows;
    if (g->fcols > cols) g->fcols = cols;
    if (g->row >= rows) g->row = rows - 1;
    if (g->col >= cols) g->col = cols - 1;
    if (g->row < g->frows) g->row = g->frows < rows ? g->frows : rows - 1;
    if (g->col < g->fcols) g->col = g->fcols < cols ? g->fcols : cols - 1;
    if (g->toprow < g->frows || g->toprow >= rows) g->toprow = g->frows;
    if (g->leftcol < g->fcols || g->leftcol >= cols) g->leftcol = g->fcols;
    g->sr1 = g->sr2 = g->row;
    g->sc1 = g->sc2 = g->col;
}

static const char *cell_text(grid *g, int r, int k)
{
    const char *s = r >= 0 && k >= 0 && r < g->rows && k < g->cols ? CELL(g, r, k) : NULL;
    return s ? s : "";
}

static void set_cell(grid *g, int r, int k, const char *s)
{
    free(CELL(g, r, k));
    CELL(g, r, k) = s && *s ? xstrdup(s) : NULL;
}

/* --- drawing ------------------------------------------------------------------------------- */

static LONG pen_for(bb_ctl *c, int32 vb)
{
    grid *g = G(c);
    struct Window *w = c->form->win;
    int32 rgb = vb & 0xFFFFFF;
    for (int i = 0; i < g->npens; i++)
        if (g->pens[i].rgb == rgb) return g->pens[i].pen;
    if (g->npens >= 32 || !w) return 1;
    uint32 r = rgb & 255, gg = (rgb >> 8) & 255, b = (rgb >> 16) & 255;
    LONG p = IGraphics->ObtainBestPen(w->WScreen->ViewPort.ColorMap, r * 0x01010101, gg * 0x01010101, b * 0x01010101,
                                      OBP_Precision, PRECISION_IMAGE, TAG_DONE);
    g->penscr = w->WScreen;
    g->pens[g->npens].rgb = rgb;
    g->pens[g->npens].pen = p;
    g->npens++;
    return p;
}

static void release_pens(grid *g)
{
    for (int i = 0; i < g->npens; i++)
        if (g->pens[i].pen >= 0 && g->penscr) IGraphics->ReleasePen(g->penscr->ViewPort.ColorMap, g->pens[i].pen);
    g->npens = 0;
}

/* the cells' box in the window */
static int area_box(bb_ctl *c, int *x, int *y, int *w, int *h)
{
    grid *g = G(c);
    if (!c->form->win || !g->area) return 0;
    struct Gadget *a = (struct Gadget *)g->area;
    *x = a->LeftEdge;
    *y = a->TopEdge;
    *w = a->Width;
    *h = a->Height;
    return *w > 0 && *h > 0;
}

static int col_x(grid *g, int k, int x0)
{
    /* x of column k (fixed columns, then from leftcol); -1 if scrolled out */
    int x = x0;
    for (int i = 0; i < g->fcols; i++) {
        if (i == k) return x;
        x += g->colw[i];
    }
    if (k < g->leftcol) return -1;
    for (int i = g->leftcol; i < g->cols; i++) {
        if (i == k) return x;
        x += g->colw[i];
    }
    return -1;
}

static int row_y(grid *g, int r, int y0)
{
    if (r < g->frows) return y0 + r * g->rowh;
    if (r < g->toprow) return -1;
    return y0 + (g->frows + r - g->toprow) * g->rowh;
}

static int is_number(const char *s)
{
    char *e;
    if (!*s) return 0;
    strtod(s, &e);
    while (*e == ' ') e++;
    return !*e;
}

static int in_sel(grid *g, int r, int k)
{
    int r1 = g->sr1 < g->sr2 ? g->sr1 : g->sr2, r2 = g->sr1 < g->sr2 ? g->sr2 : g->sr1;
    int c1 = g->sc1 < g->sc2 ? g->sc1 : g->sc2, c2 = g->sc1 < g->sc2 ? g->sc2 : g->sc1;
    return r >= r1 && r <= r2 && k >= c1 && k <= c2;
}

static void draw_cell(bb_ctl *c, int r, int k)
{
    grid *g = G(c);
    struct Window *win = c->form->win;
    int ax, ay, aw, ah;
    if (!g->redraw || !area_box(c, &ax, &ay, &aw, &ah)) return;
    int x = col_x(g, k, ax), y = row_y(g, r, ay);
    if (x < 0 || y < 0 || x >= ax + aw || y >= ay + ah) return;
    int w = g->colw[k], h = g->rowh;
    int cw = x + w > ax + aw ? ax + aw - x : w, ch = y + h > ay + ah ? ay + ah - y : h;
    if (cw <= 0 || ch <= 0) return;
    struct RastPort *rp = win->RPort;
    struct DrawInfo *dri = IIntuition->GetScreenDrawInfo(win->WScreen);
    UWORD *pens = dri ? dri->dri_Pens : NULL;
    int fixed = r < g->frows || k < g->fcols;
    int cur = r == g->row && k == g->col;
    int sel = !fixed && in_sel(g, r, k) && !(g->sr1 == g->sr2 && g->sc1 == g->sc2);
    LONG bgpen, fgpen, linepen;
    int32 bgc = g->bg[IDX(g, r, k)], fgc = g->fg[IDX(g, r, k)];
    if (fixed) bgpen = pens ? pens[BACKGROUNDPEN] : 0;
    else if (sel) bgpen = pens ? pens[FILLPEN] : 3;
    else bgpen = bgc >= 0 ? pen_for(c, bgc) : pen_for(c, 0xFFFFFF);
    fgpen = sel ? (pens ? pens[FILLTEXTPEN] : 2) : fgc >= 0 ? pen_for(c, fgc) : (pens ? pens[TEXTPEN] : 1);
    linepen = fixed ? (pens ? pens[SHADOWPEN] : 1) : pen_for(c, 0xC0C0C0);
    IGraphics->SetAPen(rp, bgpen);
    IGraphics->RectFill(rp, x, y, x + cw - 1, y + ch - 1);
    /* grid lines: right and bottom edge */
    IGraphics->SetAPen(rp, linepen);
    if (cw == w) {
        IGraphics->Move(rp, x + w - 1, y);
        IGraphics->Draw(rp, x + w - 1, y + ch - 1);
    }
    if (ch == h) {
        IGraphics->Move(rp, x, y + h - 1);
        IGraphics->Draw(rp, x + cw - 1, y + h - 1);
    }
    if (fixed && pens) {
        IGraphics->SetAPen(rp, pens[SHINEPEN]);
        IGraphics->Move(rp, x, y + ch - 2);
        IGraphics->Draw(rp, x, y);
        IGraphics->Draw(rp, x + cw - 2, y);
    }
    /* the text, clipped to the cell */
    const char *s = cur && g->editing ? g->ebuf : cell_text(g, r, k);
    int len = strlen(s);
    IGraphics->SetAPen(rp, fgpen);
    IGraphics->SetDrMd(rp, JAM1);
    IGraphics->SetSoftStyle(rp, g->bold[IDX(g, r, k)] || fixed ? FSF_BOLD : 0, FSF_BOLD);
    struct TextExtent te;
    int fit = len ? IGraphics->TextFit(rp, s, len, &te, NULL, 1, cw > 6 ? cw - 6 : 0, ch) : 0;
    int tw = fit ? IGraphics->TextLength(rp, s, fit) : 0;
    int al = g->align[k];
    if (al < 0) al = fixed ? 2 : is_number(s) ? 1 : 0;
    if (cur && g->editing) al = 0;
    int tx = al == 1 ? x + w - 4 - tw : al == 2 ? x + (w - tw) / 2 : x + 3;
    int ty = y + (h - rp->TxHeight) / 2 + rp->TxBaseline;
    if (fit) {
        IGraphics->Move(rp, tx, ty);
        IGraphics->Text(rp, s, fit);
    }
    IGraphics->SetSoftStyle(rp, 0, FSF_BOLD);
    /* the current cell: a frame; while editing, the cursor */
    if (cur) {
        IGraphics->SetAPen(rp, pens ? pens[g->focus ? FILLPEN : SHADOWPEN] : 3);
        int x2 = x + cw - 1, y2 = y + ch - 1;
        IGraphics->Move(rp, x, y);
        IGraphics->Draw(rp, x2, y);
        IGraphics->Draw(rp, x2, y2);
        IGraphics->Draw(rp, x, y2);
        IGraphics->Draw(rp, x, y);
        IGraphics->Move(rp, x + 1, y + 1);
        IGraphics->Draw(rp, x2 - 1, y + 1);
        IGraphics->Draw(rp, x2 - 1, y2 - 1);
        IGraphics->Draw(rp, x + 1, y2 - 1);
        IGraphics->Draw(rp, x + 1, y + 1);
        if (g->editing) {
            int cx = x + 3 + IGraphics->TextLength(rp, g->ebuf, g->ecur > fit ? fit : g->ecur);
            IGraphics->SetAPen(rp, pens ? pens[TEXTPEN] : 1);
            IGraphics->Move(rp, cx, y + 2);
            IGraphics->Draw(rp, cx, y + ch - 3);
        }
    }
    if (dri) IIntuition->FreeScreenDrawInfo(win->WScreen, dri);
}

static void update_scrollers(bb_ctl *c);

static void draw_all(bb_ctl *c)
{
    grid *g = G(c);
    int ax, ay, aw, ah;
    if (!g->redraw || !area_box(c, &ax, &ay, &aw, &ah)) return;
    struct RastPort *rp = c->form->win->RPort;
    int maxx = ax, maxy = ay;
    for (int r = 0; r < g->rows; r++) {
        int y = row_y(g, r, ay);
        if (y < 0) continue;
        if (y >= ay + ah) break;
        for (int k = 0; k < g->cols; k++) {
            int x = col_x(g, k, ax);
            if (x < 0) continue;
            if (x >= ax + aw) break;
            draw_cell(c, r, k);
            if (x + g->colw[k] > maxx) maxx = x + g->colw[k];
        }
        if (y + g->rowh > maxy) maxy = y + g->rowh;
    }
    /* the empty rest of the area */
    if (maxx > ax + aw) maxx = ax + aw;
    if (maxy > ay + ah) maxy = ay + ah;
    if (maxx < ax + aw) IGraphics->EraseRect(rp, maxx, ay, ax + aw - 1, ay + ah - 1);
    if (maxy < ay + ah) IGraphics->EraseRect(rp, ax, maxy, maxx - 1, ay + ah - 1);
    update_scrollers(c);
}

void bbf_grid_refresh(bb_ctl *c)
{
    if (G(c) && c->form->win) draw_all(c);
}

/* how many scrollable rows / columns fit */
static int vis_rows(bb_ctl *c)
{
    grid *g = G(c);
    int ax, ay, aw, ah;
    if (!area_box(c, &ax, &ay, &aw, &ah)) return 1;
    int n = ah / g->rowh - g->frows;
    return n > 0 ? n : 1;
}

static int vis_cols(bb_ctl *c, int from)
{
    grid *g = G(c);
    int ax, ay, aw, ah;
    if (!area_box(c, &ax, &ay, &aw, &ah)) return 1;
    int w = aw;
    for (int i = 0; i < g->fcols; i++) w -= g->colw[i];
    int n = 0;
    for (int i = from; i < g->cols && w >= g->colw[i]; i++) {
        w -= g->colw[i];
        n++;
    }
    return n > 0 ? n : 1;
}

static void sc_set(bb_ctl *c, Object *o, int total, int visible, int top)
{
    if (!o) return;
    struct TagItem t[4] = { { SCROLLER_Total, (uint32)(total > 0 ? total : 0) }, { SCROLLER_Visible, (uint32)visible },
                            { SCROLLER_Top, (uint32)top }, { TAG_DONE, 0 } };
    if (c->form->win) IIntuition->SetGadgetAttrsA((struct Gadget *)o, c->form->win, NULL, t);
    else IIntuition->SetAttrsA(o, t);
}

static void update_scrollers(bb_ctl *c)
{
    grid *g = G(c);
    sc_set(c, g->vs, g->rows - g->frows, vis_rows(c), g->toprow - g->frows);
    sc_set(c, g->hs, g->cols - g->fcols, vis_cols(c, g->leftcol), g->leftcol - g->fcols);
}

/* make the current cell visible; returns 1 if it scrolled */
static int scroll_to(bb_ctl *c, int r, int k)
{
    grid *g = G(c);
    int moved = 0;
    if (r >= g->frows) {
        int vr = vis_rows(c);
        if (r < g->toprow) { g->toprow = r; moved = 1; }
        else if (r >= g->toprow + vr) { g->toprow = r - vr + 1; moved = 1; }
    }
    if (k >= g->fcols) {
        if (k < g->leftcol) { g->leftcol = k; moved = 1; }
        else
            while (k >= g->leftcol + vis_cols(c, g->leftcol) && g->leftcol < k) { g->leftcol++; moved = 1; }
    }
    if (moved) draw_all(c);
    return moved;
}

/* --- editing and moving -------------------------------------------------------------------- */

static void commit_edit(bb_ctl *c)
{
    grid *g = G(c);
    if (!g->editing) return;
    g->editing = 0;
    set_cell(g, g->row, g->col, g->ebuf);
    draw_cell(c, g->row, g->col);
    int32_t a[2] = { g->row, g->col };       /* VSFlexGrid's AfterEdit(Row, Col) */
    fire(c->form, c->name, "AfterEdit", 2, a);
}

static void cancel_edit(bb_ctl *c)
{
    grid *g = G(c);
    if (!g->editing) return;
    g->editing = 0;
    draw_cell(c, g->row, g->col);
}

static int start_edit(bb_ctl *c, const char *init)
{
    grid *g = G(c);
    if (!g->editable || g->editing || g->row < g->frows || g->col < g->fcols) return 0;
    int32_t a[3] = { g->row, g->col, 0 };   /* BeforeEdit(Row, Col, Cancel) */
    fire(c->form, c->name, "BeforeEdit", 3, a);
    if (a[2] || ending) return 0;
    g->editing = 1;
    snprintf(g->ebuf, sizeof g->ebuf, "%s", init ? init : cell_text(g, g->row, g->col));
    g->ecur = strlen(g->ebuf);
    draw_cell(c, g->row, g->col);
    return 1;
}

static void select_range(bb_ctl *c, int r1, int c1, int r2, int c2)
{
    grid *g = G(c);
    int multi_before = !(g->sr1 == g->sr2 && g->sc1 == g->sc2);
    g->sr1 = r1; g->sc1 = c1; g->sr2 = r2; g->sc2 = c2;
    int multi = !(r1 == r2 && c1 == c2);
    if (multi || multi_before) draw_all(c);
}

static void move_to(bb_ctl *c, int r, int k, int extend)
{
    grid *g = G(c);
    if (r < g->frows) r = g->frows;
    if (k < g->fcols) k = g->fcols;
    if (r >= g->rows) r = g->rows - 1;
    if (k >= g->cols) k = g->cols - 1;
    if (r < 0 || k < 0) return;
    if (r == g->row && k == g->col && !extend) {
        if (!(g->sr1 == g->sr2 && g->sc1 == g->sc2)) select_range(c, r, k, r, k);
        return;
    }
    commit_edit(c);
    if (ending) return;
    if (r != g->row || k != g->col) fire0(c, "LeaveCell");
    int or = g->row, oc = g->col;
    g->row = r;
    g->col = k;
    if (extend) select_range(c, g->sr1, g->sc1, r, k);
    else select_range(c, r, k, r, k);
    if (!scroll_to(c, r, k)) {
        draw_cell(c, or, oc);
        draw_cell(c, r, k);
    }
    if (!ending) fire0(c, "EnterCell");
}

/* --- building ------------------------------------------------------------------------------ */

Object *bbf_grid_build(bb_form *f, afg_node *n, bb_ctl *c, tags *t)
{
    grid *g = calloc(1, sizeof *g);
    c->ext = g;
    g->defw = afg_get_int(n, "colwidth") > 8 ? afg_get_int(n, "colwidth") : 64;
    g->frows = afg_get_int(n, "fixedrows");
    g->fcols = afg_get_int(n, "fixedcols");
    g->editable = afg_get_bool(n, "editable");
    g->redraw = 1;
    g->row = g->frows;
    g->col = g->fcols;
    resize_grid(g, afg_get_int(n, "rows"), afg_get_int(n, "cols"));
    /* row height from the screen's font */
    struct Screen *scr = bbf_lock_form_screen(f);
    g->rowh = (f->tattr ? f->tattr->ta_YSize : scr && scr->Font ? scr->Font->ta_YSize : 13) + 5;
    bbf_unlock_form_screen(f, scr);
    /* fixed row/column titles as VB shows them: A, B, C... and 1, 2, 3... when asked */
    if (afg_get_bool(n, "headers")) {
        for (int k = g->fcols; k < g->cols; k++) {
            char b[8];
            int v = k - g->fcols;
            if (v < 26) snprintf(b, sizeof b, "%c", 'A' + v);
            else snprintf(b, sizeof b, "%c%c", 'A' + v / 26 - 1, 'A' + v % 26);
            if (g->frows) set_cell(g, 0, k, b);
        }
        for (int r = g->frows; r < g->rows; r++) {
            char b[12];
            snprintf(b, sizeof b, "%d", r - g->frows + 1);
            if (g->fcols) set_cell(g, r, 0, b);
        }
        if (g->fcols) g->colw[0] = g->defw / 2 + 8;
    }
    (void)f;
    tags at = { 0 };
    tg(&at, SPACE_MinWidth, afg_has(n, "width") ? afg_get_int(n, "width") : 200);
    tg(&at, SPACE_MinHeight, afg_has(n, "height") ? afg_get_int(n, "height") : g->rowh * 6);
    tg(&at, SPACE_Transparent, TRUE);
    g->area = new_obj(C_SPACE, &at);
    tags vt = { 0 };
    tg(&vt, GA_ID, c->gid | (1 << BBF_PART_SHIFT));
    tg(&vt, GA_RelVerify, TRUE);
    tg(&vt, ICA_TARGET, ICTARGET_IDCMP);
    tg(&vt, SCROLLER_Orientation, SORIENT_VERT);
    tg(&vt, SCROLLER_Arrows, TRUE);
    g->vs = new_obj(C_SCROLLER, &vt);
    tags ht = { 0 };
    tg(&ht, GA_ID, c->gid | (2 << BBF_PART_SHIFT));
    tg(&ht, GA_RelVerify, TRUE);
    tg(&ht, ICA_TARGET, ICTARGET_IDCMP);
    tg(&ht, SCROLLER_Orientation, SORIENT_HORIZ);
    tg(&ht, SCROLLER_Arrows, TRUE);
    g->hs = new_obj(C_SCROLLER, &ht);
    if (!g->area || !g->vs || !g->hs) {
        if (g->area) IIntuition->DisposeObject(g->area);
        if (g->vs) IIntuition->DisposeObject(g->vs);
        if (g->hs) IIntuition->DisposeObject(g->hs);
        g->area = g->vs = g->hs = NULL;
        return NULL;
    }
    tags rt = { 0 };
    tg(&rt, LAYOUT_Orientation, LAYOUT_ORIENT_HORIZ);
    tg(&rt, LAYOUT_SpaceInner, FALSE);
    tg(&rt, LAYOUT_AddChild, (uint32)g->area);
    tg(&rt, LAYOUT_AddChild, (uint32)g->vs);
    tg(&rt, CHILD_WeightedWidth, 0);
    Object *row = new_obj(C_LAYOUT, &rt);
    tg(t, LAYOUT_Orientation, LAYOUT_ORIENT_VERT);
    tg(t, LAYOUT_SpaceInner, FALSE);
    tg(t, LAYOUT_BevelStyle, BVS_FIELD);
    tg(t, LAYOUT_AddChild, (uint32)row);
    tg(t, LAYOUT_AddChild, (uint32)g->hs);
    tg(t, CHILD_WeightedHeight, 0);
    return new_obj(C_LAYOUT, t);
}

void bbf_grid_free(bb_ctl *c)
{
    grid *g = c->ext;
    if (!g) return;
    release_pens(g);
    for (int i = 0; i < g->rows * g->cols; i++) free(g->cells[i]);
    free(g->cells);
    free(g->fg);
    free(g->bg);
    free(g->bold);
    free(g->colw);
    free(g->align);
    free(g);
    c->ext = NULL;
}

/* --- events -------------------------------------------------------------------------------- */

void bbf_grid_update(bb_form *f, bb_ctl *c, uint16 part)
{
    grid *g = G(c);
    (void)f;
    if (part == 1) {
        uint32 v = 0;
        IIntuition->GetAttr(SCROLLER_Top, g->vs, &v);
        if ((int)v + g->frows != g->toprow) {
            g->toprow = v + g->frows;
            draw_all(c);
            fire0(c, "Scroll");
        }
    } else if (part == 2) {
        uint32 v = 0;
        IIntuition->GetAttr(SCROLLER_Top, g->hs, &v);
        if ((int)v + g->fcols != g->leftcol) {
            g->leftcol = v + g->fcols;
            draw_all(c);
            fire0(c, "Scroll");
        }
    }
}

void bbf_grid_gadget_up(bb_form *f, bb_ctl *c, uint16 code)
{
    (void)code;
    bbf_grid_update(f, c, bbf_last_part);
}

/* the cell under a window position; 0 if none */
static int hit(bb_ctl *c, int x, int y, int *r, int *k)
{
    grid *g = G(c);
    int ax, ay, aw, ah;
    if (!area_box(c, &ax, &ay, &aw, &ah) || x < ax || y < ay || x >= ax + aw || y >= ay + ah) return 0;
    *r = *k = -1;
    for (int i = 0; i < g->rows; i++) {
        int yy = row_y(g, i, ay);
        if (yy >= 0 && y >= yy && y < yy + g->rowh) { *r = i; break; }
    }
    for (int i = 0; i < g->cols; i++) {
        int xx = col_x(g, i, ax);
        if (xx >= 0 && x >= xx && x < xx + g->colw[i]) { *k = i; break; }
    }
    return *r >= 0 && *k >= 0;
}

int bbf_grid_mouse(bb_ctl *c, int down, int up, int move, int x, int y, uint32 qual, uint32 secs, uint32 micros)
{
    grid *g = G(c);
    int r, k;
    (void)up;
    if (down) {
        if (!hit(c, x, y, &r, &k)) return 0;
        int was = g->focus;
        g->focus = 1;
        if (!was) draw_cell(c, g->row, g->col);
        int dbl = r == g->lrow && k == g->lcol && IIntuition->DoubleClick(g->lsecs, g->lmicros, secs, micros);
        g->lrow = r;
        g->lcol = k;
        g->lsecs = secs;
        g->lmicros = micros;
        if (r < g->frows && k >= g->fcols) {        /* a column title: select the column */
            commit_edit(c);
            move_to(c, g->frows, k, 0);
            select_range(c, g->frows, k, g->rows - 1, k);
            fire0(c, "Click");
            return 1;
        }
        if (k < g->fcols && r >= g->frows) {        /* a row title: the row */
            commit_edit(c);
            move_to(c, r, g->fcols, 0);
            select_range(c, r, g->fcols, r, g->cols - 1);
            fire0(c, "Click");
            return 1;
        }
        move_to(c, r, k, (qual & (IEQUALIFIER_LSHIFT | IEQUALIFIER_RSHIFT)) != 0);
        g->dragging = 1;
        if (!ending) fire0(c, "Click");
        if (dbl && !ending) {
            fire0(c, "DblClick");
            if (!ending) start_edit(c, NULL);
        }
        return 1;
    }
    if (move && g->dragging) {
        if (hit(c, x, y, &r, &k) && r >= g->frows && k >= g->fcols && (r != g->sr2 || k != g->sc2)) select_range(c, g->sr1, g->sc1, r, k);
        return 1;
    }
    if (up) g->dragging = 0;
    return 0;
}

/* a key while the grid has the focus: 1 = handled */
int bbf_grid_key(bb_ctl *c, int raw, uint32 qual)
{
    grid *g = G(c);
    if (!g->focus) return 0;
    int32_t a[2] = { bbf_vb_key(raw), bbf_vb_shift(qual) };
    fire(c->form, c->name, "KeyDown", 2, a);
    if (!a[0] || ending) return 1;
    int shift = (qual & (IEQUALIFIER_LSHIFT | IEQUALIFIER_RSHIFT)) != 0;
    int pg = vis_rows(c);
    if (g->editing) {
        int n = strlen(g->ebuf);
        switch (raw) {
        case 0x44: case 0x43: commit_edit(c); if (!ending) move_to(c, g->row + 1, g->col, 0); return 1;   /* Return */
        case 0x42: commit_edit(c); if (!ending) move_to(c, g->row, g->col + (shift ? -1 : 1), 0); return 1; /* Tab */
        case 0x45: cancel_edit(c); return 1;                                       /* Esc */
        case 0x4C: commit_edit(c); if (!ending) move_to(c, g->row - 1, g->col, 0); return 1;
        case 0x4D: commit_edit(c); if (!ending) move_to(c, g->row + 1, g->col, 0); return 1;
        case 0x4F: if (g->ecur > 0) g->ecur--; draw_cell(c, g->row, g->col); return 1;
        case 0x4E: if (g->ecur < n) g->ecur++; draw_cell(c, g->row, g->col); return 1;
        case 0x41:                                                                  /* Backspace */
            if (g->ecur > 0) {
                memmove(g->ebuf + g->ecur - 1, g->ebuf + g->ecur, n - g->ecur + 1);
                g->ecur--;
                draw_cell(c, g->row, g->col);
            }
            return 1;
        case 0x46:                                                                  /* Del */
            if (g->ecur < n) {
                memmove(g->ebuf + g->ecur, g->ebuf + g->ecur + 1, n - g->ecur);
                draw_cell(c, g->row, g->col);
            }
            return 1;
        }
        int ch = bbf_map_key(raw, qual);
        if (ch >= 32 && n < (int)sizeof g->ebuf - 1) {
            memmove(g->ebuf + g->ecur + 1, g->ebuf + g->ecur, n - g->ecur + 1);
            g->ebuf[g->ecur++] = ch;
            draw_cell(c, g->row, g->col);
            return 1;
        }
        return 1;
    }
    switch (raw) {
    case 0x4C: move_to(c, g->row - 1, g->col, shift); return 1;            /* up */
    case 0x4D: move_to(c, g->row + 1, g->col, shift); return 1;            /* down */
    case 0x4F: move_to(c, g->row, g->col - 1, shift); return 1;            /* left */
    case 0x4E: move_to(c, g->row, g->col + 1, shift); return 1;            /* right */
    case 0x42: move_to(c, g->row, g->col + (shift ? -1 : 1), 0); return 1; /* Tab */
    case 0x44: case 0x43: move_to(c, g->row + 1, g->col, 0); return 1;     /* Return */
    case 0x48: move_to(c, g->row - pg, g->col, shift); return 1;           /* PageUp */
    case 0x49: move_to(c, g->row + pg, g->col, shift); return 1;           /* PageDown */
    case 0x70: move_to(c, g->row, g->fcols, shift); return 1;              /* Home */
    case 0x71: move_to(c, g->row, g->cols - 1, shift); return 1;           /* End */
    case 0x50: start_edit(c, NULL); return 1;                              /* F1 = F2 on PCs */
    case 0x51: start_edit(c, NULL); return 1;                              /* F2 */
    case 0x46:                                                             /* Del: clear the cells */
        if (g->editable) {
            int r1 = g->sr1 < g->sr2 ? g->sr1 : g->sr2, r2 = g->sr1 ^ g->sr2 ^ r1;
            int c1 = g->sc1 < g->sc2 ? g->sc1 : g->sc2, c2 = g->sc1 ^ g->sc2 ^ c1;
            for (int r = r1; r <= r2; r++)
                for (int k = c1; k <= c2; k++) {
                    set_cell(g, r, k, "");
                    draw_cell(c, r, k);
                }
            int32_t a[2] = { g->row, g->col };
            fire(c->form, c->name, "AfterEdit", 2, a);
        }
        return 1;
    }
    int ch = bbf_map_key(raw, qual);
    if (ch >= 32 && !(qual & (IEQUALIFIER_LCOMMAND | IEQUALIFIER_RCOMMAND))) {
        char s[2] = { (char)ch, 0 };
        start_edit(c, s);
        return 1;
    }
    return 0;
}

void bbf_grid_blur(bb_ctl *c)
{
    grid *g = G(c);
    if (!g || !g->focus) return;
    commit_edit(c);
    g->focus = 0;
    g->dragging = 0;
    draw_cell(c, g->row, g->col);
}

int bbf_grid_focused(bb_ctl *c) { return G(c) && G(c)->focus; }

/* --- properties ---------------------------------------------------------------------------- */

#define IS(a) (!strcasecmp(prop, a))

int bbf_grid_get(bb_ctl *c, const char *prop, int index, bb_fval *out)
{
    grid *g = G(c);
    if (IS("Rows")) return ret_int(out, g->rows);
    if (IS("Cols")) return ret_int(out, g->cols);
    if (IS("FixedRows")) return ret_int(out, g->frows);
    if (IS("FixedCols")) return ret_int(out, g->fcols);
    if (IS("Row")) return ret_int(out, g->row);
    if (IS("Col")) return ret_int(out, g->col);
    if (IS("Text")) return ret_str(c, out, g->editing ? g->ebuf : cell_text(g, g->row, g->col));
    if (IS("TopRow")) return ret_int(out, g->toprow);
    if (IS("LeftCol")) return ret_int(out, g->leftcol);
    if (IS("RowHeight")) return ret_int(out, g->rowh);
    if (IS("Editable")) return ret_int(out, vb_bool(g->editable));
    if (IS("Redraw")) return ret_int(out, vb_bool(g->redraw));
    if (IS("Editing")) return ret_int(out, vb_bool(g->editing));
    if (IS("SelStartRow")) return ret_int(out, g->sr1 < g->sr2 ? g->sr1 : g->sr2);
    if (IS("SelEndRow")) return ret_int(out, g->sr1 < g->sr2 ? g->sr2 : g->sr1);
    if (IS("SelStartCol")) return ret_int(out, g->sc1 < g->sc2 ? g->sc1 : g->sc2);
    if (IS("SelEndCol")) return ret_int(out, g->sc1 < g->sc2 ? g->sc2 : g->sc1);
    if (IS("ColWidth")) {
        if (index < 0 || index >= g->cols) return 381;
        return ret_int(out, g->colw[index]);
    }
    if (IS("ColAlignment")) {
        if (index < 0 || index >= g->cols) return 381;
        return ret_int(out, g->align[index] < 0 ? 0 : g->align[index]);
    }
    if (IS("CellBold") || IS("CellForeColor") || IS("CellBackColor")) {
        bb_fval tmp;
        int e = bbf_grid_get2(c, prop, g->row, g->col, &tmp);
        *out = tmp;
        return e;
    }
    return 438;
}

int bbf_grid_set(bb_ctl *c, const char *prop, int index, const bb_fval *v)
{
    grid *g = G(c);
    char buf[16];
    int n = vint(v);
    if (IS("Rows") || IS("Cols")) {
        if (n < 0 || n > 100000) return 380;
        cancel_edit(c);
        resize_grid(g, IS("Rows") ? n : g->rows, IS("Cols") ? n : g->cols);
        draw_all(c);
        return 0;
    }
    if (IS("FixedRows")) { if (n < 0 || n > g->rows) return 380; g->frows = n; resize_grid(g, g->rows, g->cols); draw_all(c); return 0; }
    if (IS("FixedCols")) { if (n < 0 || n > g->cols) return 380; g->fcols = n; resize_grid(g, g->rows, g->cols); draw_all(c); return 0; }
    if (IS("Row")) { if (n < 0 || n >= g->rows) return 380; move_to(c, n, g->col, 0); return 0; }
    if (IS("Col")) { if (n < 0 || n >= g->cols) return 380; move_to(c, g->row, n, 0); return 0; }
    if (IS("Text")) {
        cancel_edit(c);
        /* VB: Text sets every selected cell */
        int r1 = g->sr1 < g->sr2 ? g->sr1 : g->sr2, r2 = g->sr1 ^ g->sr2 ^ r1;
        int c1 = g->sc1 < g->sc2 ? g->sc1 : g->sc2, c2 = g->sc1 ^ g->sc2 ^ c1;
        for (int r = r1; r <= r2; r++)
            for (int k = c1; k <= c2; k++) {
                set_cell(g, r, k, vstr(v, buf));
                draw_cell(c, r, k);
            }
        return 0;
    }
    if (IS("TopRow")) {
        if (n < g->frows) n = g->frows;
        if (n >= g->rows) n = g->rows - 1;
        g->toprow = n;
        draw_all(c);
        return 0;
    }
    if (IS("LeftCol")) {
        if (n < g->fcols) n = g->fcols;
        if (n >= g->cols) n = g->cols - 1;
        g->leftcol = n;
        draw_all(c);
        return 0;
    }
    if (IS("RowHeight")) { if (n < 6 || n > 200) return 380; g->rowh = n; draw_all(c); return 0; }
    if (IS("Editable")) { g->editable = n != 0; if (!g->editable) cancel_edit(c); return 0; }
    if (IS("Redraw")) { g->redraw = n != 0; if (g->redraw) draw_all(c); return 0; }
    if (IS("ColWidth")) {
        if (index < -1 || index >= g->cols || n < 0 || n > 2000) return index < -1 || index >= g->cols ? 381 : 380;
        if (index == -1) for (int k = 0; k < g->cols; k++) g->colw[k] = n;     /* ColWidth = n: every column */
        else g->colw[index] = n;
        draw_all(c);
        return 0;
    }
    if (IS("ColAlignment")) {
        if (index < 0 || index >= g->cols) return 381;
        g->align[index] = n < 0 || n > 2 ? -1 : n;
        draw_all(c);
        return 0;
    }
    if (IS("CellBold") || IS("CellForeColor") || IS("CellBackColor")) return bbf_grid_set2(c, prop, g->row, g->col, v);
    if (IS("SelStartRow") || IS("SelEndRow") || IS("SelStartCol") || IS("SelEndCol")) {
        if (IS("SelStartRow")) g->sr1 = n;
        if (IS("SelEndRow")) g->sr2 = n;
        if (IS("SelStartCol")) g->sc1 = n;
        if (IS("SelEndCol")) g->sc2 = n;
        draw_all(c);
        return 0;
    }
    if (IS("Editing")) return 383;
    return 438;
}

int bbf_grid_get2(bb_ctl *c, const char *prop, int i, int j, bb_fval *out)
{
    grid *g = G(c);
    if (c->kind != AFG_GRID) return 438;
    if (i < 0 || j < 0 || i >= g->rows || j >= g->cols) return 381;
    if (IS("TextMatrix") || IS("Cell")) return ret_str(c, out, cell_text(g, i, j));
    if (IS("CellBold")) return ret_int(out, vb_bool(g->bold[IDX(g, i, j)]));
    if (IS("CellForeColor")) return ret_int(out, g->fg[IDX(g, i, j)] < 0 ? 0 : g->fg[IDX(g, i, j)]);
    if (IS("CellBackColor")) return ret_int(out, g->bg[IDX(g, i, j)] < 0 ? 0xFFFFFF : g->bg[IDX(g, i, j)]);
    return 438;
}

int bbf_grid_set2(bb_ctl *c, const char *prop, int i, int j, const bb_fval *v)
{
    grid *g = G(c);
    char buf[16];
    if (c->kind != AFG_GRID) return 438;
    if (i < 0 || j < 0 || i >= g->rows || j >= g->cols) return 381;
    if (IS("TextMatrix") || IS("Cell")) {
        if (g->editing && i == g->row && j == g->col) cancel_edit(c);
        set_cell(g, i, j, vstr(v, buf));
    } else if (IS("CellBold")) g->bold[IDX(g, i, j)] = vint(v) != 0;
    else if (IS("CellForeColor")) g->fg[IDX(g, i, j)] = vint(v) & 0xFFFFFF;
    else if (IS("CellBackColor")) g->bg[IDX(g, i, j)] = vint(v) & 0xFFFFFF;
    else return 438;
    draw_cell(c, i, j);
    return 0;
}

#undef IS
#define IS(a) (!strcasecmp(method, a))

int bbf_grid_call(bb_ctl *c, const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    grid *g = G(c);
    char b0[16];
    (void)ret;
    if (IS("Clear")) {
        cancel_edit(c);
        for (int r = g->frows; r < g->rows; r++)
            for (int k = g->fcols; k < g->cols; k++) set_cell(g, r, k, "");
        draw_all(c);
        return 0;
    }
    if (IS("AddItem")) {          /* AddItem "a" & vbTab & "b" [, row]: a new row */
        if (argc < 1) return 450;
        int at = argc > 1 && argv[1].type != BB_FV_NONE ? vint(&argv[1]) : g->rows;
        if (at < g->frows || at > g->rows) return 5;
        cancel_edit(c);
        resize_grid(g, g->rows + 1, g->cols);
        for (int r = g->rows - 1; r > at; r--)
            for (int k = 0; k < g->cols; k++) {
                int d = IDX(g, r, k), s = IDX(g, r - 1, k);
                free(g->cells[d]);
                g->cells[d] = g->cells[s];
                g->cells[s] = NULL;
                g->fg[d] = g->fg[s];
                g->bg[d] = g->bg[s];
                g->bold[d] = g->bold[s];
            }
        const char *s = vstr(&argv[0], b0);
        for (int k = 0; k < g->cols; k++) {
            const char *e = strchr(s, '\t');
            size_t l = e ? (size_t)(e - s) : strlen(s);
            char *cellt = malloc(l + 1);
            memcpy(cellt, s, l);
            cellt[l] = 0;
            set_cell(g, at, k, cellt);
            free(cellt);
            g->fg[IDX(g, at, k)] = g->bg[IDX(g, at, k)] = -1;
            g->bold[IDX(g, at, k)] = 0;
            if (!e) {
                for (k++; k < g->cols; k++) set_cell(g, at, k, "");
                break;
            }
            s = e + 1;
        }
        draw_all(c);
        return 0;
    }
    if (IS("RemoveItem")) {
        if (argc < 1) return 450;
        int at = vint(&argv[0]);
        if (at < g->frows || at >= g->rows) return 5;
        cancel_edit(c);
        for (int r = at; r < g->rows - 1; r++)
            for (int k = 0; k < g->cols; k++) {
                int d = IDX(g, r, k), s = IDX(g, r + 1, k);
                free(g->cells[d]);
                g->cells[d] = g->cells[s];
                g->cells[s] = NULL;
                g->fg[d] = g->fg[s];
                g->bg[d] = g->bg[s];
                g->bold[d] = g->bold[s];
            }
        resize_grid(g, g->rows - 1, g->cols);
        draw_all(c);
        return 0;
    }
    if (IS("EditCell")) {         /* start editing the current cell from code */
        start_edit(c, NULL);
        return 0;
    }
    if (IS("Refresh")) {
        draw_all(c);
        return 0;
    }
    return 438;
}
