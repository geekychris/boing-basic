/* sqlite.c - the SQLite standard extension (Extension=sqlite; docs/sqlite.md): the classes
 * SQLite (a database), SqlRecordset (rows of a query) and SqlStatement (a prepared statement):
 *
 *     Dim db As SQLite, rs As SqlRecordset
 *     Set db = CreateObject("SQLite")
 *     db.Open "PROGDIR:scores.db"
 *     db.Execute "INSERT INTO score VALUES (?, ?)", "Ann", 5200
 *     Set rs = db.Query("SELECT name, points FROM score ORDER BY points DESC")
 *
 * Linked with libsqlite3 (sqlite.bbx: link sqlite3): the AmigaOS 4 SDK's static library (3.34),
 * the system's on the host. Only programs with Extension=sqlite (and interpreters built with
 * STD_EXTS=sqlite, as the kit's is) contain it. */
#include "boing_ext.h"
#include <sqlite3.h>

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>

typedef struct bb_sqlapi {
    int (*open_v2)(const char *, sqlite3 **, int, const char *);
    int (*close)(sqlite3 *);
    int (*prepare_v2)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    int (*step)(sqlite3_stmt *);
    int (*finalize)(sqlite3_stmt *);
    int (*reset)(sqlite3_stmt *);
    int (*clear_bindings)(sqlite3_stmt *);
    int (*bind_int64)(sqlite3_stmt *, int, long long);
    int (*bind_double)(sqlite3_stmt *, int, double);
    int (*bind_text)(sqlite3_stmt *, int, const char *, int, void (*)(void *));
    int (*bind_blob)(sqlite3_stmt *, int, const void *, int, void (*)(void *));
    int (*bind_null)(sqlite3_stmt *, int);
    int (*bind_parameter_count)(sqlite3_stmt *);
    int (*column_count)(sqlite3_stmt *);
    const char *(*column_name)(sqlite3_stmt *, int);
    int (*column_type)(sqlite3_stmt *, int);
    long long (*column_int64)(sqlite3_stmt *, int);
    double (*column_double)(sqlite3_stmt *, int);
    const unsigned char *(*column_text)(sqlite3_stmt *, int);
    const void *(*column_blob)(sqlite3_stmt *, int);
    int (*column_bytes)(sqlite3_stmt *, int);
    const char *(*errmsg)(sqlite3 *);
    int (*extended_errcode)(sqlite3 *);
    int (*changes)(sqlite3 *);
    long long (*last_insert_rowid)(sqlite3 *);
    const char *(*libversion)(void);
    int (*busy_timeout)(sqlite3 *, int);
    int (*get_autocommit)(sqlite3 *);
} bb_sqlapi;

#define BB_SQ_OK 0
#define BB_SQ_ROW 100
#define BB_SQ_DONE 101
#define BB_SQ_INTEGER 1
#define BB_SQ_FLOAT 2
#define BB_SQ_TEXT 3
#define BB_SQ_BLOB 4
#define BB_SQ_NULL 5
#define BB_SQ_OPEN_READONLY 0x01
#define BB_SQ_OPEN_READWRITE 0x02
#define BB_SQ_OPEN_CREATE 0x04
#define BB_SQ_TRANSIENT ((void (*)(void *))-1)

static const bb_sqlapi table = {
    (void *)sqlite3_open_v2, (void *)sqlite3_close, (void *)sqlite3_prepare_v2, (void *)sqlite3_step,
    (void *)sqlite3_finalize, (void *)sqlite3_reset, (void *)sqlite3_clear_bindings, (void *)sqlite3_bind_int64,
    (void *)sqlite3_bind_double, (void *)sqlite3_bind_text, (void *)sqlite3_bind_blob, (void *)sqlite3_bind_null,
    (void *)sqlite3_bind_parameter_count, (void *)sqlite3_column_count, (void *)sqlite3_column_name,
    (void *)sqlite3_column_type, (void *)sqlite3_column_int64, (void *)sqlite3_column_double,
    (void *)sqlite3_column_text, (void *)sqlite3_column_blob, (void *)sqlite3_column_bytes, (void *)sqlite3_errmsg,
    (void *)sqlite3_extended_errcode, (void *)sqlite3_changes, (void *)sqlite3_last_insert_rowid,
    (void *)sqlite3_libversion, (void *)sqlite3_busy_timeout, (void *)sqlite3_get_autocommit,
};

