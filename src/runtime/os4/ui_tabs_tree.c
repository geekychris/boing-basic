/* Tabs (clicktab.gadget with a page.gadget of the child layouts) and TreeView (a hierarchical
 * listbrowser), docs/ui.md section 4. */
#include "forms_int.h"
#include <gadgets/clicktab.h>

/* --- tabs ---------------------------------------------------------------------------------- */

Object *bbf_tabs_build(bb_form *f, afg_node *n, bb_ctl *c, tags *t)
{
    tags pt = { 0 };
    int np = 0;
    c->labelarray = calloc(n->nchildren + 1, sizeof *c->labelarray);
    c->panels = calloc(n->nchildren + 1, sizeof *c->panels);   /* the page layouts */
    for (int i = 0; i < n->nchildren; i++) {
        afg_node *page = n->children[i];
        Object *o = bbf_build(f, page);
        if (!o) continue;
        c->panels[c->npanels++] = o;
        bbf_items_insert(c, -1, afg_has(page, "title") ? afg_get(page, "title") : "Page");
        tg(&pt, PAGE_Add, (uint32)o);
        np++;
    }
    for (int i = 0; i < c->nitems; i++) c->labelarray[i] = c->items[i];
    tg(&pt, LAYOUT_DeferLayout, TRUE);
    tg(&pt, TAG_DONE, 0);
    Object *pg = IIntuition->NewObjectA(NULL, "page.gadget", pt.t);
    free(pt.t);
    if (!pg) return NULL;
    c->sel = afg_get_int(n, "selected");
    if (c->sel < 0 || c->sel >= np) c->sel = 0;
    IIntuition->SetAttrs(pg, PAGE_Current, c->sel, TAG_DONE);
    c->img = NULL;
    c->ext = pg;              /* the page group (disposed with the clicktab) */
    bbf_gadget_tags(c, t);
    tg(t, GA_Text, (uint32)c->labelarray);
    tg(t, CLICKTAB_Current, c->sel);
    tg(t, CLICKTAB_PageGroup, (uint32)pg);
    return new_obj(C_CLICKTAB, t);
}

static void tabs_select(bb_ctl *c, int i)
{
    c->sel = i;
    set_attr(c, CLICKTAB_Current, i);
    if (c->ext) {
        struct TagItem t[2] = { { PAGE_Current, (uint32)i }, { TAG_DONE, 0 } };
        if (c->form->win) IIntuition->SetGadgetAttrsA((struct Gadget *)c->ext, c->form->win, NULL, t);
        else IIntuition->SetAttrsA(c->ext, t);
        relayout(c->form);
    }
}

#define IS(a) (!strcasecmp(prop, a))

static int tabs_get(bb_ctl *c, const char *prop, int index, bb_fval *out)
{
    if (IS("Tab") || IS("Value") || IS("ListIndex")) return ret_int(out, (int32)get_attr(c, CLICKTAB_Current));
    if (IS("TabCount")) return ret_int(out, c->nitems);
    if (IS("PageFramed")) {        /* was page i given a frame title of its own? (tests: never) */
        if (index < 0 || index >= c->node->nchildren) return 381;
        return ret_int(out, vb_bool(afg_get_bool(c->node->children[index], "_framed")));
    }
    if (IS("TabCaption")) {
        if (index < 0 || index >= c->nitems) return 381;
        return ret_str(c, out, c->items[index]);
    }
    return 438;
}

static int tabs_set(bb_ctl *c, const char *prop, int index, const bb_fval *v)
{
    char buf[16];
    if (IS("Tab") || IS("Value") || IS("ListIndex")) {
        int i = vint(v);
        if (i < 0 || i >= c->nitems) return 380;
        tabs_select(c, i);
        fire0(c, "Click");
        return 0;
    }
    if (IS("TabCaption")) {
        if (index < 0 || index >= c->nitems) return 381;
        free(c->items[index]);
        c->items[index] = xstrdup(vstr(v, buf));
        c->labelarray[index] = c->items[index];
        set_attr(c, GA_Text, (uint32)c->labelarray);
        return 0;
    }
    if (IS("TabCount")) return 383;
    return 438;
}

