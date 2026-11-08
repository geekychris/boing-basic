/*
 * platform.h - what libboing needs from the operating system.
 *
 * Implemented once per platform: src/runtime/posix/platform.c (macOS/Linux)
 * and src/runtime/os4/platform.c (AmigaOS 4, dos.library etc.). The portable
 * runtime only uses stdio (fopen/fread/...) and these functions.
 */
#ifndef BOING_PLATFORM_H
#define BOING_PLATFORM_H

#include <stdint.h>
#include <stddef.h>

typedef struct bb_tm {
    int year, month, day;       /* 1-based month and day */
    int hour, minute, second;
    int msec;
} bb_tm;

void bb_plat_init(int argc, char **argv);
void bb_plat_shutdown(void);
/* console */
void bb_plat_write(const char *p, size_t n);             /* stdout */
void bb_plat_write_err(const char *p, size_t n);         /* stderr */
void bb_plat_flush(void);
int bb_plat_read_line(char **line, size_t *len);         /* malloc'ed, no newline; 0 = EOF */
/* time */
void bb_plat_localtime(bb_tm *tm);
double bb_plat_seconds(void);                            /* monotonic-ish, seconds */
void bb_plat_sleep_ms(long ms);
/* Ctrl-C: nonzero if a break was requested since the last call (clears it) */
int bb_plat_break(void);
/* file system: 0 = ok, otherwise a VB error number (53, 75, 76, ...) */
int bb_plat_remove(const char *path);
int bb_plat_rename(const char *from, const char *to);
int bb_plat_mkdir(const char *path);
int bb_plat_rmdir(const char *path);
int bb_plat_chdir(const char *path);
int bb_plat_getcwd(char *buf, size_t n);
int bb_plat_file_size(const char *path, long *size);    /* also: exists */
int bb_plat_is_dir(const char *path);
/* directory scan for Dir(): returns handle or NULL */
void *bb_plat_dir_open(const char *dir);
const char *bb_plat_dir_next(void *h, int *is_dir);      /* NULL = end */
void bb_plat_dir_close(void *h);
char bb_plat_path_sep(void);                             /* '/' */
/* misc */
const char *bb_plat_getenv(const char *name);
const char *bb_plat_env_at(int index);                   /* Environ(n), 1-based; NULL = past end */
int bb_plat_system(const char *cmd);
void bb_plat_beep(void);
/* UI fallbacks (console versions on posix; requesters on OS4) */
long bb_plat_msgbox(const char *prompt, long buttons, const char *title);
char *bb_plat_inputbox(const char *prompt, const char *title, const char *def); /* malloc'ed or NULL */

#endif
