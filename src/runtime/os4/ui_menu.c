/* Menus of a form on Intuition's BOOPSI menuclass (V54.6+), docs/ui.md section 1.
 *
 * The .afg's top-level `menu` trees (after the root layout) become one menu strip
 * (WINDOW_MenuStrip). A top-level menu with hidden=1 is not in the strip: it gets a strip of
 * its own, used as a context menu (WA_ContextMenuHook, the right mouse button over a control
 * whose contextmenu= names it) and by Me.PopupMenu. Every menu object is a bb_ctl whose gid
 * is its MA_ID, so ctl_by_gid finds it on a pick. */
#include "forms_int.h"
#include <proto/graphics.h>

/* "_Open..." -> "Open..." (the .afg marks shortcuts of gadgets with _, menus have MA_Key) */
char *bbf_strip_underscore(const char *s)
{
    char *o = xstrdup(s ? s : ""), *d = o;
    for (const char *p = o; *p; p++)
        if (*p != '_') *d++ = *p;
    *d = 0;
    return o;
}

static int is_sep(afg_node *n) { return !strcmp(afg_get(n, "text"), "-") || afg_get_bool(n, "separator"); }

static bb_ctl *menu_ctl(bb_form *f, afg_node *n)
{
    for (int i = 0; i < f->nctls; i++)
        if (f->ctls[i]->node == n) return f->ctls[i];
    return NULL;
}

/* the MA_MX mask of a radio item: every other radio item of the same panel */
static uint32 mx_mask(afg_node *n)
{
    afg_node *p = n->parent;
    uint32 m = 0;
    for (int i = 0; i < p->nchildren && i < 32; i++)
        if (p->children[i] != n && afg_get_bool(p->children[i], "radio")) m |= 1u << i;
    return m;
}

/* one menu object (title or item) and its children */
static Object *build_menu(bb_form *f, afg_node *n, int level)
{
    bb_ctl *c = menu_ctl(f, n);
    tags t = { 0 };
    tg(&t, MA_Type, level == 0 ? T_MENU : T_ITEM);
    if (level > 0 && is_sep(n)) {
        tg(&t, MA_Separator, TRUE);
        if (afg_get_bool(n, "hidden")) tg(&t, MA_Hidden, TRUE);
    } else {
        if (c) {
            free(c->text);
            c->text = bbf_strip_underscore(afg_get(n, "text"));
            tg(&t, MA_Label, (uint32)c->text);
            tg(&t, MA_ID, c->gid);
        }
        if (level > 0 && afg_has(n, "key")) {
            if (c) {
                free(c->extra);
                c->extra = xstrdup(afg_get(n, "key"));
                tg(&t, MA_Key, (uint32)c->extra);
            }
        }
        if (afg_get_bool(n, "radio")) {
            tg(&t, MA_MX, mx_mask(n));
            tg(&t, MA_Selected, afg_get_bool(n, "checked"));
        } else if (afg_get_bool(n, "checkable") || afg_get_bool(n, "checked")) {
            tg(&t, MA_Toggle, TRUE);
            tg(&t, MA_Selected, afg_get_bool(n, "checked"));
        }
        if (afg_get_bool(n, "disabled")) tg(&t, MA_Disabled, TRUE);
        if (level > 0 && afg_get_bool(n, "hidden")) tg(&t, MA_Hidden, TRUE);
        for (int i = 0; i < n->nchildren; i++) {
            Object *k = build_menu(f, n->children[i], level + 1);
            if (k) tg(&t, MA_AddChild, (uint32)k);
        }
    }
    Object *o = new_obj(C_MENU, &t);
    if (c) c->obj = o;
    return o;
}

static Object *new_strip(void)
{
    tags t = { 0 };
    tg(&t, MA_Type, T_ROOT);
    return new_obj(C_MENU, &t);
}

static void add_child(Object *parent, Object *child)
{
    IIntuition->SetAttrs(parent, MA_AddChild, (uint32)child, TAG_DONE);
}

