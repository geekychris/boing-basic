/* ext.c - the registry of classes and functions (boing_ext.h): the runtime's own classes
   (Canvas, Engine3D, Audio) and those of linked extensions */
#include "boing_ext.h"
#include "canvas.h"
#include "audio.h"
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <stdio.h>

typedef struct { const char *name; const bb_class *cls; bb_obj *(*create)(void); const char *const *events; } ext_class;
typedef struct { const char *name; bb_ext_fn fn; } ext_func;
static ext_class *classes;
static int nclasses, capclasses;
static ext_func *funcs;
static int nfuncs, capfuncs;
static const char **linked;
static int nlinked;
static int builtins_done;

const bb_class *bb_canvas_class(void);
const bb_class *bb_engine3d_class(void);
const bb_class *bb_audio_class(void);
const bb_class *bb_http_class(void);     /* http_obj.c */
bb_obj *bb_http_new(void);
extern const char *const bb_http_events[];
const bb_class *bb_dict_class(void);    /* dict.c */
bb_obj *bb_dict_new(void);
const bb_class *bb_sbuilder_class(void);      /* sbuilder.c */
bb_obj *bb_sbuilder_new(void);
const bb_class *bb_socket_class(void);   /* socket.c */
bb_obj *bb_socket_new(void);
extern const char *const bb_socket_events[];
static bb_obj *new_canvas(void) { return bb_canvas_new(320, 200, NULL); }

static void builtins(void)
{
    if (builtins_done) return;
    builtins_done = 1;
    bb_register_class("Canvas", bb_canvas_class(), new_canvas);
    bb_register_class("Engine3D", bb_engine3d_class(), bb_engine3d_new);
    bb_register_class("Audio", bb_audio_class(), bb_audio_new);
    bb_register_class("Http", bb_http_class(), bb_http_new);
    bb_register_class_events("Http", bb_http_events);
    bb_register_class("Dictionary", bb_dict_class(), bb_dict_new);
    bb_register_class("StringBuilder", bb_sbuilder_class(), bb_sbuilder_new);
    bb_register_class("Socket", bb_socket_class(), bb_socket_new);
    bb_register_class_events("Socket", bb_socket_events);
}

static const char *strip(const char *name) { return name && !strncasecmp(name, "Boing.", 6) ? name + 6 : name; }

static ext_class *find_class(const char *name);

void bb_register_class(const char *name, const bb_class *cls, bb_obj *(*create)(void))
{
    int i;
    builtins();
    name = strip(name);
    for (i = 0; i < nclasses; i++)
        if (!strcasecmp(classes[i].name, name)) { classes[i].cls = cls; classes[i].create = create; return; }
    if (nclasses == capclasses) {
        capclasses = capclasses ? capclasses * 2 : 8;
        classes = (ext_class *)realloc(classes, sizeof(ext_class) * (size_t)capclasses);
    }
    classes[nclasses].name = name;
    classes[nclasses].cls = cls;
    classes[nclasses].create = create;
    classes[nclasses].events = NULL;
    nclasses++;
}

/* a runtime class's events (WithEvents): NULL-terminated names in index order; the class raises
   them with bb_event_raise(obj, index, name, argc, argv) */
void bb_register_class_events(const char *name, const char *const *events)
{
    ext_class *c = find_class(name);
    if (c) c->events = events;
}

const char *const *bb_runtime_class_events(const char *name)
{
    ext_class *c = find_class(name);
    return c ? c->events : NULL;
}

void bb_register_function(const char *name, bb_ext_fn fn)
{
    int i;
    for (i = 0; i < nfuncs; i++) if (!strcasecmp(funcs[i].name, name)) { funcs[i].fn = fn; return; }
    if (nfuncs == capfuncs) {
        capfuncs = capfuncs ? capfuncs * 2 : 8;
        funcs = (ext_func *)realloc(funcs, sizeof(ext_func) * (size_t)capfuncs);
    }
    funcs[nfuncs].name = name;
    funcs[nfuncs].fn = fn;
    nfuncs++;
}

static ext_class *find_class(const char *name)
{
    int i;
    builtins();
    name = strip(name);
    if (!name) return NULL;
    for (i = 0; i < nclasses; i++) if (!strcasecmp(classes[i].name, name)) return &classes[i];
    return NULL;
}

const bb_class *bb_runtime_class(const char *name) { ext_class *c = find_class(name); return c ? c->cls : NULL; }
bb_obj *bb_ext_create(const char *name) { ext_class *c = find_class(name); return c && c->create ? c->create() : NULL; }

bb_obj *bb_autonew_named(bb_obj **p, const char *name)
{
    bb_obj *o;
    if (p && *p) return *p;
    o = bb_ext_create(name);
    if (!o) bb_raise(429, NULL);
    if (p) *p = o;
    return o;
}

bb_ext_fn bb_ext_function(const char *name)
{
    int i;
    for (i = 0; i < nfuncs; i++) if (!strcasecmp(funcs[i].name, name)) return funcs[i].fn;
    return NULL;
}

int bb_ext_class_count(void) { builtins(); return nclasses; }
const char *bb_ext_class_name(int i) { builtins(); return i >= 0 && i < nclasses ? classes[i].name : NULL; }

void bb_ext_mark_linked(const char *ext)
{
    linked = (const char **)realloc(linked, sizeof(char *) * (size_t)(nlinked + 1));
    linked[nlinked++] = ext;
}

int bb_ext_linked(const char *ext)
{
    int i;
    for (i = 0; i < nlinked; i++) if (!strcasecmp(linked[i], ext)) return 1;
    return 0;
}

bb_value bb_ext_call(const char *name, int argc, bb_value *argv)
{
    bb_ext_fn f = bb_ext_function(name);
    char msg[160];
    if (!f) {
        snprintf(msg, sizeof msg, "function '%s' is not linked into this program (an extension or CSource missing)", name);
        bb_raise(453, msg);
    }
    return f(argc, argv);
}