static const bb_sqlapi *bb_sqlite_api(char *why, int whylen) { (void)why; (void)whylen; return &table; }

#define E_SQL 31601             /* SQLite reported an error */
#define E_NOSQL 31602           /* SQLite isn't available */

typedef struct {
    bb_obj hdr;
    sqlite3 *db;
    char *path;
    int timeout_ms;
} db_obj;

typedef struct {
    bb_obj hdr;
    db_obj *db;                 /* retained */
    sqlite3_stmt *st;
    int nparams;
    int busy;                   /* a recordset is reading it */
} stmt_obj;

typedef struct {
    bb_obj hdr;
    db_obj *db;                 /* retained */
    stmt_obj *owner;            /* the SqlStatement it came from (retained), or NULL: own st */
    sqlite3_stmt *st;
    int at_end;
    long row;
} rs_obj;

static const bb_class db_class, stmt_class, rs_class;

static const bb_sqlapi *api(void)
{
    char why[300];
    const bb_sqlapi *a = bb_sqlite_api(why, sizeof why);
    if (!a) bb_raise(E_NOSQL, why);
    return a;
}

static void sql_error(db_obj *d, const char *what)
{
    char m[600];
    snprintf(m, sizeof m, "%s%s%s", what ? what : "", what ? ": " : "", d->db ? api()->errmsg(d->db) : "the database isn't open");
    bb_raise(E_SQL, m);
}

static void need_open(db_obj *d)
{
    if (!d->db) bb_raise(E_SQL, "the database isn't open (Open)");
}

/* ---- values ---- */

static bb_value column_value(const bb_sqlapi *a, sqlite3_stmt *st, int i)
{
    switch (a->column_type(st, i)) {
    case BB_SQ_INTEGER: {
        long long v = a->column_int64(st, i);
        if (v >= -2147483647LL - 1 && v <= 2147483647LL) return bb_v_long((bb_long)v);
        return bb_v_double((double)v);
    }
    case BB_SQ_FLOAT:
        return bb_v_double(a->column_double(st, i));
    case BB_SQ_TEXT: {
        const unsigned char *t = a->column_text(st, i);
        return bb_v_str(bb_str_new((const char *)t, a->column_bytes(st, i)));
    }
    case BB_SQ_BLOB: {
        const void *b = a->column_blob(st, i);
        return bb_v_str(bb_str_new(b ? (const char *)b : "", a->column_bytes(st, i)));
    }
    default:
        return bb_v_null();
    }
}

static void bind_value(db_obj *d, sqlite3_stmt *st, int i, const bb_value *v)
{
    const bb_sqlapi *a = api();
    int rc;
    switch (v->type) {
    case BB_EMPTY:
    case BB_NULL:
        rc = a->bind_null(st, i);
        break;
    case BB_BOOLEAN:
        rc = a->bind_int64(st, i, v->u.b ? 1 : 0);
        break;
    case BB_BYTE:
    case BB_INTEGER:
    case BB_LONG:
        rc = a->bind_int64(st, i, (long long)bb_v_to_long(v));
        break;
    case BB_CURRENCY:
        rc = v->u.c % 10000 == 0 ? a->bind_int64(st, i, (long long)(v->u.c / 10000)) : a->bind_double(st, i, v->u.c / 10000.0);
        break;
    case BB_SINGLE:
    case BB_DOUBLE: {
        double x = bb_v_to_double(v);
        rc = a->bind_double(st, i, x);
        break;
    }
    case BB_DATE: {
        /* dates as ISO text, which SQLite's date functions understand */
        static bb_str *iso;
        bb_str *f;
        if (!iso) iso = bb_str_lit("yyyy-mm-dd hh:nn:ss", 19);
        f = bb_format(v, iso);
        rc = a->bind_text(st, i, bb_str_ptr(f), (int)bb_str_len(f), BB_SQ_TRANSIENT);
        bb_str_release(f);
        break;
    }
    case BB_STRING:
        rc = a->bind_text(st, i, bb_str_ptr(v->u.s), (int)bb_str_len(v->u.s), BB_SQ_TRANSIENT);
        break;
    default:
        bb_raise(13, "a query parameter must be a number, a String, a Date, Null or Empty");
        return;
    }
    if (rc) sql_error(d, "binding a parameter");
}

