/* forms_rt.c - forms and controls as BASIC objects, on the platform forms layer (bb_forms.h)
 *
 * Every form of a project is registered at start-up (bb_forms_register) with its .afg text.
 * The form's window name is a module variable holding a form object. It loads the form on
 * first use, as VB does, so `other.Show` works from any module. Loading creates a bb_ctl for
 * every designer object; the code-behind's variable for each control id gets a control object.
 * Events from the forms layer call `<control>_<Event>` in the code-behind
 * (bb_dispatch_event).
 *
 * Control members are not known statically: find() interns the name and invoke() hands it
 * to bb_ctl_get / bb_ctl_set / bb_ctl_call, converting between Variants and bb_fval.
 */
#include "boing.h"
#include "bb_forms.h"
#include "afg.h"
#include "canvas.h"     /* canvas */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

typedef struct formdef {
    char *module, *name, *afg, *path;
    bb_form *form;
    int loading;
} formdef;

static formdef *forms;
static int nforms;
static int forms_used;

typedef struct ctlobj {
    bb_obj hdr;
    formdef *fd;            /* the form this control (or form object) belongs to */
    bb_ctl *ctl;            /* NULL for a form object whose form is not loaded yet */
    int is_form;
    char *name;
} ctlobj;

/* ---------- member names ---------- */

static char **names;
static int32_t nnames, capnames;

static int32_t intern(const char *s)
{
    int32_t i;
    for (i = 0; i < nnames; i++) if (strcasecmp(names[i], s) == 0) return i;
    if (nnames == capnames) {
        capnames = capnames ? capnames * 2 : 64;
        names = (char **)bb_realloc(names, sizeof(char *) * (size_t)capnames);
    }
    names[nnames] = strdup(s);
    return nnames++;
}

static void fv_from_value(const bb_value *v0, bb_fval *fv, bb_str **hold)
{
    bb_value t;
    const bb_value *v = bb_v_deref(v0, &t);
    *hold = NULL;
    fv->s = NULL;
    fv->i = 0;
    switch (v->type) {
    case BB_EMPTY: fv->type = BB_FV_INT; break;
    case BB_STRING: fv->type = BB_FV_STR; fv->s = bb_str_ptr(v->u.s); break;
    case BB_BOOLEAN: case BB_INTEGER: case BB_LONG: case BB_BYTE:
        fv->type = BB_FV_INT;
        fv->i = bb_v_to_long(v);
        break;
    case BB_SINGLE: case BB_DOUBLE: case BB_CURRENCY: case BB_DATE:
        fv->type = BB_FV_INT;
        fv->i = bb_v_to_long(v);
        break;
    case BB_NULL: bb_raise(94, NULL);
    default:
        *hold = bb_v_to_str(v);
        fv->type = BB_FV_STR;
        fv->s = bb_str_ptr(*hold);
    }
}

static bb_value value_from_fv(const bb_fval *fv)
{
    switch (fv->type) {
    case BB_FV_INT: return bb_v_long(fv->i);
    case BB_FV_STR: return bb_v_str(bb_str_from_c(fv->s ? fv->s : ""));
    default: return bb_v_empty();
    }
}

static formdef *find_form(const char *module)
{
    int i;
    for (i = 0; i < nforms; i++)
        if (strcasecmp(forms[i].module, module) == 0 || strcasecmp(forms[i].name, module) == 0) return &forms[i];
    return NULL;
}

static int load_form(formdef *fd);

static bb_ctl *ctl_of(ctlobj *o)
{
    if (o->is_form) {
        if (!o->fd->form && load_form(o->fd) != 0) bb_raise(bb_err.number ? bb_err.number : 5, NULL);
        o->ctl = bb_form_self(o->fd->form);
    }
    if (!o->ctl) bb_raise(364, "Object was unloaded");
    return o->ctl;
}

static int32_t ctl_find(const bb_class *cls, const char *name)
{
    (void)cls;
    return intern(name && *name ? name : "");
}

