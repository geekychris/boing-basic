' Translated strings: the catalog's text if there is one, else the default
Option Explicit
Const MSG_HELLO = 1, MSG_FILES = 2

If App.OpenCatalog("greeter.catalog", "english") Then Print "(catalog open)"
Print App.Str(MSG_HELLO, "Hello!")
Print Replace(App.Str(MSG_FILES, "%1 files"), "%1", CStr(12))
