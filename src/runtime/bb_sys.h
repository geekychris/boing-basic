/* Operating system services behind BASIC's Shell, Environ, Command, App, Beep, Clipboard and
 * Dir, one implementation per platform (src/runtime/os4/sys.c, src/runtime/posix/sys.c).
 * Strings returned as char * are malloc'd (the caller frees them); const char * ones are
 * owned by the runtime. Paths are the platform's own (AmigaDOS "Work:dir/file" on OS4). */
#ifndef BB_SYS_H
#define BB_SYS_H

/* At program start: the command line. For `boing run prog.bas a b`, argv is {"prog.bas",
 * "a", "b"} and app_dir the directory of prog.bas (NULL = the executable's directory). */
void bb_sys_init(int argc, char **argv, const char *app_dir);

/* docs/ui.md: the WBStartup message when started from Workbench (NULL from a shell), and the
 * program's arguments one by one (argv[1..]) */
void *bb_sys_wbstartup(void);
int bb_sys_argc(void);
const char *bb_sys_argv(int i);

const char *bb_sys_command(void);       /* Command(): the arguments, as typed (joined by spaces) */
const char *bb_sys_app_path(void);      /* App.Path: the program's directory, no trailing / */
const char *bb_sys_app_exename(void);   /* App.EXEName: the program name without directory */

/* Shell(cmd [, wait]): run a command. wait = 0: asynchronously (VB's Shell) and return a
 * nonzero id, or 0 if it couldn't start; wait = 1: return its return code (-1 = couldn't start). */
long bb_sys_shell(const char *cmd, int wait);

char *bb_sys_environ(const char *name);     /* Environ("name"): NULL if unset */
/* Process.SetEnv: set (value NULL: remove) a variable for this program and the commands it
 * runs (a local shell variable on AmigaOS). 0 = ok. */
int bb_sys_setenv(const char *name, const char *value);

/* Process.Run: run cmd (a shell command line) with in[0..inlen) as its input (in NULL: no
 * input), wait for it, and return its exit code (the return code on AmigaOS) with what it wrote
 * to standard output and standard error in malloc'd buffers *out / *eout (lengths *outlen /
 * *eoutlen). -1 when it couldn't be started, with a message in err. */
int bb_sys_run(const char *cmd, const char *in, long inlen, char **out, long *outlen, char **eout, long *eoutlen,
               char *err, int errsz);
void bb_sys_beep(void);

char *bb_sys_clipboard_get(void);           /* Clipboard.GetText: "" if empty, NULL on error */
int bb_sys_clipboard_set(const char *text); /* Clipboard.SetText: 0 = ok */
extern int bb_sys_clip_unit;
void bb_sys_set_wbproject(void *wbs);       /* OS4: boing run from a project icon (wbstart.c) */
void *bb_sys_wbproject(void);               /* Clipboard.Unit: the clipboard unit (0-255) both use */

/* Dir(pattern [, attributes]): the first match, then bb_sys_dir_next() for the next ones
 * (Dir with no arguments); NULL when there are no more. The pattern's file part may use VB
 * wildcards * and ? (and on OS4 also AmigaDOS #? patterns). attributes: VB's vbDirectory (16)
 * includes directories, vbNormal (0) only files. Names are returned without directory. */
char *bb_sys_dir_first(const char *pattern, int attributes);
char *bb_sys_dir_next(void);

/* Files and directories; 0 = ok, else a VB error number (53 File not found, 75 Path/File
 * access error, 76 Path not found, 58 File already exists, 70 Permission denied). */
int bb_sys_kill(const char *pattern);       /* wildcards allowed, as Kill */
int bb_sys_mkdir(const char *path);
int bb_sys_rmdir(const char *path);
int bb_sys_chdir(const char *path);
char *bb_sys_curdir(void);
int bb_sys_rename(const char *from, const char *to);   /* Name ... As */
int bb_sys_filecopy(const char *from, const char *to);
long bb_sys_filelen(const char *path);      /* -1 if not found */
int bb_sys_getattr(const char *path);       /* GetAttr: vbDirectory 16, vbReadOnly 1, -1 = not found */

/* The full path of a file or directory ("PROGDIR:" -> "Work:Boing"); malloc'd, NULL if
 * it doesn't exist. */
char *bb_sys_real_path(const char *path);
/* Does "path" name an existing file on a mounted volume? Never asks the user: on AmigaOS a
   missing assign/volume ("BOING:...") is looked up in the DOS list first (no "Please insert
   volume" requester), and requesters are off while probing. */
int bb_sys_probe(const char *path);

#endif
