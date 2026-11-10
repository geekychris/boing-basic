Sub Main()
    opts.Hello
    opts.Caption = "x"
    Print opts.Caption
    Load Settings
    Print Settings.Caption
    Unload Settings
    Unload opts
    Print "done"
End Sub