/* bind argv[from..] (or the elements of one array argument) to the statement's ? parameters */
static void bind_args(db_obj *d, sqlite3_stmt *st, int argc, bb_value *argv, int from)
{
    const bb_sqlapi *a = api();
    int want = a->bind_parameter_count(st), n = 0, i;
    bb_value t;
    a->clear_bindings(st);
    if (argc - from == 1) {
        const bb_value *v = bb_v_deref(&argv[from], &t);
        if (v->type & BB_ARRAY) {
            bb_array *arr = v->u.a;
            if (arr && arr->ndims != 1) bb_raise(5, "the parameter array must be one-dimensional");
            if (arr && arr->etype == BB_UDT) bb_raise(13, NULL);
            for (i = 0; arr && i < arr->count; i++) {
                bb_value e = bb_elem_load(arr->etype, (const char *)arr->data + (size_t)i * (size_t)arr->esize);
                if (i < want) bind_value(d, st, i + 1, &e);
                bb_v_release(&e);
                n++;
            }
            goto check;
        }
    }
    for (i = from; i < argc; i++) {
        bb_value tt;
        const bb_value *v = bb_v_deref(&argv[i], &tt);
        if (v->type == BB_ERROR && (v->flags & BB_VF_MISSING)) continue;
        if (n < want) bind_value(d, st, n + 1, v);
        n++;
    }
check:
    if (n != want) {
        char m[160];
        snprintf(m, sizeof m, "the statement has %d parameter(s) (?) but %d value(s) were given", want, n);
        bb_raise(450, m);
    }
}

/* prepare the first statement of sql; *tail = the rest */
static sqlite3_stmt *prepare(db_obj *d, const char *sql, int len, const char **tail)
{
    sqlite3_stmt *st = NULL;
    need_open(d);
    if (api()->prepare_v2(d->db, sql, len, &st, tail)) sql_error(d, NULL);
    return st;
}

typedef struct { const bb_sqlapi *a; sqlite3_stmt *st; } fin_ctx;
static void finalize_cb(void *p) { fin_ctx *f = p; if (f->st) f->a->finalize(f->st); }

/* step until done; returns the number of rows changed */
static int run_to_end(db_obj *d, sqlite3_stmt *st)
{
    const bb_sqlapi *a = api();
    int rc;
    while ((rc = a->step(st)) == BB_SQ_ROW) ;
    if (rc != BB_SQ_DONE) sql_error(d, NULL);
    return a->changes(d->db);
}

static int do_execute(db_obj *d, const bb_str *sql, int argc, bb_value *argv)
{
    const bb_sqlapi *a = api();
    const char *p = bb_str_ptr(sql), *end = p + bb_str_len(sql), *tail = NULL;
    int changes = 0, first = 1;
    while (p < end) {
        fin_ctx fc;
        bb_cleanup cl;
        fc.a = a;
        fc.st = prepare(d, p, (int)(end - p), &tail);
        if (!fc.st) {                   /* only white space or a comment left */
            p = tail && tail > p ? tail : end;
            continue;
        }
        cl.prev = bb_cleanups;
        cl.fn = finalize_cb;
        cl.ctx = &fc;
        bb_cleanups = &cl;
        /* parameters go to the (only) statement; a script of several takes none */
        if (first && argc > 1) bind_args(d, fc.st, argc, argv, 1);
        else if (a->bind_parameter_count(fc.st)) bb_raise(450, "parameters (?) are only allowed in a single statement");
        changes = run_to_end(d, fc.st);
        bb_cleanups = cl.prev;
        a->finalize(fc.st);
        first = 0;
        p = tail && tail > p ? tail : end;
        if (argc > 1 && p < end) {
            /* the rest must be empty */
            const char *q = p;
            while (q < end && (*q == ' ' || *q == '\t' || *q == '\n' || *q == '\r' || *q == ';')) q++;
            if (q < end) bb_raise(450, "parameters (?) are only allowed in a single statement");
            break;
        }
    }
    return changes;
}