static void ctl_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    ctlobj *o = (ctlobj *)self;
    const char *name = names[id];
    bb_fval fv, out;
    bb_str *hold = NULL;
    int err;
    bb_ctl *c;
    /* form-level operations that also work on an unloaded form */
    if (o->is_form && (kind & BB_INV_METHOD) && !strcasecmp(name, "Show")) {
        c = ctl_of(o);
        err = bb_form_show(o->fd->form);
        if (err) bb_raise(err, NULL);
        return;
    }
    if (o->is_form && (kind & BB_INV_METHOD) && !strcasecmp(name, "Hide")) {
        if (!o->fd->form) return;
        err = bb_form_hide(o->fd->form);
        if (err) bb_raise(err, NULL);
        return;
    }
    c = ctl_of(o);
    /* form.control: a control of the form by name (main.ok.Caption) */
    if (o->is_form && *name && (kind & BB_INV_GET) && argc == 0 && bb_form_ctl(o->fd->form, name)) {
        int type = 0;
        void *slot = bb_find_global(o->fd->module, name, &type);
        bb_obj *ctl = NULL;
        if (slot && type == BB_OBJECT) ctl = *(bb_obj **)slot;
        else if (slot && type == BB_VARIANT && ((bb_value *)slot)->type == BB_OBJECT) ctl = ((bb_value *)slot)->u.o;
        if (ctl) {
            *ret = bb_v_obj(bb_obj_retain(ctl));
            return;
        }
    }
    if (!*name) {
        /* default property: VB's Text / Caption / Value */
        static const char *const defs[] = {"Text", "Caption", "Value", NULL};
        int i;
        for (i = 0; defs[i]; i++) {
            if (kind & (BB_INV_LET | BB_INV_SET)) {
                fv_from_value(&argv[argc - 1], &fv, &hold);
                err = bb_ctl_set(c, defs[i], argc > 1 ? bb_v_to_long(&argv[0]) : -1, &fv);
                bb_str_release(hold);
            } else {
                memset(&out, 0, sizeof out);
                err = bb_ctl_get(c, defs[i], argc > 0 ? bb_v_to_long(&argv[0]) : -1, &out);
                if (!err) *ret = value_from_fv(&out);
            }
            if (err != 438) break;
        }
        if (err) bb_raise(err, NULL);
        return;
    }
    if (kind & (BB_INV_LET | BB_INV_SET)) {
        if (argc < 1 || argc > 2) bb_raise(450, NULL);
        fv_from_value(&argv[argc - 1], &fv, &hold);
        err = bb_ctl_set(c, name, argc == 2 ? bb_v_to_long(&argv[0]) : -1, &fv);
        bb_str_release(hold);
        if (err) bb_raise(err, NULL);
        return;
    }
    err = 438;
    if ((kind & BB_INV_GET) && argc <= 1) {
        memset(&out, 0, sizeof out);
        err = bb_ctl_get(c, name, argc == 1 ? bb_v_to_long(&argv[0]) : -1, &out);
        if (!err) { *ret = value_from_fv(&out); return; }
        if (err != 438 || !(kind & BB_INV_METHOD)) bb_raise(err, NULL);
    }
    if (kind & BB_INV_METHOD) {
        bb_fval args[8];
        bb_str *holds[8];
        int i;
        if (argc > 8) bb_raise(450, NULL);
        for (i = 0; i < argc; i++) {
            if (argv[i].type == BB_ERROR && (argv[i].flags & BB_VF_MISSING)) { args[i].type = BB_FV_NONE; args[i].s = NULL; args[i].i = 0; holds[i] = NULL; }
            else fv_from_value(&argv[i], &args[i], &holds[i]);
        }
        memset(&out, 0, sizeof out);
        err = bb_ctl_call(c, name, argc, args, &out);
        for (i = 0; i < argc; i++) bb_str_release(holds[i]);
        if (err) bb_raise(err, NULL);
        *ret = value_from_fv(&out);
        return;
    }
    bb_raise(err, NULL);
}

static void ctl_terminate(bb_obj *self)
{
    ctlobj *o = (ctlobj *)self;
    free(o->name);
}

static const bb_class ctl_class = {"Control", sizeof(ctlobj), ctl_find, ctl_invoke, ctl_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL};
static const bb_class form_class = {"Form", sizeof(ctlobj), ctl_find, ctl_invoke, ctl_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL};