/* --- treeview ------------------------------------------------------------------------------ */

typedef struct tnode {
    char *key, *text;
    int parent;               /* index, -1 = a root */
    int expanded;
    int dead;
} tnode;

typedef struct tree {
    tnode *n;
    int count, cap;
    int *order;               /* list position -> node index (depth first) */
    int norder;
    char *eventkey;
} tree;

static tree *T(bb_ctl *c)
{
    if (!c->ext) c->ext = calloc(1, sizeof(tree));
    return c->ext;
}

static int tfind(tree *t, const char *key)
{
    for (int i = 0; i < t->count; i++)
        if (!t->n[i].dead && !strcmp(t->n[i].key, key)) return i;
    return -1;
}

static int has_children(tree *t, int i)
{
    for (int k = 0; k < t->count; k++)
        if (!t->n[k].dead && t->n[k].parent == i) return 1;
    return 0;
}

static int depth_of(tree *t, int i)
{
    int d = 1;
    while (t->n[i].parent >= 0) {
        i = t->n[i].parent;
        d++;
    }
    return d;
}

static int visible_node(tree *t, int i)
{
    for (int p = t->n[i].parent; p >= 0; p = t->n[p].parent)
        if (!t->n[p].expanded) return 0;
    return 1;
}

static void add_dfs(tree *t, int parent)
{
    for (int i = 0; i < t->count; i++)
        if (!t->n[i].dead && t->n[i].parent == parent) {
            t->order[t->norder++] = i;
            add_dfs(t, i);
        }
}

/* the listbrowser nodes from the tree (detached while rebuilt) */
static void tree_rebuild(bb_ctl *c)
{
    tree *t = T(c);
    if (!bbf_ILB) return;
    int selnode = -1;
    if (c->obj) {
        int s = (int)get_attr(c, LISTBROWSER_Selected);
        if (s >= 0 && s < t->norder) selnode = t->order[s];
        set_attr(c, LISTBROWSER_Labels, ~0u);
    }
    struct Node *nd;
    while ((nd = IExec->RemHead(&c->labels))) bbf_ILB->FreeListBrowserNode(nd);
    free(t->order);
    t->order = malloc((t->count + 1) * sizeof *t->order);
    t->norder = 0;
    add_dfs(t, -1);
    int newsel = -1;
    for (int k = 0; k < t->norder; k++) {
        int i = t->order[k];
        uint32 fl = 0;
        if (has_children(t, i)) fl |= LBFLG_HASCHILDREN | (t->n[i].expanded ? LBFLG_SHOWCHILDREN : 0);
        if (!visible_node(t, i)) fl |= LBFLG_HIDDEN;
        nd = bbf_ILB->AllocListBrowserNode(1, LBNA_Generation, depth_of(t, i), LBNA_Flags, fl, LBNA_UserData, i,
                                           LBNCA_CopyText, TRUE, LBNCA_Text, (uint32)t->n[i].text, TAG_DONE);
        if (nd) IExec->AddTail(&c->labels, nd);
        if (i == selnode) newsel = k;
    }
    if (c->obj) {
        struct TagItem tl[3] = { { LISTBROWSER_Labels, (uint32)&c->labels }, { LISTBROWSER_Selected, (uint32)newsel }, { TAG_DONE, 0 } };
        if (c->form->win) IIntuition->SetGadgetAttrsA((struct Gadget *)c->obj, c->form->win, NULL, tl);
        else IIntuition->SetAttrsA(c->obj, tl);
    }
}

