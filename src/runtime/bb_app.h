/* The App, Clipboard and Printer objects' members beyond the compiler's built-ins (docs/ui.md
 * sections 6 to 8): app.c makes them BASIC objects (late bound, like controls) and handles the
 * portable members; the platform (os4/ui_app.c, posix/app_posix.c) does the rest. Values cross
 * as bb_fval (bb_forms.h); 0 or a VB error number is returned (438 = no such member). */
#ifndef BB_APP_H
#define BB_APP_H

#include "bb_forms.h"

int bb_app_plat_get(const char *prop, int index, bb_fval *out);
int bb_app_plat_set(const char *prop, int index, const bb_fval *v);
int bb_app_plat_call(const char *method, int argc, const bb_fval *argv, bb_fval *ret);

int bb_clip_plat_call(const char *method, int argc, const bb_fval *argv, bb_fval *ret);   /* SetPicture ... */
int bb_prn_plat_get(const char *prop, int index, bb_fval *out);
int bb_prn_plat_set(const char *prop, int index, const bb_fval *v);
int bb_prn_plat_call(const char *method, int argc, const bb_fval *argv, bb_fval *ret);

/* Workbench / ARexx events for BASIC (from the platform's event loop): calls `name` in any
 * module (the startup form's first) with the arguments; 1 if there was such a sub. */
int bb_app_event(const char *name, int argc, bb_value *argv);

/* Locale (docs/ui.md): the user's decimal point and group separator ("." and "," on hosts),
 * and a date (VB serial) in the locale's format: fmt "short" (default), "long", "time", "datetime"
 * or a locale.library %-format. 0 if the platform has nothing (the portable code formats). */
const char *bb_app_plat_decimal_point(void);
const char *bb_app_plat_group_separator(void);
int bb_app_plat_format_date(double d, const char *fmt, char *out, int n);

/* the directory the settings live in: ENV: / ENVARC: on AmigaOS, ~/.boing/ (both) on hosts */
const char *bb_app_settings_dir(int archive);

/* strings returned through bb_fval by the platform stay valid until its next call */
#endif
