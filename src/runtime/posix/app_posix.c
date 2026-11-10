/* App / Clipboard / Printer members of docs/ui.md on hosts without AmigaOS: settings under
 * $BOING_SETTINGS or ~/.boing/; tooltypes, ARexx, Workbench and printing don't exist here
 * (ToolType gives the default, the rest error 438). */
#include "../boing.h"
#include "../bb_app.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

const char *bb_app_settings_dir(int archive)
{
    static char dir[1024];
    (void)archive;
    if (!dir[0]) {
        const char *e = getenv("BOING_SETTINGS"), *h = getenv("HOME");
        if (e && *e) snprintf(dir, sizeof dir, "%s/", e);
        else snprintf(dir, sizeof dir, "%s/.boing/", h ? h : ".");
    }
    return dir;
}

static char hold[1024];

const char *bb_app_plat_decimal_point(void) { return "."; }
const char *bb_app_plat_group_separator(void) { return ","; }
int bb_app_plat_format_date(double d, const char *fmt, char *out, int n) { (void)d; (void)fmt; (void)out; (void)n; return 0; }

int bb_app_plat_get(const char *prop, int index, bb_fval *out)
{
    (void)index;
    if (!strcasecmp(prop, "FromWorkbench")) { out->type = BB_FV_INT; out->i = 0; return 0; }
    if (!strcasecmp(prop, "ToolTypeCount") || !strcasecmp(prop, "DropCount")) { out->type = BB_FV_INT; out->i = 0; return 0; }
    if (!strcasecmp(prop, "ARexxRC")) { out->type = BB_FV_INT; out->i = 0; return 0; }
    if (!strcasecmp(prop, "Language")) { out->type = BB_FV_STR; out->s = "english"; return 0; }
    return 438;
}

int bb_app_plat_set(const char *prop, int index, const bb_fval *v)
{
    (void)prop; (void)index; (void)v;
    return 438;
}

int bb_app_plat_call(const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    /* App.ToolType(name [, default]) and App.Str(id, default): the default */
    if ((!strcasecmp(method, "ToolType") || !strcasecmp(method, "Str")) && argc >= 1) {
        const bb_fval *d = argc > 1 ? &argv[1] : NULL;
        ret->type = BB_FV_STR;
        if (d && d->type == BB_FV_STR) snprintf(hold, sizeof hold, "%s", d->s ? d->s : "");
        else if (d && d->type == BB_FV_INT) snprintf(hold, sizeof hold, "%ld", (long)d->i);
        else hold[0] = 0;
        ret->s = hold;
        return 0;
    }
    if (!strcasecmp(method, "OpenCatalog")) { ret->type = BB_FV_INT; ret->i = 0; return 0; }
    return 438;
}

int bb_clip_plat_call(const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    (void)argc; (void)argv;
    if (!strcasecmp(method, "HasPicture")) { ret->type = BB_FV_INT; ret->i = 0; return 0; }
    return 438;
}

int bb_prn_plat_get(const char *prop, int index, bb_fval *out) { (void)prop; (void)index; (void)out; return 438; }
int bb_prn_plat_set(const char *prop, int index, const bb_fval *v) { (void)prop; (void)index; (void)v; return 438; }
int bb_prn_plat_call(const char *method, int argc, const bb_fval *argv, bb_fval *ret)
{
    (void)method; (void)argc; (void)argv; (void)ret;
    return 438;
}