/* TypeName(ctl): VB's names for the control kinds */
static const char *const vb_type[AFG_NUM_KINDS] = {
    [AFG_BUTTON] = "CommandButton", [AFG_STRING] = "TextBox", [AFG_INTEGER] = "IntegerBox",
    [AFG_CHECKBOX] = "CheckBox", [AFG_CHOOSER] = "ComboBox", [AFG_RADIO] = "OptionGroup", [AFG_SLIDER] = "Slider",
    [AFG_SCROLLER] = "ScrollBar", [AFG_LISTBROWSER] = "ListBox", [AFG_LABEL] = "Label", [AFG_SPACE] = "Space",
    [AFG_FUELGAUGE] = "ProgressBar", [AFG_GETFILE] = "FileChooser", [AFG_TEXTEDITOR] = "TextEditor",
    [AFG_TIMER] = "Timer",
};
static bb_class kind_classes[AFG_NUM_KINDS];

static const bb_class *class_for(int kind)
{
    if (kind < 0 || kind >= AFG_NUM_KINDS || !vb_type[kind]) return &ctl_class;
    if (!kind_classes[kind].name) {
        kind_classes[kind] = ctl_class;
        kind_classes[kind].name = vb_type[kind];
    }
    return &kind_classes[kind];
}

static bb_obj *new_ctlobj_kind(formdef *fd, bb_ctl *c, int is_form, const char *name, int kind)
{
    ctlobj *o = (ctlobj *)bb_obj_new(is_form ? &form_class : class_for(kind));
    o->fd = fd;
    o->ctl = c;
    o->is_form = is_form;
    o->name = strdup(name);
    return &o->hdr;
}

static bb_obj *new_ctlobj(formdef *fd, bb_ctl *c, int is_form, const char *name)
{
    ctlobj *o = (ctlobj *)bb_obj_new(is_form ? &form_class : &ctl_class);
    o->fd = fd;
    o->ctl = c;
    o->is_form = is_form;
    o->name = strdup(name);
    return &o->hdr;
}

static void set_global_obj(const char *module, const char *name, bb_obj *owned)
{
    int type = 0;
    void *slot = bb_find_global(module, name, &type);
    if (!slot) { bb_obj_release(owned); return; }
    if (type == BB_OBJECT) bb_obj_set((bb_obj **)slot, owned);
    else if (type == BB_VARIANT) bb_v_set((bb_value *)slot, bb_v_obj(owned));
    else bb_obj_release(owned);
}

/* ---------- events ---------- */

typedef struct fillctx { formdef *fd; } fillctx;

static void fill_one(afg_node *n, void *ud)
{
    fillctx *fc = (fillctx *)ud;
    const char *id;
    bb_ctl *c;
    if (n->kind == AFG_WINDOW) return;
    id = afg_get(n, "id");
    if (!id || !*id) return;
    c = bb_form_ctl(fc->fd->form, id);
    if (c && n->kind == AFG_CANVAS)       /* canvas: its own object class (canvas.c) */
        set_global_obj(fc->fd->module, id, bb_canvas_new(afg_get_int(n, "width"), afg_get_int(n, "height"), c));
    else if (c) set_global_obj(fc->fd->module, id, new_ctlobj_kind(fc->fd, c, 0, id, n->kind));
}

/* the code-behind's control variables */
static void fill_controls(formdef *fd)
{
    char err[256];
    afg_node *root = afg_parse(fd->afg, err, sizeof err);
    fillctx fc;
    if (!root) return;
    fc.fd = fd;
    afg_walk(root, fill_one, &fc);
    afg_free(root);
}

static int ev_has(void *ud, bb_form *f, const char *ctl, const char *event)
{
    formdef *fd = (formdef *)ud;
    char name[256];
    (void)f;
    snprintf(name, sizeof name, "%s_%s", ctl, event);
    return bb_find_proc(fd->module, name) != NULL;
}

