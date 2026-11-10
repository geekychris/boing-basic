/* tasklist - ready/waiting tasks: state, priority, process id/parent id, CLI number,
 * CLI command name, task name. Read-only (walks the lists under Disable()). */
#include <exec/execbase.h>
#include <exec/tasks.h>
#include <dos/dosextens.h>
#include <proto/exec.h>
#include <proto/dos.h>
#include <stdio.h>
#include <string.h>
#define SYSB ((struct ExecBase *)SysBase)
struct E { char name[64]; char cmd[80]; LONG pri; int ready; LONG cli; ULONG pid, ppid; int proc; };
static struct E e[400];
int main(void) {
    int n = 0, i, nready = 0; struct Node *nd;
    Disable();
    for (i = 0; i < 2; i++) {
        struct List *l = i == 0 ? &SYSB->TaskReady : &SYSB->TaskWait;
        for (nd = l->lh_Head; nd->ln_Succ && n < 400; nd = nd->ln_Succ) {
            struct Task *t = (struct Task *)nd;
            struct E *x = &e[n];
            strncpy(x->name, nd->ln_Name ? nd->ln_Name : "(null)", 63); x->name[63] = 0;
            x->cmd[0] = 0; x->cli = 0; x->pid = x->ppid = 0; x->proc = 0;
            if (t->tc_Node.ln_Type == NT_PROCESS) {
                struct Process *p = (struct Process *)t;
                x->proc = 1; x->cli = p->pr_CliNum; x->pid = p->pr_ProcessID; x->ppid = p->pr_ParentID;
                if (p->pr_CLI) {
                    struct CommandLineInterface *c = BADDR(p->pr_CLI);
                    if (c && c->cli_CommandName) {
                        UBYTE *b = BADDR(c->cli_CommandName); int len = b[0];
                        if (len > 79) len = 79;
                        memcpy(x->cmd, b + 1, len); x->cmd[len] = 0;
                    }
                }
            }
            x->pri = nd->ln_Pri; x->ready = (i == 0); if (i == 0) nready++; n++;
        }
    }
    Enable();
    printf("TASKS %d READY %d (this tasklist is the running one)\n", n, nready);
    for (i = 0; i < n; i++)
        printf("%-5s pri=%4ld %s pid=%3lu ppid=%3lu cli=%2ld cmd=[%s] name=[%s]\n", e[i].ready ? "READY" : "wait",
               (long)e[i].pri, e[i].proc ? "proc" : "task", (unsigned long)e[i].pid, (unsigned long)e[i].ppid,
               (long)e[i].cli, e[i].cmd, e[i].name);
    return 0;
}