/* the control under the window's mouse position that names a context menu */
static bb_ctl *ctx_target(bb_form *f, int x, int y, const char **menu)
{
    bb_ctl *best = NULL;
    for (int i = 0; i < f->nctls; i++) {
        bb_ctl *c = f->ctls[i];
        if (!c->obj || !afg_takes_space(c->kind) || c->kind == AFG_TOOL || !c->visible || c->dead) continue;
        const char *m = c->ctxmenu ? c->ctxmenu : afg_get(c->node, "contextmenu");
        if (!m || !*m) continue;
        struct Gadget *g = (struct Gadget *)c->obj;
        if (x >= g->LeftEdge && y >= g->TopEdge && x < g->LeftEdge + g->Width && y < g->TopEdge + g->Height) {
            best = c;            /* later (inner) objects win */
            *menu = m;
        }
    }
    if (!best) {
        const char *m = f->self.ctxmenu ? f->self.ctxmenu : afg_get(f->afg, "contextmenu");
        if (m && *m) {
            best = &f->self;
            *menu = m;
        }
    }
    return best;
}

static bb_ctl *find_menu(bb_form *f, const char *name)
{
    for (int i = 0; i < f->nctls; i++)
        if (f->ctls[i]->kind == AFG_MENU && !f->ctls[i]->dead && !strcasecmp(f->ctls[i]->name, name)) return f->ctls[i];
    return NULL;
}

/* WA_ContextMenuHook: runs in Intuition's input handler, so it only reads */
static uint32 ctx_hook_func(struct Hook *h, struct Window *w, struct ContextMenuMsg *msg)
{
    bb_form *f = h->h_Data;
    if (msg->State != CM_QUERY || !f->loaded) return 0;
    const char *name = NULL;
    bb_ctl *c = ctx_target(f, w->MouseX, w->MouseY, &name);
    if (!c) return 0;
    bb_ctl *m = find_menu(f, name);
    if (!m || !m->strip) return 0;
    msg->Menu = m->strip;
    msg->Context = c;
    return 0;
}

int bbf_menus_build(bb_form *f, tags *wintags)
{
    afg_node *w = f->afg;
    int any = 0, anyctx = 0;
    for (int i = 1; i < w->nchildren; i++)
        if (w->children[i]->kind == AFG_MENU) any = 1;
    for (int i = 0; i < f->nctls; i++)
        if (f->ctls[i]->kind != AFG_MENU && afg_has(f->ctls[i]->node, "contextmenu")) anyctx = 1;
    if (afg_has(w, "contextmenu")) anyctx = 1;
    if (!any) return 1;
    f->menustrip = new_strip();
    if (!f->menustrip) return 0;
    for (int i = 1; i < w->nchildren; i++) {
        afg_node *n = w->children[i];
        if (n->kind != AFG_MENU) continue;
        Object *o = build_menu(f, n, 0);
        if (!o) continue;
        bb_ctl *c = menu_ctl(f, n);
        if (afg_get_bool(n, "hidden")) {
            /* a context / pop-up menu: a strip of its own */
            Object *s = new_strip();
            if (s) add_child(s, o);
            else IIntuition->DisposeObject(o);
            if (c) c->strip = s;
            if (s) anyctx = 1;
        } else
            add_child(f->menustrip, o);
    }
    tg(wintags, WINDOW_MenuStrip, (uint32)f->menustrip);
    if (anyctx) {
        f->ctx_hook.h_Entry = (HOOKFUNC)ctx_hook_func;
        f->ctx_hook.h_Data = f;
        tg(wintags, WA_ContextMenuHook, (uint32)&f->ctx_hook);
    }
    return 1;
}

void bbf_menus_free(bb_form *f)
{
    /* after the window object is gone */
    for (int i = 0; i < f->nctls; i++) {
        bb_ctl *c = f->ctls[i];
        if (c->kind == AFG_MENU && c->strip) {
            IIntuition->DisposeObject(c->strip);
            c->strip = NULL;
        }
    }
    if (f->menustrip) IIntuition->DisposeObject(f->menustrip);
    f->menustrip = NULL;
}

