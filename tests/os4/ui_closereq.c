/* ui_closereq TITLE... - for tools/os4-ui-tests.sh: a requester a stopped test left open (its
 * window has one of these titles) is activated and gets Esc, injected only while it is the
 * active window (the guest may be shared). Prints what it did. */
#define MAIN_TITLE ""
#include "test_inject.h"

int main(int argc, char **argv)
{
    if (!inject_open()) return 20;
    for (int i = 1; i < argc; i++)
        for (int k = 0; k < 3; k++) {
            if (!find_window(argv[i])) break;
            if (!make_active(argv[i])) { printf("%s: can't make it active\n", argv[i]); break; }
            struct InputEvent ie;
            memset(&ie, 0, sizeof ie);
            ie.ie_Class = IECLASS_RAWKEY;
            ie.ie_Code = 0x45;       /* Esc */
            inject(&ie);
            ie.ie_Code = 0x45 | IECODE_UP_PREFIX;
            inject(&ie);
            printf("%s: Esc\n", argv[i]);
            IDOS->Delay(25);
        }
    inject_close();
    return 0;
}