Object *bbf_tree_build(bb_form *f, afg_node *n, bb_ctl *c, tags *t)
{
    (void)f; (void)n;
    T(c);
    tree_rebuild(c);
    bbf_gadget_tags(c, t);
    tg(t, LISTBROWSER_Labels, (uint32)&c->labels);
    tg(t, LISTBROWSER_Hierarchical, TRUE);
    tg(t, LISTBROWSER_ShowSelected, TRUE);
    tg(t, LISTBROWSER_Selected, (uint32)-1);
    return new_obj(C_LISTBROWSER, t);
}

void bbf_tree_free(bb_ctl *c)
{
    tree *t = c->ext;
    if (!t) return;
    struct Node *nd;
    while ((nd = IExec->RemHead(&c->labels)))
        if (bbf_ILB) bbf_ILB->FreeListBrowserNode(nd);
    for (int i = 0; i < t->count; i++) {
        free(t->n[i].key);
        free(t->n[i].text);
    }
    free(t->n);
    free(t->order);
    free(t->eventkey);
    free(t);
    c->ext = NULL;
}

static void set_eventkey(tree *t, int i)
{
    free(t->eventkey);
    t->eventkey = xstrdup(i >= 0 ? t->n[i].key : "");
}

/* GADGETUP: a click (NodeClick), a double click, or the user opened / closed a node */
void bbf_tree_gadget_up(bb_form *f, bb_ctl *c)
{
    tree *t = T(c);
    uint32 rel = get_attr(c, LISTBROWSER_RelEvent);
    int s = (int)get_attr(c, LISTBROWSER_Selected);
    struct Node *sn = (struct Node *)get_attr(c, LISTBROWSER_SelectedNode);
    int i = -1;
    if (sn && bbf_ILB) {
        uint32 ud = 0;
        bbf_ILB->GetListBrowserNodeAttrs(sn, LBNA_UserData, &ud, TAG_DONE);
        i = (int)ud;
    } else if (s >= 0 && s < t->norder)
        i = t->order[s];
    if (i < 0 || i >= t->count) return;
    set_eventkey(t, i);
    if (rel & (LBRE_SHOWCHILDREN | LBRE_HIDECHILDREN)) {
        t->n[i].expanded = (rel & LBRE_SHOWCHILDREN) != 0;
        fire0(c, t->n[i].expanded ? "Expand" : "Collapse");
        return;
    }
    fire0(c, "NodeClick");
    if (!ending && f->loaded) fire0(c, "Click");
    if (!ending && f->loaded && (rel & LBRE_DOUBLECLICK)) fire0(c, "DblClick");
}

static int tree_get(bb_ctl *c, const char *prop, bb_fval *out)
{
    tree *t = T(c);
    if (IS("NodeCount")) {
        int k = 0;
        for (int i = 0; i < t->count; i++) k += !t->n[i].dead;
        return ret_int(out, k);
    }
    if (IS("SelectedKey")) {
        int s = (int)get_attr(c, LISTBROWSER_Selected);
        return ret_str(c, out, s >= 0 && s < t->norder ? t->n[t->order[s]].key : "");
    }
    if (IS("EventKey")) return ret_str(c, out, t->eventkey);
    return 438;
}

static int tree_set(bb_ctl *c, const char *prop, const bb_fval *v)
{
    tree *t = T(c);
    char buf[16];
    if (IS("SelectedKey")) {
        int i = tfind(t, vstr(v, buf));
        if (i < 0) return 380;
        /* open its parents so it can be seen */
        int changed = 0;
        for (int p = t->n[i].parent; p >= 0; p = t->n[p].parent)
            if (!t->n[p].expanded) t->n[p].expanded = changed = 1;
        if (changed) tree_rebuild(c);
        for (int k = 0; k < t->norder; k++)
            if (t->order[k] == i) {
                set_attr(c, LISTBROWSER_Selected, k);
                set_attr(c, LISTBROWSER_MakeVisible, k);
            }
        set_eventkey(t, i);
        fire0(c, "NodeClick");
        return 0;
    }
    if (IS("NodeCount") || IS("EventKey")) return 383;
    return 438;
}

#undef IS
#define IS(a) (!strcasecmp(method, a))