static bb_obj *new_rs(db_obj *d, stmt_obj *owner, sqlite3_stmt *st)
{
    const bb_sqlapi *a = api();
    rs_obj *r = (rs_obj *)bb_obj_new(&rs_class);
    int rc;
    r->db = (db_obj *)bb_obj_retain(&d->hdr);
    r->owner = owner ? (stmt_obj *)bb_obj_retain(&owner->hdr) : NULL;
    if (owner) owner->busy = 1;
    r->st = st;
    rc = a->step(st);
    if (rc == BB_SQ_ROW) r->row = 1;
    else {
        r->at_end = 1;
        if (rc != BB_SQ_DONE) {
            bb_obj_release(&r->hdr);
            sql_error(d, NULL);
        }
    }
    return &r->hdr;
}

static bb_obj *do_query(db_obj *d, const bb_str *sql, int argc, bb_value *argv)
{
    const char *tail = NULL;
    sqlite3_stmt *st = prepare(d, bb_str_ptr(sql), (int)bb_str_len(sql), &tail);
    fin_ctx fc;
    bb_cleanup cl;
    bb_obj *r;
    if (!st) bb_raise(5, "the query is empty");
    fc.a = api();
    fc.st = st;
    cl.prev = bb_cleanups;
    cl.fn = finalize_cb;
    cl.ctx = &fc;
    bb_cleanups = &cl;
    bind_args(d, st, argc, argv, 1);
    bb_cleanups = cl.prev;
    r = new_rs(d, NULL, st);           /* the recordset owns st now (finalized with it) */
    return r;
}

/* ---- SQLite ---- */

enum { D_OPEN = 1, D_CLOSE, D_EXECUTE, D_QUERY, D_QUERYVALUE, D_QUERYALL, D_PREPARE, D_BEGIN, D_COMMIT, D_ROLLBACK,
       D_LASTINSERTID, D_CHANGES, D_ERRORCODE, D_VERSION, D_ISOPEN, D_INTRANSACTION, D_TIMEOUT, D_PATH, D_AVAILABLE };
static const struct { const char *name; int id; } members[] = {
    {"Open", D_OPEN}, {"Close", D_CLOSE}, {"Execute", D_EXECUTE}, {"Query", D_QUERY}, {"QueryValue", D_QUERYVALUE},
    {"QueryAll", D_QUERYALL}, {"Prepare", D_PREPARE}, {"BeginTransaction", D_BEGIN}, {"Commit", D_COMMIT},
    {"Rollback", D_ROLLBACK}, {"LastInsertId", D_LASTINSERTID}, {"Changes", D_CHANGES}, {"ErrorCode", D_ERRORCODE},
    {"Version", D_VERSION}, {"IsOpen", D_ISOPEN}, {"InTransaction", D_INTRANSACTION}, {"Timeout", D_TIMEOUT},
    {"Path", D_PATH}, {"Available", D_AVAILABLE},
};

static void close_db(db_obj *d)
{
    if (d->db) {
        const bb_sqlapi *a = bb_sqlite_api(NULL, 0);
        if (a && a->close(d->db) != BB_SQ_OK) {
            /* statements still open (recordsets alive): it closes when they are finalized */
        }
    }
    d->db = NULL;
}

static bb_str *arg_str(int argc, bb_value *argv, int i)
{
    bb_value t;
    if (i >= argc) bb_raise(450, NULL);
    return bb_v_to_str(bb_v_deref(&argv[i], &t));
}

static int present(int argc, bb_value *argv, int i)
{
    bb_value t;
    const bb_value *v;
    if (i >= argc) return 0;
    v = bb_v_deref(&argv[i], &t);
    return !(v->type == BB_ERROR && (v->flags & BB_VF_MISSING));
}

