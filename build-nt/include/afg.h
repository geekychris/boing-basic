/* The .afg GUI file (AmiForge's designer format, AmiForge src/ide/GuiModel.h), parsed into a
 * tree. Portable C: the host tests parse .afg files too.
 *
 *   # AmiForge GUI
 *   window name=main title="My Program" width=320 height=160
 *   vlayout id=root
 *     hlayout title="Options" frame=group
 *       checkbox id=fast text="_Fast"
 *     button id=ok text="_OK" weight=0
 *
 * One object per line: its kind and key=value properties (values with spaces in "quotes", with
 * \" \\ and \n escapes), two spaces of indentation per level. The first object is the window,
 * the second the root layout. Boing BASIC adds the kind `timer` (no gadget, see
 * docs/forms-events.md). */
#ifndef BB_AFG_H
#define BB_AFG_H

typedef enum {
    AFG_WINDOW, AFG_VLAYOUT, AFG_HLAYOUT, AFG_BUTTON, AFG_STRING, AFG_INTEGER, AFG_CHECKBOX,
    AFG_CHOOSER, AFG_RADIO, AFG_SLIDER, AFG_SCROLLER, AFG_LISTBROWSER, AFG_LABEL, AFG_SPACE,
    AFG_FUELGAUGE, AFG_GETFILE, AFG_TEXTEDITOR, AFG_TIMER, AFG_NUM_KINDS
} afg_kind;

typedef struct afg_prop {
    char *key, *value;
} afg_prop;

typedef struct afg_node {
    afg_kind kind;
    int line;                       /* in the file */
    int nprops;
    afg_prop *props;
    int nchildren;
    struct afg_node **children;
    struct afg_node *parent;
} afg_node;

const char *afg_kind_name(afg_kind k);      /* "button" */
int afg_kind_by_name(const char *name);     /* -1 if unknown */
int afg_is_container(afg_kind k);           /* layouts (and the window) */
int afg_is_gadget(afg_kind k);              /* has a GA_ID and reports events */

/* Parse text; returns the window node (its one child is the root layout), or NULL with a
 * message "line N: ..." in err. */
afg_node *afg_parse(const char *text, char *err, int errlen);
void afg_free(afg_node *n);

/* A property: the value in the file, or the kind's default (as AmiForge's designer), or "". */
const char *afg_get(const afg_node *n, const char *key);
int afg_get_int(const afg_node *n, const char *key);
int afg_get_bool(const afg_node *n, const char *key);
int afg_has(const afg_node *n, const char *key);     /* set and not empty */

/* Depth-first walk, calling fn for every node below (and including) n. */
void afg_walk(afg_node *n, void (*fn)(afg_node *, void *), void *ud);

/* "a|b|c" -> count and items (malloc'd array of malloc'd strings; free with afg_free_items). */
int afg_split_items(const char *s, char ***items);
void afg_free_items(char **items, int n);

#endif