static void remove_rec(tree *t, int i)
{
    t->n[i].dead = 1;
    for (int k = 0; k < t->count; k++)
        if (!t->n[k].dead && t->n[k].parent == i) remove_rec(t, k);
}

static int tree_call(bb_ctl *c, const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    tree *t = T(c);
    char b0[16], b1[16], b2[16];
    if (IS("AddNode")) {          /* AddNode key, parent, text */
        if (argc < 3) return 450;
        const char *key = vstr(&argv[0], b0), *par = argv[1].type == BB_FV_NONE ? "" : vstr(&argv[1], b1);
        if (!*key || tfind(t, key) >= 0) return 457;      /* VB: "This key is already associated" */
        int p = *par ? tfind(t, par) : -1;
        if (*par && p < 0) return 35601;                  /* VB TreeView: "Element not found" */
        if (t->count == t->cap) {
            t->cap = t->cap ? t->cap * 2 : 16;
            t->n = realloc(t->n, t->cap * sizeof *t->n);
        }
        tnode *nn = &t->n[t->count++];
        nn->key = xstrdup(key);
        nn->text = xstrdup(vstr(&argv[2], b2));
        nn->parent = p;
        nn->expanded = 0;
        nn->dead = 0;
        tree_rebuild(c);
        return ret_int(ret, t->count - 1);
    }
    if (IS("RemoveNode")) {
        if (argc < 1) return 450;
        int i = tfind(t, vstr(&argv[0], b0));
        if (i < 0) return 35601;
        remove_rec(t, i);
        tree_rebuild(c);
        return 0;
    }
    if (IS("Clear")) {
        for (int i = 0; i < t->count; i++) t->n[i].dead = 1;
        tree_rebuild(c);
        return 0;
    }
    if (IS("Expand") || IS("Collapse")) {
        if (argc < 1) return 450;
        int i = tfind(t, vstr(&argv[0], b0));
        if (i < 0) return 35601;
        t->n[i].expanded = IS("Expand");
        tree_rebuild(c);
        return 0;
    }
    if (IS("NodeText") || IS("NodeParent") || IS("NodeExpanded")) {     /* as methods: NodeText(key) */
        if (argc < 1) return 450;
        int i = tfind(t, vstr(&argv[0], b0));
        if (i < 0) return 35601;
        if (argc >= 2 && IS("NodeText")) {           /* tv.NodeText key, "new text" */
            free(t->n[i].text);
            t->n[i].text = xstrdup(vstr(&argv[1], b1));
            tree_rebuild(c);
            return 0;
        }
        if (IS("NodeText")) return ret_str(c, ret, t->n[i].text);
        if (IS("NodeExpanded")) return ret_int(ret, vb_bool(t->n[i].expanded));
        return ret_str(c, ret, t->n[i].parent >= 0 ? t->n[t->n[i].parent].key : "");
    }
    return 438;
}

/* --- dispatch ------------------------------------------------------------------------------ */

int bbf_tt_get(bb_ctl *c, const char *prop, int index, bb_fval *out)
{
    if (c->kind == AFG_TABS) return tabs_get(c, prop, index, out);
    if (c->kind == AFG_TREEVIEW) return tree_get(c, prop, out);
    return 438;
}

int bbf_tt_set(bb_ctl *c, const char *prop, int index, const bb_fval *v)
{
    if (c->kind == AFG_TABS) return tabs_set(c, prop, index, v);
    if (c->kind == AFG_TREEVIEW) return tree_set(c, prop, v);
    return 438;
}

int bbf_tt_call(bb_ctl *c, const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    if (c->kind == AFG_TREEVIEW) return tree_call(c, method, argc, argv, ret);
    return 438;
}

void bbf_tt_gadget_up(bb_form *f, bb_ctl *c, uint16 code)
{
    if (c->kind == AFG_TABS) {
        c->sel = code;
        fire0(c, "Click");
    } else if (c->kind == AFG_TREEVIEW)
        bbf_tree_gadget_up(f, c);
}