static void d_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    db_obj *d = (db_obj *)self;
    int set = kind & (BB_INV_LET | BB_INV_SET);
    bb_str *s;
    switch (id) {
    case D_AVAILABLE: {         /* Available: SQLite can be used here */
        char why[200];
        *ret = bb_v_bool(bb_sqlite_api(why, sizeof why) != NULL);
        return;
    }
    case D_OPEN: {
        const bb_sqlapi *a = api();
        int ro = 0, rc;
        s = arg_str(argc, argv, 0);
        if (present(argc, argv, 1)) {
            bb_value t;
            ro = bb_v_to_bool(bb_v_deref(&argv[1], &t)) != 0;
        }
        close_db(d);
        free(d->path);
        d->path = malloc((size_t)bb_str_len(s) + 1);
        memcpy(d->path, bb_str_ptr(s), (size_t)bb_str_len(s));
        d->path[bb_str_len(s)] = 0;
        bb_str_release(s);
#ifdef __amigaos4__
        {
            /* "DH1:/name" -> "DH1:name" as the other file functions do (App.Path & "/" & name for a
               program at a volume root on AmigaOS); ":memory:" has no "/" after its colon */
            char *c = strchr(d->path, ':');
            if (c && c[1] == '/' && c != d->path) memmove(c + 1, c + 2, strlen(c + 2) + 1);
        }
#endif
        rc = a->open_v2(d->path, &d->db, ro ? BB_SQ_OPEN_READONLY : BB_SQ_OPEN_READWRITE | BB_SQ_OPEN_CREATE, NULL);
        if (rc != BB_SQ_OK) {
            char m[600];
            snprintf(m, sizeof m, "can't open %.300s: %s", d->path, d->db ? a->errmsg(d->db) : "out of memory");
            if (d->db) a->close(d->db);
            d->db = NULL;
            bb_raise(E_SQL, m);
        }
        a->busy_timeout(d->db, d->timeout_ms);
        return;
    }
    case D_CLOSE:
        close_db(d);
        return;
    case D_EXECUTE: {
        int n;
        s = arg_str(argc, argv, 0);
        {
            bb_cleanup cl;
            cl.prev = bb_cleanups;
            cl.fn = (void (*)(void *))bb_str_release;
            cl.ctx = s;
            bb_cleanups = &cl;
            n = do_execute(d, s, argc, argv);
            bb_cleanups = cl.prev;
        }
        bb_str_release(s);
        *ret = bb_v_long(n);
        return;
    }
    case D_QUERY:
    case D_QUERYVALUE:
    case D_QUERYALL: {
        bb_obj *r;
        bb_cleanup cl;
        s = arg_str(argc, argv, 0);
        cl.prev = bb_cleanups;
        cl.fn = (void (*)(void *))bb_str_release;
        cl.ctx = s;
        bb_cleanups = &cl;
        r = do_query(d, s, argc, argv);
        bb_cleanups = cl.prev;
        bb_str_release(s);
        if (id == D_QUERY) {
            *ret = bb_v_obj(r);
            return;
        }
        {
            rs_obj *rs = (rs_obj *)r;
            const bb_sqlapi *a = api();
            if (id == D_QUERYVALUE) {
                *ret = rs->at_end ? bb_v_empty() : column_value(a, rs->st, 0);
            } else {
                /* every row as a 2-D Variant array (row, column), both from 0; no rows: Empty */
                bb_value **rows = NULL;
                int nrows = 0, ncols = a->column_count(rs->st), i, j;
                while (!rs->at_end) {
                    int rc;
                    rows = realloc(rows, sizeof(bb_value *) * (size_t)(nrows + 1));
                    rows[nrows] = malloc(sizeof(bb_value) * (size_t)(ncols ? ncols : 1));
                    for (j = 0; j < ncols; j++) rows[nrows][j] = column_value(a, rs->st, j);
                    nrows++;
                    rc = a->step(rs->st);
                    if (rc != BB_SQ_ROW) {
                        rs->at_end = 1;
                        if (rc != BB_SQ_DONE) {
                            for (i = 0; i < nrows; i++) {
                                for (j = 0; j < ncols; j++) bb_v_release(&rows[i][j]);
                                free(rows[i]);
                            }
                            free(rows);
                            bb_obj_release(r);
                            sql_error(d, NULL);
                        }
                    }
                }
                if (!nrows) *ret = bb_v_empty();
                else {
                    int32_t lb[2] = {0, 0}, ub[2];
                    bb_array *arr;
                    ub[0] = nrows - 1;
                    ub[1] = ncols - 1;
                    arr = bb_arr_new(BB_VARIANT, NULL, 2, lb, ub);
                    for (i = 0; i < nrows; i++) {
                        for (j = 0; j < ncols; j++) *(bb_value *)bb_arr_elem2(arr, i, j) = rows[i][j];
                        free(rows[i]);
                    }
                    free(rows);
                    *ret = bb_v_arr(arr);
                }
            }
            bb_obj_release(r);
        }
        return;
    }
    case D_PREPARE: {
        stmt_obj *so;
        const char *tail = NULL;
        sqlite3_stmt *st;
        s = arg_str(argc, argv, 0);
        st = prepare(d, bb_str_ptr(s), (int)bb_str_len(s), &tail);
        bb_str_release(s);
        if (!st) bb_raise(5, "the statement is empty");
        so = (stmt_obj *)bb_obj_new(&stmt_class);
        so->db = (db_obj *)bb_obj_retain(&d->hdr);
        so->st = st;
        so->nparams = api()->bind_parameter_count(st);
        *ret = bb_v_obj(&so->hdr);
        return;
    }
    case D_BEGIN:
    case D_COMMIT:
    case D_ROLLBACK: {
        const char *sql = id == D_BEGIN ? "BEGIN" : id == D_COMMIT ? "COMMIT" : "ROLLBACK";
        bb_str *q = bb_str_from_c(sql);
        bb_cleanup cl;
        cl.prev = bb_cleanups;
        cl.fn = (void (*)(void *))bb_str_release;
        cl.ctx = q;
        bb_cleanups = &cl;
        do_execute(d, q, 1, argv);
        bb_cleanups = cl.prev;
        bb_str_release(q);
        return;
    }
    case D_LASTINSERTID: {
        long long v;
        need_open(d);
        v = api()->last_insert_rowid(d->db);
        *ret = v >= -2147483647LL - 1 && v <= 2147483647LL ? bb_v_long((bb_long)v) : bb_v_double((double)v);
        return;
    }
    case D_CHANGES:
        need_open(d);
        *ret = bb_v_long(api()->changes(d->db));
        return;
    case D_ERRORCODE:
        *ret = bb_v_long(d->db ? api()->extended_errcode(d->db) : 0);
        return;
    case D_VERSION:
        *ret = bb_v_str(bb_str_from_c(api()->libversion()));
        return;
    case D_ISOPEN:
        *ret = bb_v_bool(d->db != NULL);
        return;
    case D_INTRANSACTION:
        *ret = bb_v_bool(d->db && !api()->get_autocommit(d->db));
        return;
    case D_TIMEOUT:
        if (set) {
            bb_value t;
            int32_t v = (int32_t)bb_v_to_long(bb_v_deref(&argv[argc - 1], &t));
            if (v < 0) bb_raise(380, NULL);
            d->timeout_ms = (int)v;
            if (d->db) api()->busy_timeout(d->db, v);
        } else
            *ret = bb_v_long(d->timeout_ms);
        return;
    case D_PATH:
        *ret = bb_v_str(bb_str_from_c(d->path ? d->path : ""));
        return;
    }
    bb_raise(438, NULL);
}

