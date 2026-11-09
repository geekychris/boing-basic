/* Forms: the C interface between the BASIC runtime (VM and C back end) and a platform's form
 * implementation (src/runtime/os4/forms.c on ReAction). What each control kind supports is
 * docs/forms-events.md.
 *
 * Values cross the interface as bb_fval (an integer or a string); the BASIC side converts its
 * Variants. Strings returned by the forms code stay valid until the next call on the same
 * form; the caller copies them. Every function returning int returns 0 or a VB error number:
 * 438 "Object doesn't support this property or method", 380 "Invalid property value",
 * 381 "Invalid property array index", 383 "property is read-only", 7 "Out of memory",
 * 364 "Object was unloaded", 5 "Invalid procedure call or argument". */
#ifndef BB_FORMS_H
#define BB_FORMS_H

#include <stdint.h>

typedef struct bb_form bb_form;
typedef struct bb_ctl bb_ctl;

enum { BB_FV_NONE, BB_FV_INT, BB_FV_STR, BB_FV_OBJ };
typedef struct bb_fval {
    int type;
    int32_t i;
    const char *s;
    void *o;            /* BB_FV_OBJ: a bb_obj * argument that isn't a control (a Canvas) */
} bb_fval;

/* An event: ctl is the control's name, or "Form" for the form's own events; event is
 * "Click", "Load", ... args are the event's arguments in order (all Integer/Long), the sub
 * may change them (ByRef Cancel, KeyAscii...). The handler returns 0, or nonzero when the
 * program must end (an unhandled runtime error or End in the event sub). */
typedef int (*bb_form_event_fn)(void *ud, bb_form *f, const char *ctl, const char *event, int argc, int32_t *args);

/* Does the program have a sub for this event? (So the forms code can skip work, e.g. only
 * ask for key events when Form_KeyDown exists.) May be NULL = every event is wanted. */
typedef int (*bb_form_has_event_fn)(void *ud, bb_form *f, const char *ctl, const char *event);

/* Load a form from .afg text (file is for error messages). Fires Form_Load; doesn't show it.
 * NULL with "file:line: message" in err. */
bb_form *bb_form_load(const char *afg_text, const char *file, bb_form_event_fn fn, bb_form_has_event_fn has,
                      void *ud, char *err, int errlen);

const char *bb_form_name(bb_form *f);        /* the window's name= */
int bb_form_show(bb_form *f);
int bb_form_hide(bb_form *f);
/* Unload: fires QueryUnload/Unload (mode 1 = from code), returns 1 if a sub cancelled it. */
int bb_form_unload(bb_form *f);
bb_form *bb_form_find(const char *name);     /* a loaded form by name */

/* The form as an object (Caption, Width...) and its controls by name (case-insensitive). */
bb_ctl *bb_form_self(bb_form *f);
bb_ctl *bb_form_ctl(bb_form *f, const char *name);
const char *bb_ctl_kind(bb_ctl *c);          /* "button", "window"... */

/* Properties. index is the array index for List(i), else -1. */
int bb_ctl_get(bb_ctl *c, const char *prop, int index, bb_fval *out);
int bb_ctl_set(bb_ctl *c, const char *prop, int index, const bb_fval *v);
/* Methods: AddItem, RemoveItem, Clear, SetFocus, Refresh, ShowOpen, Show, Hide, Move. */
int bb_ctl_call(bb_ctl *c, const char *method, int argc, const bb_fval *argv, bb_fval *ret);

/* Run the event loop until every form is unloaded or bb_forms_end() is called (End, or an
 * event handler returned nonzero). Returns 0, or nonzero when ended by a handler. */
int bb_forms_run(void);
void bb_forms_end(void);
/* Unload every form without events and free everything (program end). */
void bb_forms_cleanup(void);
/* DoEvents: handle what's pending without waiting. */
void bb_forms_doevents(void);

/* Requesters (work without any form too). MsgBox returns vbOK=1, vbCancel=2, vbAbort=3,
 * vbRetry=4, vbIgnore=5, vbYes=6, vbNo=7. InputBox returns a malloc'd string, or NULL when
 * cancelled. title NULL = the program's name. */
int bb_ui_msgbox(const char *prompt, int buttons, const char *title);
char *bb_ui_inputbox(const char *prompt, const char *title, const char *def);
/* A requester with the program's own buttons, "_Save|_Discard|_Cancel": returns 1 for the
 * leftmost button ... n for the last (also Esc / close). icon = MsgBox's vbCritical... bits. */
int bb_ui_request(const char *prompt, const char *buttons, const char *title, int icon);

/* A CommonDialog without a form (CreateObject("Boing.CommonDialog")): a bb_ctl of kind
 * commondialog for bb_ctl_get/set/call. NULL where the platform has no requesters. */
bb_ctl *bb_dialog_new(void);
void bb_dialog_free(bb_ctl *c);

/* Canvas (canvas.c): the OS window (struct Window * on AmigaOS) of a control and the control's
 * box inside it. 0 when the form isn't open or the platform has no windows. */
int bb_ctl_os_window(bb_ctl *c, void **window, int *x, int *y, int *w, int *h);

/* Test support: the screen rectangle of a control (for input injection). 0 if not shown. */
int bb_ctl_screen_box(bb_ctl *c, int *x, int *y, int *w, int *h);

#endif
