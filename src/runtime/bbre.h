/* bbre.h - a small regular expression engine for the RegExp class (regexp.c, docs/regexp.md).
 *
 * Syntax: literals, . [abc] [^a-z] \d \w \s \D \W \S \b \B ^ $ \n \t \r \f \v \0 \xHH \uHHHH
 * (as a byte when < 256), escapes of punctuation, ( ) (?: ) (?= ) (?! ) | * + ? {n} {n,} {n,m}
 * with lazy forms (*? +? ?? {n,m}?), backreferences \1-\9. Bytes (Latin-1 for IgnoreCase).
 * Matching is a backtracking VM with its stack on the heap (no deep C recursion) and a step
 * limit, so a pathological pattern fails with an error instead of hanging. */
#ifndef BB_RE_H
#define BB_RE_H

enum { BB_RE_ICASE = 1, BB_RE_MULTILINE = 2 };
enum { BB_RE_NOMATCH = 0, BB_RE_MATCH = 1, BB_RE_TOOLONG = -1, BB_RE_NOMEM = -2 };

typedef struct bb_re bb_re;

/* compile; NULL with a message in err on a syntax error */
bb_re *bb_re_compile(const char *pat, int patlen, int flags, char *err, int errlen);
void bb_re_free(bb_re *re);
int bb_re_ngroups(const bb_re *re);          /* capturing groups (not counting the whole match) */
/* search s[0..len) from start: BB_RE_MATCH with caps[0..2*(ngroups+1)) = start/end offsets
 * (-1 for groups that didn't take part), BB_RE_NOMATCH, or BB_RE_TOOLONG (step limit) */
int bb_re_search(const bb_re *re, const char *s, int len, int start, int *caps);

#endif