static int32_t tab_find(const void *tab, size_t n, size_t stride, const char *name)
{
    size_t i;
    for (i = 0; i < n; i++) {
        const struct { const char *name; int id; } *e = (const void *)((const char *)tab + i * stride);
        if (!strcasecmp(e->name, name)) return e->id;
    }
    return BB_NOMEMBER;
}

static int32_t d_find(const bb_class *cls, const char *name)
{
    (void)cls;
    if (!name || !*name) return BB_NOMEMBER;
    return tab_find(members, sizeof members / sizeof members[0], sizeof members[0], name);
}

static void d_terminate(bb_obj *self)
{
    db_obj *d = (db_obj *)self;
    close_db(d);
    free(d->path);
}

static const bb_class db_class = {
    "SQLite", sizeof(db_obj), d_find, d_invoke, d_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};
static bb_obj *bb_sqlite_new(void)
{
    db_obj *d = (db_obj *)bb_obj_new(&db_class);
    d->timeout_ms = 5000;
    return &d->hdr;
}

/* ---- SqlStatement ---- */

enum { S_EXECUTE = 1, S_QUERY, S_CLOSE, S_PARAMCOUNT };
static const struct { const char *name; int id; } stmt_tab[] = {
    {"Execute", S_EXECUTE}, {"Query", S_QUERY}, {"Close", S_CLOSE}, {"ParameterCount", S_PARAMCOUNT},
};

