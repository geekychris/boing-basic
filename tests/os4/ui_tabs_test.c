/* ui_tabs_test [SECONDS] - tabs pages must not draw their title again as a frame label inside
 * the page (the tab shows it). Prints PageFramed for each page, keeps the window open SECONDS
 * (default 2) for a screenshot, PASS/FAIL. */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include "bb_forms.h"

static const char __attribute__((used)) stack_cookie[] = "$STACK:262144";

static const char *afg =
    "window name=main title=\"Boing tabs test\" width=320 height=160\n"
    "vlayout id=root\n"
    "  tabs id=pages\n"
    "    vlayout title=\"General\"\n"
    "      label text=\"Page one\"\n"
    "      string id=s label=\"Name\"\n"
    "    vlayout title=\"Advanced\"\n"
    "      label text=\"Page two\"\n"
    "  timer id=quit interval=2000\n";

static int ev(void *ud, bb_form *f, const char *ctl, const char *e, int argc, int32_t *args)
{
    (void)ud; (void)argc; (void)args;
    if (!strcasecmp(ctl, "quit") && !strcasecmp(e, "Timer")) bb_form_unload(f);
    return 0;
}

int main(int argc, char **argv)
{
    char err[200], text[2048];
    setvbuf(stdout, NULL, _IOLBF, 0);
    int secs = argc > 1 ? atoi(argv[1]) : 2;
    snprintf(text, sizeof text, "%s", afg);
    char *q = strstr(text, "interval=2000");
    if (q) snprintf(q, sizeof text - (q - text), "interval=%d\n", secs * 1000);
    bb_form *f = bb_form_load(text, "tabs.afg", ev, NULL, NULL, err, sizeof err);
    if (!f) { printf("# %s\nFAIL\n", err); return 20; }
    bb_form_show(f);
    bb_fval v;
    int framed = 0;
    for (int i = 0; i < 2; i++) {
        int e = bb_ctl_get(bb_form_ctl(f, "pages"), "PageFramed", i, &v);
        printf("# page %d PageFramed %d (err %d)\n", i, e ? -1 : v.i, e);
        if (e || v.i) framed = 1;
    }
    printf("%s 1 - tab pages have no frame title of their own\n", framed ? "not ok" : "ok");
    bb_forms_run();
    bb_forms_cleanup();
    printf("%s (%d/1)\n", framed ? "FAIL" : "PASS", !framed);
    return framed ? 10 : 0;
}
