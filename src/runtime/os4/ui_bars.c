/* Toolbars (speedbar.gadget), status bars, images and the dispatch of the docs/ui.md kinds
 * (docs/ui.md sections 2 and 4). forms.c calls bbf_ext_* for every kind it doesn't know. */
#include "forms_int.h"
#include <proto/speedbar.h>
#include <gadgets/speedbar.h>
#include <images/bitmap.h>

static struct SpeedBarIFace *ISB;

static struct SpeedBarIFace *sb_iface(void)
{
    if (!ISB && cls(C_SPEEDBAR) && bbf_class_lib(C_SPEEDBAR))
        ISB = (void *)IExec->GetInterface(bbf_class_lib(C_SPEEDBAR), "main", 1, NULL);
    return ISB;
}

/* program end, before the classes are closed */
void bbf_ext_cleanup(void)
{
    if (ISB) IExec->DropInterface((struct Interface *)ISB);
    ISB = NULL;
    bbf_dialog_cleanup();
}

/* a picture file (any datatype) as a bitmap.image remapped to the Workbench screen */
Object *bbf_load_image(const char *file, const char *selfile)
{
    if (!file || !*file) return NULL;
    /* a missing file (e.g. TBImages: names a system doesn't have) is no picture, not a crash */
    BPTR l = IDOS->Lock(file, SHARED_LOCK);
    if (!l) return NULL;
    IDOS->UnLock(l);
    if (selfile && *selfile) {
        BPTR sl = IDOS->Lock(selfile, SHARED_LOCK);
        if (sl) IDOS->UnLock(sl);
        else selfile = NULL;
    }
    struct Screen *scr = IIntuition->LockPubScreen(NULL);
    tags t = { 0 };
    tg(&t, BITMAP_SourceFile, (uint32)file);
    if (selfile && *selfile) tg(&t, BITMAP_SelectSourceFile, (uint32)selfile);
    tg(&t, BITMAP_Screen, (uint32)scr);
    tg(&t, BITMAP_Masking, TRUE);
    tg(&t, BITMAP_Precision, PRECISION_IMAGE);
    Object *o = new_obj(C_BITMAP, &t);
    if (scr) IIntuition->UnlockPubScreen(NULL, scr);
    if (o) {      /* a file datatypes couldn't read gives an empty image: none then */
        uint32 w = 0, h = 0;
        IIntuition->GetAttr(BITMAP_Width, o, &w);
        IIntuition->GetAttr(BITMAP_Height, o, &h);
        if (!w || !h) {
            IIntuition->DisposeObject(o);
            o = NULL;
        }
    }
    return o;
}

/* --- toolbar ------------------------------------------------------------------------------ */

static bb_ctl *ctl_of_node(bb_form *f, afg_node *n)
{
    for (int i = 0; i < f->nctls; i++)
        if (f->ctls[i]->node == n) return f->ctls[i];
    return NULL;
}

static Object *build_toolbar(bb_form *f, afg_node *n, bb_ctl *c, tags *t)
{
    struct SpeedBarIFace *sb = sb_iface();
    if (!sb) return NULL;
    int any_image = 0, all_images = 1;
    for (int i = 0; i < n->nchildren; i++) {
        afg_node *k = n->children[i];
        bb_ctl *tc = ctl_of_node(f, k);
        if (!tc) continue;
        tc->bar = c;
        tc->enabled = !afg_get_bool(k, "disabled");
        if (afg_get_bool(k, "separator")) {
            tc->sbnode = sb->AllocSpeedButtonNode(tc->gid, SBNA_Separator, TRUE, TAG_DONE);
        } else {
            tc->img = bbf_load_image(afg_get(k, "image"), afg_get(k, "selimage"));
            if (tc->img) any_image = 1;
            else all_images = 0;
            tc->text = bbf_strip_underscore(afg_get(k, "text"));
            if (afg_has(k, "hint")) tc->hint = xstrdup(afg_get(k, "hint"));
            tc->sbnode = sb->AllocSpeedButtonNode(tc->gid,
                                                  tc->img ? SBNA_Image : TAG_IGNORE, (uint32)tc->img,
                                                  SBNA_Text, (uint32)tc->text,
                                                  tc->hint ? SBNA_HintInfo : TAG_IGNORE, (uint32)tc->hint,
                                                  SBNA_Toggle, afg_get_bool(k, "toggle"),
                                                  SBNA_Selected, afg_get_bool(k, "checked"),
                                                  SBNA_Disabled, afg_get_bool(k, "disabled"),
                                                  SBNA_Enabled, TRUE,
                                                  SBNA_Spacing, 2,
                                                  SBNA_Highlight, SBH_RECESS,
                                                  TAG_DONE);
        }
        if (tc->sbnode) IExec->AddTail(&c->labels, tc->sbnode);
    }
    bbf_gadget_tags(c, t);
    tg(t, SPEEDBAR_Buttons, (uint32)&c->labels);
    tg(t, SPEEDBAR_Orientation, afg_get_bool(n, "vertical") ? SBORIENT_VERT : SBORIENT_HORIZ);
    /* pictures only when every tool has one: a missing picture makes the bar text-only */
    int type = any_image && all_images ? SBTYPE_BOTH : SBTYPE_TEXT;
    if (afg_get_bool(n, "textonly")) type = SBTYPE_TEXT;
    if (afg_get_bool(n, "imagesonly") && any_image && all_images) type = SBTYPE_IMAGE;
    tg(t, SPEEDBAR_ButtonType, type);
    tg(t, SPEEDBAR_EvenSize, TRUE);
    tg(t, SPEEDBAR_BevelStyle, BVS_NONE);
    return new_obj(C_SPEEDBAR, t);
}

