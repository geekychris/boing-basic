// shapes.cpp - a sample Boing BASIC extension in C++ (docs/extensions.md): a class Shape backed
// by a C++ object, and a function Gcd. boing_ext.h gives BB_EXTENSION C linkage; the class's
// find/invoke are plain functions, the C++ object lives inside the bb_obj.
#include "boing_ext.h"
#include <new>
#include <string>
#include <strings.h>

namespace {

class Rect {
public:
    Rect() : w_(1), h_(1) {}
    long area() const { return w_ * h_; }
    std::string describe() const { return std::to_string(w_) + "x" + std::to_string(h_); }
    long w_, h_;
};

struct shape_obj { bb_obj hdr; Rect *r; };

enum { M_AREA, M_DESCRIBE, P_WIDTH, P_HEIGHT };

int32_t s_find(const bb_class *, const char *name)
{
    static const struct { const char *n; int32_t id; } m[] = {
        {"Area", M_AREA}, {"Describe", M_DESCRIBE}, {"Width", P_WIDTH}, {"Height", P_HEIGHT}};
    for (const auto &e : m)
        if (!strcasecmp(e.n, name)) return e.id;
    return BB_NOMEMBER;
}

void s_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    Rect *r = reinterpret_cast<shape_obj *>(self)->r;
    bool let = (kind & BB_INV_LET) != 0;
    switch (id) {
    case M_AREA: *ret = bb_v_long(r->area()); return;
    case M_DESCRIBE: *ret = bb_v_str(bb_str_from_c(r->describe().c_str())); return;
    case P_WIDTH: if (let) r->w_ = bb_v_to_long(&argv[argc - 1]); else *ret = bb_v_long(r->w_); return;
    case P_HEIGHT: if (let) r->h_ = bb_v_to_long(&argv[argc - 1]); else *ret = bb_v_long(r->h_); return;
    }
    bb_raise(438, nullptr);
}

void s_terminate(bb_obj *self) { delete reinterpret_cast<shape_obj *>(self)->r; }

const bb_class shape_class = {"Shape", sizeof(shape_obj), s_find, s_invoke, s_terminate,
                              nullptr, nullptr, 0, nullptr, 0, nullptr, nullptr};

bb_obj *new_shape()
{
    bb_obj *o = bb_obj_new(&shape_class);
    reinterpret_cast<shape_obj *>(o)->r = new Rect();
    return o;
}

bb_value gcd(int, bb_value *argv)
{
    long a = argv[0].u.l, b = argv[1].u.l;
    while (b) { long t = a % b; a = b; b = t; }
    return bb_v_long(a < 0 ? -a : a);
}

} // namespace

BB_EXTENSION(shapes)
{
    bb_register_class("Shape", &shape_class, new_shape);
    bb_register_function("Gcd", gcd);
}
