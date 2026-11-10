// textutil.cpp - a Boing BASIC extension in C++: a WordCount class built on std::map and
// std::string, and a function WordTotal. The C++ object lives behind a pointer inside the
// bb_obj; s_terminate deletes it when BASIC lets go of the object.
#include "boing_ext.h"
#include <algorithm>
#include <cctype>
#include <map>
#include <string>
#include <strings.h>
#include <utility>
#include <vector>

namespace {

// the C++ side: knows nothing about Boing BASIC
class Words {
public:
    void add(const std::string &text) {
        std::string w;
        for (char ch : text + " ") {
            unsigned char c = static_cast<unsigned char>(ch);
            if (std::isalnum(c) || c == '\'') w += static_cast<char>(std::tolower(c));
            else if (!w.empty()) { counts_[w]++; total_++; w.clear(); }
        }
    }
    long count(std::string w) const {
        std::transform(w.begin(), w.end(), w.begin(), [](unsigned char c) { return std::tolower(c); });
        auto it = counts_.find(w);
        return it == counts_.end() ? 0 : it->second;
    }
    std::string top(long n) const {        // "word:count word:count ..." most frequent first
        std::vector<std::pair<std::string, long>> v(counts_.begin(), counts_.end());
        std::stable_sort(v.begin(), v.end(), [](const auto &a, const auto &b) { return a.second > b.second; });
        std::string out;
        for (long i = 0; i < n && i < static_cast<long>(v.size()); i++)
            out += (i ? " " : "") + v[i].first + ":" + std::to_string(v[i].second);
        return out;
    }
    long distinct() const { return static_cast<long>(counts_.size()); }
    long total() const { return total_; }
private:
    std::map<std::string, long> counts_;
    long total_ = 0;
};

// the Boing BASIC side
struct wc_obj { bb_obj hdr; Words *w; };

enum { M_ADD, M_COUNT, M_TOP, P_DISTINCT, P_TOTAL };

int32_t wc_find(const bb_class *, const char *name)
{
    static const struct { const char *n; int32_t id; } m[] = {
        {"Add", M_ADD}, {"Count", M_COUNT}, {"Top", M_TOP}, {"Distinct", P_DISTINCT}, {"Total", P_TOTAL}};
    for (const auto &e : m)
        if (!strcasecmp(e.n, name)) return e.id;
    return BB_NOMEMBER;
}

std::string arg_string(const bb_value *v)       // any BASIC value as a std::string
{
    bb_str *s = bb_v_to_str(v);
    std::string r(bb_str_ptr(s), s ? s->len : 0);
    bb_str_release(s);
    return r;
}

void wc_invoke(bb_obj *self, int32_t id, int, int argc, bb_value *argv, bb_value *ret)
{
    Words *w = reinterpret_cast<wc_obj *>(self)->w;
    try {
        switch (id) {
        case M_ADD: if (argc != 1) bb_raise(450, nullptr); w->add(arg_string(&argv[0])); return;
        case M_COUNT: *ret = bb_v_long(w->count(arg_string(&argv[0]))); return;
        case M_TOP: *ret = bb_v_str(bb_str_from_c(w->top(bb_v_to_long(&argv[0])).c_str())); return;
        case P_DISTINCT: *ret = bb_v_long(w->distinct()); return;
        case P_TOTAL: *ret = bb_v_long(w->total()); return;
        }
    } catch (const std::bad_alloc &) {
        bb_raise(7, nullptr);                   // out of memory: never let a C++ exception reach BASIC
    }
    bb_raise(438, nullptr);
}

void wc_terminate(bb_obj *self) { delete reinterpret_cast<wc_obj *>(self)->w; }

const bb_class wc_class = {"WordCount", sizeof(wc_obj), wc_find, wc_invoke, wc_terminate,
                           nullptr, nullptr, 0, nullptr, 0, nullptr, nullptr};

bb_obj *new_wc()
{
    bb_obj *o = bb_obj_new(&wc_class);
    reinterpret_cast<wc_obj *>(o)->w = new Words();
    return o;
}

bb_value word_total(int, bb_value *argv)
{
    Words w;
    w.add(bb_str_ptr(argv[0].u.s));             // a String argument arrives as a bb_str
    return bb_v_long(w.total());
}

} // namespace

BB_EXTENSION(textutil)
{
    bb_register_class("WordCount", &wc_class, new_wc);
    bb_register_function("WordTotal", word_total);
}