static void tool_set(bb_ctl *tc, Tag tag, uint32 v)
{
    if (!tc->sbnode || !tc->bar || !tc->bar->obj) return;
    struct TagItem t[2] = { { tag, v }, { TAG_DONE, 0 } };
    bb_form *f = tc->form;
    if (f->win)
        IIntuition->DoGadgetMethodA((struct Gadget *)tc->bar->obj, f->win, NULL,
                                   (Msg) & (struct sbSetNodeAttrs){ SBM_SETNODEATTRS, NULL, tc->sbnode, t });
    else if (sb_iface())
        ISB->SetSpeedButtonNodeAttrsA(tc->sbnode, t);
}

static uint32 tool_get(bb_ctl *tc, Tag tag)
{
    uint32 v = 0;
    if (tc->sbnode && sb_iface()) {
        struct TagItem t[2] = { { tag, (uint32)&v }, { TAG_DONE, 0 } };
        ISB->GetSpeedButtonNodeAttrsA(tc->sbnode, t);
    }
    return v;
}

void bbf_tools_follow_menu(bb_form *f, const char *menu, int enabled)
{
    for (int i = 0; i < f->nctls; i++) {
        bb_ctl *tc = f->ctls[i];
        if (tc->kind == AFG_TOOL && !strcasecmp(afg_get(tc->node, "menu"), menu)) {
            tc->enabled = enabled;
            tool_set(tc, SBNA_Disabled, !enabled);
        }
    }
}

#define IS(a) (!strcasecmp(prop, a))

static int tool_get_prop(bb_ctl *c, const char *prop, bb_fval *out)
{
    if (IS("Caption") || IS("Text")) return ret_str(c, out, c->text);
    if (IS("Enabled")) return ret_int(out, vb_bool(c->enabled));
    if (IS("Value")) return ret_int(out, tool_get(c, SBNA_Selected) ? 1 : 0);
    if (IS("ToolTipText")) return ret_str(c, out, c->hint);
    if (IS("Picture")) return ret_str(c, out, c->extra ? c->extra : afg_get(c->node, "image"));
    if (IS("Visible")) return ret_int(out, vb_bool(c->visible));
    return 438;
}

static int tool_set_prop(bb_ctl *c, const char *prop, const bb_fval *v)
{
    char buf[16];
    if (IS("Enabled")) {
        c->enabled = vint(v) != 0;
        tool_set(c, SBNA_Disabled, !c->enabled);
        return 0;
    }
    if (IS("Value")) { tool_set(c, SBNA_Selected, vint(v) != 0); return 0; }
    if (IS("Caption") || IS("Text")) {
        char *old = c->text;
        c->text = bbf_strip_underscore(vstr(v, buf));
        tool_set(c, SBNA_Text, (uint32)c->text);
        free(old);
        return 0;
    }
    if (IS("ToolTipText")) {
        char *old = c->hint;
        c->hint = xstrdup(vstr(v, buf));
        tool_set(c, SBNA_HintInfo, (uint32)c->hint);
        free(old);
        return 0;
    }
    if (IS("Picture")) {
        Object *img = bbf_load_image(vstr(v, buf), NULL);
        if (!img) return 53;
        free(c->extra);
        c->extra = xstrdup(vstr(v, buf));
        tool_set(c, SBNA_Image, (uint32)img);
        if (c->img) IIntuition->DisposeObject(c->img);
        c->img = img;
        return 0;
    }
    if (IS("Visible")) {
        c->visible = vint(v) != 0;     /* speedbar buttons can't hide: kept for reading back */
        return 0;
    }
    return 438;
}

