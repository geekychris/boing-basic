# CSV to SQLite

Imports a CSV file into an SQLite table, with a fuel gauge and a Cancel button. It shows the
**Timer slices** pattern for long work in a form program: each `tick_Timer` reads and inserts at
most 200 records, updates the gauge and returns, so the window stays responsive (see
docs/background-tasks.md). All rows go into one transaction: fast, and Cancel or an error leaves
the database as it was.

Uses `Csv` (the header line names the columns), `SQLite` with a prepared `INSERT` and `?`
parameters, a `getfile` for each file, a `fuelgauge` and a `timer`.

```
boing build examples/csvimport/csvimport.bbp                  # native (Extension=sqlite)
csvimport                                                     # choose the files in the window
csvimport sample.csv data.db                                  # import straight away and quit
```

`boing run` needs an interpreter with SQLite: the kit's, or one built with `make STD_EXTS=sqlite`.
`sample.csv` has 1000 records with quoted fields, doubled quotes and line breaks inside fields.
