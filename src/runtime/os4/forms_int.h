/* Internals of the OS4 forms runtime shared by forms.c and the ui_*.c files (menus, toolbars,
 * dialogs, grid, Workbench, ARexx: docs/ui.md). Not part of the runtime's API. */
#ifndef BB_OS4_FORMS_INT_H
#define BB_OS4_FORMS_INT_H

#include "../bb_forms.h"
#include "../afg.h"
#include "../canvas.h"     /* canvas */

#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

#include <exec/exec.h>
#include <devices/timer.h>
#include <intuition/intuition.h>
#include <intuition/gadgetclass.h>
#include <intuition/icclass.h>
#include <intuition/sghooks.h>
#include <devices/inputevent.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <proto/intuition.h>
#include <proto/keymap.h>
#include <proto/listbrowser.h>
#include <proto/chooser.h>
#include <proto/layout.h>
#include <proto/utility.h>
#include <classes/window.h>
#include <classes/requester.h>
#include <gadgets/layout.h>
#include <gadgets/button.h>
#include <gadgets/string.h>
#include <gadgets/integer.h>
#include <gadgets/checkbox.h>
#include <gadgets/chooser.h>
#include <gadgets/radiobutton.h>
#include <gadgets/slider.h>
#include <gadgets/scroller.h>
#include <gadgets/listbrowser.h>
#include <gadgets/space.h>
#include <gadgets/fuelgauge.h>
#include <gadgets/getfile.h>
#include <gadgets/texteditor.h>
#include <images/label.h>
#include <images/bevel.h>

#include <intuition/menuclass.h>
#include <classes/popupmenu.h>

/* --- tag lists -------------------------------------------------------------------------- */

typedef struct {
    struct TagItem *t;
    int n, cap;
} tags;

/* --- objects ---------------------------------------------------------------------------- */

struct bb_ctl {
    bb_form *form;
    afg_node *node;          /* NULL for the form itself */
    afg_kind kind;
    const char *name;
    Object *obj;
    uint32 gid;
    struct List labels;      /* listbrowser / chooser nodes */
    char **items;            /* chooser / radio / list texts */
    int nitems, capitems;
    STRPTR *labelarray;      /* radio */
    int32 sel;               /* ListIndex */
    int32 lastval;           /* slider/scroller value of the last Scroll event */
    volatile int edited;     /* string: set by the edit hook (input.device's task) */
    char *tagstr, *hint, *text, *extra;
    int visible;
    /* timer */
    struct Hook edit_hook;
    struct TimeRequest *tio;
    int interval, enabled, pending;
    /* docs/ui.md */
    Object *strip;           /* menu: a hidden top-level menu's own strip (context / pop-up) */
    char *ctxmenu;           /* ContextMenu set at run time (NULL = the .afg's contextmenu=) */
    int dead;                /* menu removed at run time */
    struct Node *sbnode;     /* tool: its speedbar node */
    bb_ctl *bar;             /* tool: its toolbar */
    Object *img, *selimg;    /* tool / image / button: bitmap.image objects (ours to dispose) */
    Object **panels;         /* statusbar: one read-only button per panel */
    int npanels;
    void *ext;               /* the ui_*.c kinds' own state */
    char *ret_buf;           /* the last string returned by a control without a form */
};

struct bb_form {
    bb_form *next;
    afg_node *afg;
    char *file;
    bb_form_event_fn fn;
    bb_form_has_event_fn has;
    void *ud;
    Object *winobj, *root;
    struct Window *win;
    struct bb_ctl self;
    struct bb_ctl **ctls;
    int nctls;
    char *ret;               /* the last string returned */
    int loaded, unloading, enabled;
    int16 lastw, lasth;
    struct Hook idcmp_hook;  /* IDCMPUPDATE: per-keystroke Change, slider Scroll */
    uint16 upd[32];          /* gadget ids reported by the hook, handled after it */
    int nupd;
    /* docs/ui.md */
    Object *menustrip;       /* WINDOW_MenuStrip (menuclass) */
    struct Hook ctx_hook;    /* WA_ContextMenuHook */
    const char *ctx_control; /* the control the last context menu was opened over */
    /* mouse events, noted by the IDCMP hook (with the message's position and time) */
    struct { uint32 mcls; uint16 code, qual; int16 x, y, wheel; uint32 secs, micros; } mq[32];
    int nmq;
    int mouse_wanted;        /* some canvas / the form has a Mouse* event sub */
    bb_ctl *capture;         /* the canvas that got the button press */
    int buttons;             /* VB bits of the buttons held */
    uint32 last_secs, last_micros;
    bb_ctl *last_down;
    int32_t movex, movey;    /* the last MouseMove position reported while dragging */
};