static int ev_fire(void *ud, bb_form *f, const char *ctl, const char *event, int argc, int32_t *args)
{
    formdef *fd = (formdef *)ud;
    bb_value argv[8];
    char name[256];
    void *proc;
    int i;
    int32_t err;
    if (!fd->form) {
        /* first event (Form_Load) arrives during bb_form_load */
        fd->form = f;
        fill_controls(fd);
    }
    snprintf(name, sizeof name, "%s_%s", ctl, event);
    proc = bb_find_proc(fd->module, name);
    if (!proc) return 0;
    if (argc > 8) argc = 8;
    for (i = 0; i < argc; i++) argv[i] = bb_v_ref(BB_LONG, &args[i]);
    err = bb_call_proc(proc, argc, argv, NULL);
    if (err) {
        bb_fatal_error();
        return 1;
    }
    return 0;
}

static int load_form(formdef *fd)
{
    char err[512];
    bb_form *f;
    if (fd->form) return 0;
    if (fd->loading) return 0;
    fd->loading = 1;
    forms_used = 1;
    err[0] = 0;
    f = bb_form_load(fd->afg, fd->path, ev_fire, ev_has, fd, err, sizeof err);
    fd->loading = 0;
    if (!f) {
        bb_console_flush();
        fprintf(stderr, "%s\n", err[0] ? err : "cannot load form");
        bb_err.number = 5;
        return 5;
    }
    if (!fd->form) {
        fd->form = f;
        fill_controls(fd);
    }
    return 0;
}

/* ---------- API for programs ---------- */

void bb_forms_register(const char *module, const char *form_name, const char *afg_text, const char *afg_path)
{
    formdef *fd;
    forms = (formdef *)bb_realloc(forms, sizeof(formdef) * (size_t)(nforms + 1));
    fd = &forms[nforms++];
    memset(fd, 0, sizeof *fd);
    fd->module = strdup(module);
    fd->name = strdup(form_name && *form_name ? form_name : module);
    fd->afg = strdup(afg_text ? afg_text : "");
    fd->path = strdup(afg_path ? afg_path : module);
    /* the form's own variable holds a (not yet loaded) form object */
    set_global_obj(fd->module, fd->name, new_ctlobj(fd, NULL, 1, fd->name));
}

int bb_forms_register_file(const char *module, const char *form_name, const char *afg_path)
{
    FILE *f = fopen(afg_path, "rb");
    long n;
    char *text;
    if (!f) {
        fprintf(stderr, "%s: cannot read form file\n", afg_path);
        return 53;
    }
    fseek(f, 0, SEEK_END);
    n = ftell(f);
    fseek(f, 0, SEEK_SET);
    text = (char *)malloc((size_t)n + 1);
    if (fread(text, 1, (size_t)n, f) != (size_t)n) n = 0;
    text[n] = 0;
    fclose(f);
    bb_forms_register(module, form_name, text, afg_path);
    free(text);
    return 0;
}

static bb_int forms_doevents(void) { bb_forms_doevents(); return 0; }

/* Startup=Form x: load, show, run the event loop until the last form is unloaded */
void bb_forms_main(const char *module)
{
    formdef *fd = find_form(module);
    int err;
    if (!fd) bb_raise(5, "startup form not registered");
    bb_set_doevents(forms_doevents);
    err = load_form(fd);
    if (err) bb_exit(20);
    err = bb_form_show(fd->form);
    if (err) bb_raise(err, NULL);
    bb_forms_run();
    bb_forms_cleanup();
}

/* Load x / Unload x / x.Show from code (objects created by this module) */
void bb_form_load_obj(const bb_value *v)
{
    bb_value t;
    const bb_value *x = bb_v_deref(v, &t);
    ctlobj *o;
    if (x->type != BB_OBJECT || !x->u.o || x->u.o->cls != &form_class) bb_raise(424, NULL);
    o = (ctlobj *)x->u.o;
    if (load_form(o->fd)) bb_raise(5, NULL);
}

void bb_form_unload_obj(const bb_value *v)
{
    bb_value t;
    const bb_value *x = bb_v_deref(v, &t);
    ctlobj *o;
    if (x->type != BB_OBJECT || !x->u.o || x->u.o->cls != &form_class) bb_raise(424, NULL);
    o = (ctlobj *)x->u.o;
    if (!o->fd->form) return;
    if (bb_form_unload(o->fd->form) == 0) {
        o->fd->form = NULL;
        o->ctl = NULL;
    }
}

void bb_forms_shutdown_(void)
{
    if (forms_used) bb_forms_cleanup();
}