static void s_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    stmt_obj *so = (stmt_obj *)self;
    const bb_sqlapi *a;
    (void)kind;
    if (id == S_CLOSE) {
        if (so->st) api()->finalize(so->st);
        so->st = NULL;
        return;
    }
    if (id == S_PARAMCOUNT) {
        *ret = bb_v_long(so->nparams);
        return;
    }
    if (!so->st) bb_raise(E_SQL, "the statement is closed");
    if (so->busy) bb_raise(E_SQL, "the statement is still being read by a recordset (close it first)");
    a = api();
    a->reset(so->st);
    /* all the arguments are parameters */
    bind_args(so->db, so->st, argc, argv, 0);
    if (id == S_EXECUTE) {
        int n = run_to_end(so->db, so->st);
        a->reset(so->st);
        *ret = bb_v_long(n);
        return;
    }
    if (id == S_QUERY) {
        *ret = bb_v_obj(new_rs(so->db, so, so->st));
        return;
    }
    bb_raise(438, NULL);
}

static int32_t s_find(const bb_class *cls, const char *name)
{
    (void)cls;
    if (!name || !*name) return BB_NOMEMBER;
    return tab_find(stmt_tab, sizeof stmt_tab / sizeof stmt_tab[0], sizeof stmt_tab[0], name);
}

static void s_terminate(bb_obj *self)
{
    stmt_obj *so = (stmt_obj *)self;
    if (so->st) {
        const bb_sqlapi *a = bb_sqlite_api(NULL, 0);
        if (a) a->finalize(so->st);
    }
    bb_obj_release(&so->db->hdr);
}

static const bb_class stmt_class = {
    "SqlStatement", sizeof(stmt_obj), s_find, s_invoke, s_terminate, NULL, NULL, 0, NULL, 0, NULL, NULL
};

/* ---- SqlRecordset ---- */

enum { R_FIELD = 1, R_MOVENEXT, R_ATEND, R_EOF, R_FIELDCOUNT, R_FIELDNAME, R_FIELDS, R_CLOSE, R_ROW };
static const struct { const char *name; int id; } rs_tab[] = {
    {"Field", R_FIELD}, {"MoveNext", R_MOVENEXT}, {"AtEnd", R_ATEND}, {"EOF", R_EOF}, {"FieldCount", R_FIELDCOUNT},
    {"FieldName", R_FIELDNAME}, {"Fields", R_FIELDS}, {"Close", R_CLOSE}, {"RowNumber", R_ROW},
};

static void rs_close(rs_obj *r)
{
    if (!r->st) return;
    if (r->owner) {
        const bb_sqlapi *a = bb_sqlite_api(NULL, 0);
        if (a) a->reset(r->st);
        r->owner->busy = 0;
        bb_obj_release(&r->owner->hdr);
        r->owner = NULL;
    } else {
        const bb_sqlapi *a = bb_sqlite_api(NULL, 0);
        if (a) a->finalize(r->st);
    }
    r->st = NULL;
    r->at_end = 1;
}

static int col_index(rs_obj *r, int argc, bb_value *argv)
{
    const bb_sqlapi *a = api();
    bb_value t;
    const bb_value *v;
    int n, i;
    if (argc < 1) bb_raise(450, NULL);
    if (!r->st) bb_raise(E_SQL, "the recordset is closed");
    n = a->column_count(r->st);
    v = bb_v_deref(&argv[0], &t);
    if (v->type == BB_STRING) {
        for (i = 0; i < n; i++) {
            const char *cn = a->column_name(r->st, i);
            if (cn && (int32_t)strlen(cn) == bb_str_len(v->u.s) && !strncasecmp(cn, bb_str_ptr(v->u.s), (size_t)bb_str_len(v->u.s)))
                return i;
        }
        {
            char m[300];
            snprintf(m, sizeof m, "no column named %.200s", bb_str_ptr(v->u.s));
            bb_raise(5, m);
        }
    }
    i = (int)bb_v_to_long(v);
    if (i < 0 || i >= n) bb_raise(9, NULL);
    return i;
}