/* a pick: every selected id of the strip (multiple selection with the right button held) */
static void pick_strip(bb_form *f, Object *strip)
{
    uint32 id = NO_MENU_ID;
    if (!strip) return;
    /* collect first: a Click sub may change the menus */
    uint32 ids[16];
    int n = 0;
    while ((id = IIntuition->IDoMethod(strip, MM_NEXTSELECT, 0, id)) != NO_MENU_ID && n < 16) ids[n++] = id;
    for (int i = 0; i < n && f->loaded && !ending; i++) {
        bb_ctl *c = bbf_ctl_by_gid(f, ids[i]);
        if (c && c->kind == AFG_MENU && !c->dead) fire0(c, "Click");
    }
}

void bbf_menus_pick(bb_form *f)
{
    uint32 type = IMT_DEFAULT, addr = 0, ctx = 0;
    IIntuition->GetAttr(WINDOW_MenuType, f->winobj, &type);
    IIntuition->GetAttr(WINDOW_MenuAddress, f->winobj, &addr);
    if (type != IMT_DEFAULT) {
        IIntuition->GetAttr(WINDOW_MenuContext, f->winobj, &ctx);
        bb_ctl *c = (bb_ctl *)ctx;
        f->ctx_control = NULL;
        if (c == &f->self) f->ctx_control = "Form";
        else
            for (int i = 0; i < f->nctls; i++)
                if (f->ctls[i] == c) f->ctx_control = c->name;
    }
    if (addr) {
        pick_strip(f, (Object *)addr);
        return;
    }
    /* window.class without WINDOW_MenuAddress: ask every strip (the others return nothing) */
    pick_strip(f, f->menustrip);
    for (int i = 0; i < f->nctls; i++)
        if (f->ctls[i]->kind == AFG_MENU && f->ctls[i]->strip) pick_strip(f, f->ctls[i]->strip);
}

/* --- properties ------------------------------------------------------------------------- */

#define IS(a) (!strcasecmp(prop, a))

static uint32 mget(bb_ctl *c, Tag t)
{
    uint32 v = 0;
    if (c->obj) IIntuition->GetAttr(t, c->obj, &v);
    return v;
}

static void mset(bb_ctl *c, Tag t, uint32 v)
{
    if (c->obj) IIntuition->SetAttrs(c->obj, t, v, TAG_DONE);
}

int bbf_menu_get(bb_ctl *c, const char *prop, bb_fval *out)
{
    if (IS("Caption") || IS("Text")) return ret_str(c, out, c->text);
    if (IS("Checked")) return ret_int(out, vb_bool(mget(c, MA_Selected)));
    if (IS("Enabled")) return ret_int(out, vb_bool(!mget(c, MA_Disabled)));
    if (IS("Visible")) return ret_int(out, vb_bool(!mget(c, MA_Hidden)));
    if (IS("Shortcut")) return ret_str(c, out, c->extra);
    if (IS("Checkable")) return ret_int(out, vb_bool(mget(c, MA_Toggle) || mget(c, MA_MX)));
    return 438;
}

int bbf_menu_set(bb_ctl *c, const char *prop, const bb_fval *v)
{
    char buf[16];
    if (IS("Caption") || IS("Text")) {
        char *old = c->text;
        c->text = bbf_strip_underscore(vstr(v, buf));
        mset(c, MA_Label, (uint32)c->text);
        free(old);
        return 0;
    }
    if (IS("Checked")) {
        if (!mget(c, MA_Toggle) && !mget(c, MA_MX)) mset(c, MA_Toggle, TRUE);
        mset(c, MA_Selected, vint(v) != 0);
        return 0;
    }
    if (IS("Checkable")) { mset(c, MA_Toggle, vint(v) != 0); return 0; }
    if (IS("Enabled")) {
        mset(c, MA_Disabled, vint(v) == 0);
        bbf_tools_follow_menu(c->form, c->name, vint(v) != 0);    /* tools with menu=<this> */
        return 0;
    }
    if (IS("Visible")) {
        c->visible = vint(v) != 0;
        mset(c, MA_Hidden, !c->visible);
        return 0;
    }
    if (IS("Shortcut")) {
        char *old = c->extra;
        c->extra = xstrdup(vstr(v, buf));
        mset(c, MA_Key, *c->extra ? (uint32)c->extra : 0);
        free(old);
        return 0;
    }
    return 438;
}

