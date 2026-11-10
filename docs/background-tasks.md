# Background tasks (future design, not built)

Status: **not implemented**. Decided 2026-11-10: no background tasks for now; programs stay on
one task and use asynchronous I/O (Socket events, asynchronous Http) and work in Timer slices
(below). This page keeps the design in case they are wanted later.

## Doing long work today: Timer slices

A form program keeps its window responsive by doing a long job in small pieces from a Timer
event: each tick processes N items, updates a progress bar and checks a Cancel flag.

```basic
' import a big CSV into SQLite, 200 rows per tick
Private Sub importbtn_Click()
    Set table = CreateObject("Csv"): table.HasHeader = True: table.Open src.Text
    Set db = CreateObject("SQLite"): db.Open dst.Text
    db.BeginTransaction
    cancelled = False
    tick.Interval = 10: tick.Enabled = True
End Sub

Private Sub tick_Timer()
    Dim i As Long
    For i = 1 To 200
        If cancelled Or Not table.ReadRecord() Then
            tick.Enabled = False
            If cancelled Then db.Rollback Else db.Commit
            Exit Sub
        End If
        ins.Execute table.Fields
    Next
    progress.Value = table.RecordNumber
End Sub

Private Sub cancelbtn_Click()
    cancelled = True
End Sub
```

Network waits need no slicing: Socket events and asynchronous Http arrive through the event loop.

## Why there are no threads

1. The runtime is single-threaded: the error state (`bb_err`, the handler frames, the cleanup
   list), the current line, the Ctrl-C poll and, in the VM, the interpreter itself (`g_vm`, its
   value stack and the module globals) are per program, not per task. Native code keeps module
   variables in plain C globals.
2. Strings and objects are reference counted without atomic operations. Two tasks touching
   the same String corrupt its count; atomic or Forbid()-protected counts would slow every
   string and object operation in every program.
3. Windows, gadgets and their message ports belong to the task that opened them; Canvas, Audio,
   Http and Socket objects hold per-task resources (signals, timer requests, the bsdsocket
   library base, which is per opener on AmigaOS 4).
4. AmigaOS 4 has no memory protection between tasks: a race is a crash, not a wrong number.

## The design, if wanted: isolated workers with messages

```basic
Dim WithEvents job As BackgroundTask
Set job = CreateObject("BackgroundTask")
job.Start "Worker.Crunch", inputData        ' a Sub of the project, one argument

Sub job_Progress(ByVal Percent As Long)
Sub job_Message(ByVal Data As Variant)
Sub job_Done(ByVal Result As Variant)
Sub job_Error(ByVal Number As Long, ByVal Description As String)
' in the worker: ReportProgress n, PostMessage v, CheckCancel() (True after job.Cancel)
```

- Each worker is a new AmigaOS process (its own stack) running its own runtime instance: in the
  VM a second interpreter over the same read-only bytecode with its own module variables (a
  fresh copy, as at program start; nothing is shared). Native code would need the runtime's
  globals moved into a per-task context passed through the generated code, a large change to
  the C back end (and slower native code); a first version would be VM-only.
- Arguments, messages and results are deep-copied: numbers, Strings, arrays of them and
  Collections/Dictionaries of them. Forms, controls, Canvas, sockets can't be passed (error 13).
- The program's side receives messages on a message port whose signal joins the form event loop
  (the same hook Socket uses, `bb_forms_wait_hook`), so `job_*` events fire like a Timer event;
  in console programs in `DoEvents` / `WaitEvents`.
- A worker can't use forms, MsgBox or the console (only messages); Http, Socket, Process and
  files work there (each opens its own libraries).
- Strings and the reference counts need no change, since nothing is shared, at the cost of
  copying data in and out.

Cost: a VM-only first version is roughly two pull requests, and the VM and runtime globals behind
a per-task pointer touch bb-core's interpreter and error code (with the benchmark suite showing no
slowdown). Native support is the expensive part.
