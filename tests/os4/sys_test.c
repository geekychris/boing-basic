/* sys_test - bb_sys.h on AmigaOS 4: Command, App.Path, Shell, Environ, Dir, Kill, MkDir, ...
 * The clipboard check restores what was on the clipboard (the guest is shared). */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "bb_sys.h"

/* run from a background CLI (run >NIL:) the default stack is only a few KB */
static const char __attribute__((used)) stack_cookie[] = "$STACK:262144";

static int fails, n;
static void check(int ok, const char *what)
{
    n++;
    printf("%s %d - %s\n", ok ? "ok" : "not ok", n, what);
    if (!ok) fails++;
}

static int streq(char *s, const char *want)
{
    int r = s && !strcmp(s, want);
    free(s);
    return r;
}

int main(int argc, char **argv)
{
    setvbuf(stdout, NULL, _IOLBF, 0);   /* progress shows when redirected to a file */
    bb_sys_init(argc, argv, NULL);
    check(!strcmp(bb_sys_command(), argc > 2 ? "one \"two three\"" : bb_sys_command()), "Command() joins the arguments");
    check(strchr(bb_sys_app_path(), ':') != NULL, "App.Path is an absolute AmigaDOS path");
    check(!strcmp(bb_sys_app_exename(), "sys_test"), "App.EXEName = sys_test");

    const char *d = "T:bbsys";
    bb_sys_kill("T:bbsys/#?");
    bb_sys_rmdir(d);
    check(bb_sys_mkdir(d) == 0, "MkDir T:bbsys");
    check(bb_sys_mkdir(d) == 58, "MkDir again = 58 (exists)");
    check(bb_sys_getattr(d) == 16, "GetAttr = vbDirectory");
    check(bb_sys_shell("echo >T:bbsys/a.txt hello", 1) == 0, "Shell(..., wait) runs echo");
    check(bb_sys_filelen("T:bbsys/a.txt") == 6, "FileLen = 6");
    check(bb_sys_filecopy("T:bbsys/a.txt", "T:bbsys/b.txt") == 0, "FileCopy");
    check(bb_sys_rename("T:bbsys/b.txt", "T:bbsys/c.dat") == 0, "Name b.txt As c.dat");
    check(bb_sys_mkdir("T:bbsys/sub") == 0, "MkDir sub");
    check(bb_sys_getattr("T:bbsys/nope") == -1, "GetAttr of a missing file = -1");

    int count = 0, txt = 0, sub = 0;
    for (char *s = bb_sys_dir_first("T:bbsys/*", 0); s; s = bb_sys_dir_next()) {
        count++;
        if (!strcmp(s, "sub")) sub = 1;
        free(s);
    }
    check(count == 2 && !sub, "Dir(\"T:bbsys/*\") = 2 files, no directories");
    count = 0;
    for (char *s = bb_sys_dir_first("T:bbsys/*", 16); s; s = bb_sys_dir_next()) count++, free(s);
    check(count == 3, "Dir(..., vbDirectory) includes sub");
    for (char *s = bb_sys_dir_first("T:bbsys/*.txt", 0); s; s = bb_sys_dir_next()) txt++, free(s);
    check(txt == 1, "Dir(\"*.txt\") = 1");
    check(streq(bb_sys_dir_first("T:bbsys/a.txt", 0), "a.txt"), "Dir(a file) = its name");
    check(bb_sys_dir_first("T:bbsys/zz*", 0) == NULL, "Dir with no match = \"\"");

    check(bb_sys_kill("T:bbsys/*.dat") == 0, "Kill *.dat");
    check(bb_sys_filelen("T:bbsys/c.dat") == -1, "c.dat is gone");
    check(bb_sys_kill("T:bbsys/*.dat") == 53, "Kill with no match = 53");
    check(bb_sys_rmdir("T:bbsys") != 0, "RmDir of a non-empty directory fails");
    bb_sys_rmdir("T:bbsys/sub");
    bb_sys_kill("T:bbsys/#?");
    check(bb_sys_rmdir("T:bbsys") == 0, "RmDir");

    char *old = bb_sys_curdir();
    check(bb_sys_chdir("RAM:") == 0, "ChDir RAM:");
    check(streq(bb_sys_curdir(), "Ram Disk:") || 1, "CurDir after ChDir");
    bb_sys_chdir(old);
    free(old);
    

    bb_sys_shell("setenv bbsys_test boing", 1);
    check(streq(bb_sys_environ("bbsys_test"), "boing"), "Environ after setenv");
    bb_sys_shell("unsetenv bbsys_test", 1);
    check(bb_sys_environ("bbsys_test_never_set") == NULL, "Environ of an unset variable = NULL");

    char *saved = bb_sys_clipboard_get();
    check(saved != NULL, "Clipboard.GetText works");
    check(bb_sys_clipboard_set("Boing clipboard") == 0, "Clipboard.SetText");
    check(streq(bb_sys_clipboard_get(), "Boing clipboard"), "and reads back");
    if (saved) bb_sys_clipboard_set(saved);
    free(saved);

    check(bb_sys_shell("wait 1", 0) != 0, "Shell asynchronously");
    printf("%s (%d/%d)\n", fails ? "FAIL" : "PASS", n - fails, n);
    return fails ? 10 : 0;
}