#undef IS
#define IS(a) (!strcasecmp(method, a))

/* a node for a menu added at run time, inserted in the form's .afg tree (freed with it) */
static afg_node *new_node(afg_node *parent, const char *id, const char *text, const char *key)
{
    afg_node *n = calloc(1, sizeof *n);
    n->kind = AFG_MENU;
    n->line = 0;
    const char *kv[3][2] = { { "id", id }, { "text", text }, { "key", key } };
    n->props = calloc(3, sizeof *n->props);
    for (int i = 0; i < 3; i++) {
        if (!kv[i][1] || !*kv[i][1]) continue;
        n->props[n->nprops].key = xstrdup(kv[i][0]);
        n->props[n->nprops].value = xstrdup(kv[i][1]);
        n->nprops++;
    }
    parent->children = realloc(parent->children, (parent->nchildren + 1) * sizeof *parent->children);
    parent->children[parent->nchildren++] = n;
    n->parent = parent;
    return n;
}

static int menu_level(afg_node *n)
{
    int l = -1;
    for (; n && n->kind == AFG_MENU; n = n->parent) l++;
    return l;
}

/* Me.AddMenu id, caption [, parent [, key]] */
static int add_menu(bb_form *f, int argc, const bb_fval *argv)
{
    char b1[16], b2[16], b3[16], b4[16];
    if (argc < 2) return 450;
    const char *id = vstr(&argv[0], b1), *text = vstr(&argv[1], b2);
    const char *parent = argc > 2 && argv[2].type != BB_FV_NONE ? vstr(&argv[2], b3) : "";
    const char *key = argc > 3 && argv[3].type != BB_FV_NONE ? vstr(&argv[3], b4) : "";
    if (!*id || bb_form_ctl(f, id)) return 5;
    bb_ctl *pc = *parent ? find_menu(f, parent) : NULL;
    if (*parent && !pc) return 5;
    afg_node *n = new_node(pc ? pc->node : f->afg, id, text, key);
    bb_ctl *c = calloc(1, sizeof *c);
    c->form = f;
    c->node = n;
    c->kind = AFG_MENU;
    c->name = afg_get(n, "id");
    c->gid = f->nctls + 1;
    c->visible = 1;
    c->sel = -1;
    IExec->NewList(&c->labels);
    f->ctls = realloc(f->ctls, (f->nctls + 1) * sizeof *f->ctls);
    f->ctls[f->nctls++] = c;
    Object *o = build_menu(f, n, menu_level(n));
    if (!o) return 7;
    if (pc) {
        if (pc->obj) add_child(pc->obj, o);
    } else {
        if (!f->menustrip) {
            /* the first menu of a form without a menu bar: the window gets one */
            f->menustrip = new_strip();
            if (f->menustrip) {
                IIntuition->SetAttrs(f->winobj, WINDOW_MenuStrip, (uint32)f->menustrip, TAG_DONE);
            }
        }
        if (f->menustrip) add_child(f->menustrip, o);
    }
    return 0;
}

static void mark_dead(bb_form *f, afg_node *n)
{
    bb_ctl *c = menu_ctl(f, n);
    if (c) {
        c->dead = 1;
        c->obj = NULL;
        c->name = "";
    }
    for (int i = 0; i < n->nchildren; i++) mark_dead(f, n->children[i]);
}

