/* fpath.h - on AmigaOS 4, fopen goes through bb_plat_fopen, which turns "DH1:/name" into
 * "DH1:name" (App.Path & "/" & name for a program at a volume root). Include after <stdio.h>
 * in the runtime files that open files. */
#ifndef BB_FPATH_H
#define BB_FPATH_H
#ifdef __amigaos4__
#include <stdio.h>
FILE *bb_plat_fopen(const char *path, const char *mode);
#define fopen(p, m) bb_plat_fopen((p), (m))
#endif
#endif