/* forms.c helpers used by the ui_*.c files */
#define tg bbf_tg
#define new_obj bbf_new_obj
#define cls bbf_cls
#define fire bbf_fire
#define fire0 bbf_fire0
#define set_attr bbf_set_attr
#define get_attr bbf_get_attr
#define relayout bbf_relayout
#define xstrdup bbf_xstrdup
#define ret_str bbf_ret_str
#define ret_int bbf_ret_int
#define vint bbf_vint
#define vstr bbf_vstr
#define vb_bool bbf_vb_bool
#define forms bbf_forms
#define ending bbf_ending

enum { C_WINDOW, C_LAYOUT, C_BUTTON, C_STRING, C_INTEGER, C_CHECKBOX, C_CHOOSER, C_RADIO, C_SLIDER, C_SCROLLER,
       C_LISTBROWSER, C_LABEL, C_SPACE, C_FUELGAUGE, C_GETFILE, C_TEXTEDITOR, C_REQUESTER,
       C_MENU, C_POPUPMENU, C_POPUPMENUITEM, C_SPEEDBAR, C_BITMAP, C_CLICKTAB, C_AREXX, C_NUM };

extern bb_form *forms;
extern int ending;
void tg(tags *t, Tag tag, uint32 data);
Object *new_obj(int c, tags *t);
Class *cls(int c);
int fire(bb_form *f, const char *ctl, const char *event, int argc, int32_t *args);
int fire0(bb_ctl *c, const char *event);
void set_attr(bb_ctl *c, Tag tag, uint32 v);
uint32 get_attr(bb_ctl *c, Tag tag);
void relayout(bb_form *f);
char *xstrdup(const char *s);
int ret_str(bb_ctl *c, bb_fval *out, const char *s);
int ret_int(bb_fval *out, int32 v);
int32 vint(const bb_fval *v);
const char *vstr(const bb_fval *v, char *buf);
int vb_bool(int b);
bb_ctl *bbf_ctl_by_gid(bb_form *f, uint32 gid);

void bbf_gadget_tags(bb_ctl *c, tags *t);

/* ui_bars.c: the kinds of docs/ui.md that are built into the layout (toolbar, statusbar,
   image, ...) and the ones without a gadget (tool, commondialog) */
Object *bbf_ext_build(bb_form *f, afg_node *n, bb_ctl *c, tags *t);
int bbf_ext_get(bb_ctl *c, const char *prop, int index, bb_fval *out);
int bbf_ext_set(bb_ctl *c, const char *prop, int index, const bb_fval *v);
int bbf_ext_call(bb_ctl *c, const char *method, int argc, const bb_fval *argv, bb_fval *ret);
void bbf_ext_gadget_up(bb_form *f, bb_ctl *c, uint16 code);
void bbf_ext_free(bb_ctl *c);         /* after the window object (and its gadgets) is gone */
Object *bbf_load_image(const char *file, const char *selfile);
void bbf_tools_follow_menu(bb_form *f, const char *menu, int enabled);
void bbf_ext_cleanup(void);
struct Library *bbf_class_lib(int c);
void bbf_items_insert(bb_ctl *c, int at, const char *s);

/* ui_dialog.c: commondialog (also used by CreateObject("Boing.CommonDialog")) */
int bbf_dialog_get(bb_ctl *c, const char *prop, int index, bb_fval *out);
int bbf_dialog_set(bb_ctl *c, const char *prop, int index, const bb_fval *v);
int bbf_dialog_call(bb_ctl *c, const char *method, int argc, const bb_fval *argv, bb_fval *ret);
void bbf_dialog_free(bb_ctl *c);
void bbf_dialog_cleanup(void);
struct Window *bbf_front_window(void);
void bbf_handle_form(bb_form *f);       /* one round of a window's input */
void bbf_form_discard(bb_form *f);      /* free a private form (requesters) without events */

/* ui_menu.c */
int bbf_menus_build(bb_form *f, tags *wintags);    /* adds WINDOW_MenuStrip etc.; 0 = failed */
void bbf_menus_free(bb_form *f);
void bbf_menus_pick(bb_form *f);                    /* WMHI_MENUPICK */
int bbf_menu_get(bb_ctl *c, const char *prop, bb_fval *out);
int bbf_menu_set(bb_ctl *c, const char *prop, const bb_fval *v);
int bbf_form_menu_call(bb_form *f, const char *method, int argc, const bb_fval *argv, bb_fval *ret);
char *bbf_strip_underscore(const char *s);

#endif