/* --- statusbar ---------------------------------------------------------------------------- */

static Object *build_statusbar(bb_form *f, afg_node *n, bb_ctl *c, tags *t)
{
    char **texts, **widths;
    int np = afg_split_items(afg_get(n, "panels"), &texts);
    int nw = afg_split_items(afg_get(n, "widths"), &widths);
    if (np < 1) {
        afg_free_items(texts, np);
        np = afg_split_items(" ", &texts);
    }
    c->panels = calloc(np, sizeof *c->panels);
    c->npanels = np;
    for (int i = 0; i < np; i++) bbf_items_insert(c, -1, texts[i]);
    tg(t, LAYOUT_Orientation, LAYOUT_ORIENT_HORIZ);
    tg(t, LAYOUT_SpaceInner, FALSE);
    for (int i = 0; i < np; i++) {
        tags bt = { 0 };
        tg(&bt, GA_ReadOnly, TRUE);
        tg(&bt, GA_Text, (uint32)c->items[i]);
        tg(&bt, BUTTON_BevelStyle, BVS_FIELD);
        tg(&bt, BUTTON_Justification, BCJ_LEFT);
        c->panels[i] = new_obj(C_BUTTON, &bt);
        if (!c->panels[i]) continue;
        tg(t, LAYOUT_AddChild, (uint32)c->panels[i]);
        int w = i < nw ? atoi(widths[i]) : 0;
        if (w > 0) {
            tg(t, CHILD_MinWidth, w);
            tg(t, CHILD_WeightedWidth, 0);
        }
    }
    afg_free_items(texts, np);
    afg_free_items(widths, nw);
    (void)f;
    return new_obj(C_LAYOUT, t);
}

static int panel_set(bb_ctl *c, int i, const char *s)
{
    if (i < 0 || i >= c->npanels) return 381;
    free(c->items[i]);
    c->items[i] = xstrdup(s);
    if (!c->panels[i]) return 0;
    struct TagItem t[2] = { { GA_Text, (uint32)c->items[i] }, { TAG_DONE, 0 } };
    if (c->form->win) IIntuition->SetGadgetAttrsA((struct Gadget *)c->panels[i], c->form->win, NULL, t);
    else IIntuition->SetAttrsA(c->panels[i], t);
    return 0;
}

/* --- image -------------------------------------------------------------------------------- */

static Object *build_image(bb_form *f, afg_node *n, bb_ctl *c, tags *t)
{
    (void)f;
    c->img = bbf_load_image(afg_get(n, "file"), NULL);
    tg(t, GA_ID, c->gid);
    tg(t, GA_ReadOnly, TRUE);
    tg(t, BUTTON_BevelStyle, afg_get_bool(n, "frame") ? BVS_FIELD : BVS_NONE);
    tg(t, BUTTON_Transparent, TRUE);
    if (c->img) tg(t, BUTTON_RenderImage, (uint32)c->img);
    else tg(t, GA_Text, (uint32)"");
    return new_obj(C_BUTTON, t);
}

/* --- dispatch ----------------------------------------------------------------------------- */

Object *bbf_ext_build(bb_form *f, afg_node *n, bb_ctl *c, tags *t)
{
    switch (n->kind) {
    case AFG_TOOLBAR: return build_toolbar(f, n, c, t);
    case AFG_STATUSBAR: return build_statusbar(f, n, c, t);
    case AFG_IMAGE: return build_image(f, n, c, t);
    case AFG_COMMONDIALOG: return NULL;
    case AFG_TABS: return bbf_tabs_build(f, n, c, t);
    case AFG_TREEVIEW: return bbf_tree_build(f, n, c, t);
    case AFG_GRID: return bbf_grid_build(f, n, c, t);
    default: return NULL;
    }
}

int bbf_ext_get(bb_ctl *c, const char *prop, int index, bb_fval *out)
{
    switch (c->kind) {
    case AFG_TOOL: return tool_get_prop(c, prop, out);
    case AFG_STATUSBAR:
        if (IS("Text") || IS("SimpleText")) return ret_str(c, out, c->npanels ? c->items[0] : "");
        if (IS("PanelCount")) return ret_int(out, c->npanels);
        if (IS("Panel")) {
            if (index < 0 || index >= c->npanels) return 381;
            return ret_str(c, out, c->items[index]);
        }
        return 438;
    case AFG_IMAGE:
        if (IS("Picture")) return ret_str(c, out, c->extra ? c->extra : afg_get(c->node, "file"));
        return 438;
    case AFG_TOOLBAR:
        if (IS("ButtonCount")) {
            int k = 0;
            for (int i = 0; i < c->form->nctls; i++) k += c->form->ctls[i]->bar == c;
            return ret_int(out, k);
        }
        return 438;
    case AFG_CANVAS:
        if (IS("RightButton")) return ret_int(out, vb_bool(c->rmb));
        if (IS("Fill")) return ret_int(out, vb_bool(c->fill));
        if (IS("MouseX")) return ret_int(out, c->mx);
        if (IS("MouseY")) return ret_int(out, c->my);
        if (IS("MouseButtons")) return ret_int(out, c->form->capture == c ? c->form->buttons : 0);
        if (IS("MousePointer")) return ret_int(out, c->ptr);
        return 438;
    case AFG_COMMONDIALOG: return bbf_dialog_get(c, prop, index, out);
    case AFG_GRID: return bbf_grid_get(c, prop, index, out);
    default: return bbf_tt_get(c, prop, index, out);
    }
}