static void r_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    rs_obj *r = (rs_obj *)self;
    const bb_sqlapi *a;
    if (kind & (BB_INV_LET | BB_INV_SET)) bb_raise(383, NULL);
    switch (id) {
    case R_ATEND:
    case R_EOF:
        *ret = bb_v_bool(r->at_end);
        return;
    case R_ROW:
        *ret = bb_v_long((bb_long)(r->at_end ? 0 : r->row));
        return;
    case R_CLOSE:
        rs_close(r);
        return;
    case R_MOVENEXT: {
        int rc;
        if (r->at_end || !r->st) bb_raise(E_SQL, "MoveNext past the last row (check AtEnd)");
        a = api();
        rc = a->step(r->st);
        if (rc == BB_SQ_ROW) r->row++;
        else {
            r->at_end = 1;
            if (rc != BB_SQ_DONE) sql_error(r->db, NULL);
        }
        return;
    }
    case R_FIELDCOUNT:
        *ret = bb_v_long(r->st ? api()->column_count(r->st) : 0);
        return;
    case R_FIELDNAME: {
        int i = col_index(r, argc, argv);
        *ret = bb_v_str(bb_str_from_c(api()->column_name(r->st, i)));
        return;
    }
    case R_FIELD: {
        int i = col_index(r, argc, argv);
        if (r->at_end) bb_raise(E_SQL, "no current row (AtEnd)");
        *ret = column_value(api(), r->st, i);
        return;
    }
    case R_FIELDS: {
        int n, i;
        bb_array *arr;
        if (!r->st || r->at_end) bb_raise(E_SQL, "no current row (AtEnd)");
        a = api();
        n = a->column_count(r->st);
        arr = bb_arr_new1(BB_VARIANT, 0, n - 1);
        for (i = 0; i < n; i++) *(bb_value *)bb_arr_elem1(arr, i) = column_value(a, r->st, i);
        *ret = bb_v_arr(arr);
        return;
    }
    }
    bb_raise(438, NULL);
}

static int32_t r_find(const bb_class *cls, const char *name)
{
    (void)cls;
    if (!name || !*name) return R_FIELD;
    return tab_find(rs_tab, sizeof rs_tab / sizeof rs_tab[0], sizeof rs_tab[0], name);
}

static void r_terminate(bb_obj *self)
{
    rs_obj *r = (rs_obj *)self;
    rs_close(r);
    bb_obj_release(&r->db->hdr);
}

/* For Each row In db.Query(...): each row's Fields array */
static int r_iterate(bb_obj *self, bb_value *state, bb_value *out)
{
    rs_obj *r = (rs_obj *)self;
    const bb_sqlapi *a;
    int n, i, rc;
    bb_array *arr;
    if (state->type == BB_LONG && !r->at_end && r->st) {   /* not the first call: step */
        a = api();
        rc = a->step(r->st);
        if (rc == BB_SQ_ROW) r->row++;
        else {
            r->at_end = 1;
            if (rc != BB_SQ_DONE) sql_error(r->db, NULL);
        }
    }
    *state = bb_v_long(1);
    if (r->at_end || !r->st) return 0;
    a = api();
    n = a->column_count(r->st);
    arr = bb_arr_new1(BB_VARIANT, 0, n - 1);
    for (i = 0; i < n; i++) *(bb_value *)bb_arr_elem1(arr, i) = column_value(a, r->st, i);
    *out = bb_v_arr(arr);
    return 1;
}

static const bb_class rs_class = {
    "SqlRecordset", sizeof(rs_obj), r_find, r_invoke, r_terminate, r_iterate, NULL, 0, NULL, 0, NULL, NULL
};

BB_EXTENSION(sqlite)
{
    bb_register_class("SQLite", &db_class, bb_sqlite_new);
    bb_register_class("SqlRecordset", &rs_class, NULL);
    bb_register_class("SqlStatement", &stmt_class, NULL);
}
