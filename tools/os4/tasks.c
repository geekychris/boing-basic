/* tasks.c - list the guest's tasks and processes (name, priority, state), for the test runners:
 * `tasks` prints all of them (with a CLI process's running command), `tasks NAME` only those whose
 * name or command contains NAME and exits with 5
 * when there is at least one (so a runner can check that no "Boing BASIC worker" is left). */
#include <proto/exec.h>
#include <exec/execbase.h>
#include <dos/dosextens.h>
#include <stdio.h>
#include <string.h>

struct row { char name[64]; char cmd[64]; int pri; const char *state; };
static struct row rows[512];
static int nrows;

static void take(struct List *l, const char *state)
{
    struct Node *n;
    for (n = l->lh_Head; n->ln_Succ && nrows < 512; n = n->ln_Succ) {
        struct row *r = &rows[nrows++];
        strncpy(r->name, n->ln_Name ? n->ln_Name : "?", sizeof r->name - 1);
        r->name[sizeof r->name - 1] = 0;
        r->pri = n->ln_Pri;
        r->cmd[0] = 0;
        if (n->ln_Type == NT_PROCESS) {        /* a CLI's running command (BSTR) */
            struct Process *p = (struct Process *)n;
            struct CommandLineInterface *cli = (struct CommandLineInterface *)BADDR(p->pr_CLI);
            if (cli && cli->cli_Module) {
                unsigned char *b = (unsigned char *)BADDR(cli->cli_CommandName);
                if (b && b[0]) {
                    int len = b[0] < sizeof r->cmd - 1 ? b[0] : (int)sizeof r->cmd - 1;
                    memcpy(r->cmd, b + 1, len);
                    r->cmd[len] = 0;
                }
            }
        }
        r->state = state;
    }
}

int main(int argc, char **argv)
{
    struct ExecBase *sb = (struct ExecBase *)SysBase;
    const char *want = argc > 1 ? argv[1] : NULL;
    int i, found = 0;
    IExec->Disable();                       /* the lists change under a Forbid (interrupts) */
    take(&sb->TaskReady, "ready");
    take(&sb->TaskWait, "wait");
    IExec->Enable();
    for (i = 0; i < nrows; i++) {
        if (want && !strstr(rows[i].name, want) && !strstr(rows[i].cmd, want)) continue;
        found++;
        printf("%-40s pri=%4d %-5s %s\n", rows[i].name, rows[i].pri, rows[i].state, rows[i].cmd);
    }
    printf("%d task(s)%s%s\n", found, want ? " named *" : "", want ? want : "");
    return want && found ? 5 : 0;
}
