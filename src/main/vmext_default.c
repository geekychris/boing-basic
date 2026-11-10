/* vmext_default.c - the standard interpreter links no extensions. `boing vm` builds one that
   does: its glue file defines bb_vm_ext_init() (calling the extensions' inits and registering the
   Lib "C" functions), so this archive member is not linked (docs/extensions.md). */
void bb_vm_ext_init(void);
void bb_vm_ext_init(void) {}
