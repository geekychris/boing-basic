/* audio_posix.c - the Audio object's platform layer on macOS/Linux: no sound device (yet).
 * audio.c then runs its silent clock-driven mixer ("null"), or the wav/manual devices. */
#include "../audio.h"

int audio_plat_open(int rate) { (void)rate; return 0; }
void audio_plat_close(void) {}
void audio_plat_lock(void) {}
void audio_plat_unlock(void) {}
int audio_plat_cpu_load(void) { return -1; }
const char *audio_plat_name(void) { return "null"; }