int bbf_ext_set(bb_ctl *c, const char *prop, int index, const bb_fval *v)
{
    char buf[16];
    switch (c->kind) {
    case AFG_TOOL: return tool_set_prop(c, prop, v);
    case AFG_STATUSBAR:
        if (IS("Text") || IS("SimpleText")) return panel_set(c, 0, vstr(v, buf));
        if (IS("Panel")) return panel_set(c, index, vstr(v, buf));
        if (IS("PanelCount")) return 383;
        return 438;
    case AFG_IMAGE:
        if (IS("Picture")) {
            Object *img = bbf_load_image(vstr(v, buf), NULL);
            if (!img) return 53;
            free(c->extra);
            c->extra = xstrdup(vstr(v, buf));
            set_attr(c, BUTTON_RenderImage, (uint32)img);
            if (c->img) IIntuition->DisposeObject(c->img);
            c->img = img;
            relayout(c->form);
            return 0;
        }
        return 438;
    case AFG_CANVAS:
        if (IS("RightButton")) {
            c->rmb = vint(v) != 0;
            if (c->rmb && !c->form->mouse_wanted) return 5;    /* the window doesn't report the mouse: use rmb=1 in the .afg */
            return 0;
        }
        if (IS("Fill")) { c->fill = vint(v) != 0; relayout(c->form); return 0; }
        if (IS("MousePointer")) {
            c->ptr = vint(v);
            bbf_update_pointer(c->form, c->form->mouse_wanted ? c->mx : -1, -1);   /* takes effect at the next move */
            return 0;
        }
        if (IS("MouseX") || IS("MouseY") || IS("MouseButtons")) return 383;
        return 438;
    case AFG_COMMONDIALOG: return bbf_dialog_set(c, prop, index, v);
    case AFG_GRID: return bbf_grid_set(c, prop, index, v);
    default: return bbf_tt_set(c, prop, index, v);
    }
}

#undef IS

int bbf_ext_call(bb_ctl *c, const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    if (c->kind == AFG_COMMONDIALOG) return bbf_dialog_call(c, method, argc, argv, ret);
    if (c->kind == AFG_GRID) return bbf_grid_call(c, method, argc, argv, ret);
    return bbf_tt_call(c, method, argc, argv, ret);
}

void bbf_ext_gadget_up(bb_form *f, bb_ctl *c, uint16 code)
{
    if (c->kind == AFG_TOOLBAR) {
        bb_ctl *tc = bbf_ctl_by_gid(f, code);
        if (!tc || tc->kind != AFG_TOOL) return;
        fire0(tc, "Click");
        const char *menu = afg_get(tc->node, "menu");
        if (*menu && !ending && f->loaded) fire(f, menu, "Click", 0, NULL);
        return;
    }
    if (c->kind == AFG_GRID) bbf_grid_gadget_up(f, c, code);
    else bbf_tt_gadget_up(f, c, code);
}

void bbf_ext_free(bb_ctl *c)
{
    if (c->kind == AFG_TOOLBAR) {
        struct Node *nd;
        while ((nd = IExec->RemHead(&c->labels)))
            if (ISB) ISB->FreeSpeedButtonNode(nd);
    }
    if (c->selimg) IIntuition->DisposeObject(c->selimg);     /* a label.image using img: first */
    if (c->img) IIntuition->DisposeObject(c->img);
    c->img = c->selimg = NULL;
    free(c->panels);
    c->panels = NULL;
    if (c->kind == AFG_COMMONDIALOG) bbf_dialog_free(c);
    if (c->kind == AFG_TREEVIEW) bbf_tree_free(c);
    if (c->kind == AFG_GRID) bbf_grid_free(c);
    if (c->kind == AFG_TABS) c->ext = NULL;       /* the page group went with the clicktab */
}