static int remove_menu(bb_form *f, const char *name)
{
    bb_ctl *c = find_menu(f, name);
    if (!c) return 5;
    if (c->strip) {
        IIntuition->DisposeObject(c->strip);
        c->strip = NULL;
    } else if (c->obj) {
        Object *parent = (Object *)mget(c, MA_Parent);
        if (parent) IIntuition->SetAttrs(parent, MA_RemoveChild, (uint32)c->obj, TAG_DONE);
        IIntuition->DisposeObject(c->obj);
    }
    mark_dead(f, c->node);
    return 0;
}

/* --- pop-up menus (popupmenu.class) ----------------------------------------------------- */

static Object *build_popup(bb_form *f, afg_node *n)
{
    tags t = { 0 };
    for (int i = 0; i < n->nchildren; i++) {
        afg_node *k = n->children[i];
        bb_ctl *c = menu_ctl(f, k);
        if (!c || c->dead || !c->visible) continue;
        tags it = { 0 };
        if (is_sep(k))
            tg(&it, PMIA_Title, ~0u);
        else {
            tg(&it, PMIA_Title, (uint32)(c->text ? c->text : ""));
            tg(&it, PMIA_ID, c->gid);
            if (c->obj && (mget(c, MA_Toggle) || mget(c, MA_MX))) {
                tg(&it, PMIA_CheckIt, TRUE);
                tg(&it, PMIA_Checked, mget(c, MA_Selected) ? TRUE : FALSE);
            }
            if (c->obj && mget(c, MA_Disabled)) tg(&it, PMIA_Disabled, TRUE);
            if (k->nchildren) {
                Object *sub = build_popup(f, k);
                if (sub) tg(&it, PMIA_SubMenu, (uint32)sub);
            }
        }
        Object *io = new_obj(C_POPUPMENUITEM, &it);
        if (io) tg(&t, PMA_AddItem, (uint32)io);
    }
    return new_obj(C_POPUPMENU, &t);
}

static int popup_menu(bb_form *f, int argc, const bb_fval *argv)
{
    char b[16];
    if (argc < 1) return 450;
    bb_ctl *m = find_menu(f, vstr(&argv[0], b));
    if (!m) return 5;
    if (!f->win) return 0;
    Object *pm = build_popup(f, m->node);
    if (!pm) return 0;
    if (argc >= 3 && argv[1].type != BB_FV_NONE && argv[2].type != BB_FV_NONE)
        IIntuition->SetAttrs(pm, PMA_Left, f->win->LeftEdge + vint(&argv[1]), PMA_Top, f->win->TopEdge + vint(&argv[2]),
                             TAG_DONE);
    uint32 id = IIntuition->IDoMethod(pm, PM_OPEN, f->win);
    IIntuition->DisposeObject(pm);
    bb_ctl *c = id ? bbf_ctl_by_gid(f, id) : NULL;
    if (c && c->kind == AFG_MENU && !c->dead) {
        if (c->obj && mget(c, MA_Toggle)) mset(c, MA_Selected, !mget(c, MA_Selected));
        else if (c->obj && mget(c, MA_MX)) {
            /* switch the other radio items of the panel off */
            afg_node *p = c->node->parent;
            for (int i = 0; i < p->nchildren; i++) {
                bb_ctl *o = menu_ctl(f, p->children[i]);
                if (o && o->obj && mget(o, MA_MX)) mset(o, MA_Selected, o == c);
            }
        }
        f->ctx_control = NULL;
        fire0(c, "Click");
    }
    return 0;
}

int bbf_form_menu_call(bb_form *f, const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    char b[16];
    if (IS("PopupMenu")) return popup_menu(f, argc, argv);
    if (IS("AddMenu")) return add_menu(f, argc, argv);
    if (IS("RemoveMenu")) {
        if (argc < 1) return 450;
        return remove_menu(f, vstr(&argv[0], b));
    }
    return 438;
}
