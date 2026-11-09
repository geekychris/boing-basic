/* audio.h - the Audio object (docs/audio.md) and its platform layer.
 *
 * The player and mixer are portable C in audio/ (bbaudio.h); audio.c is the BASIC object.
 * The platform layer (os4/audio_os4.c, posix/audio_posix.c) runs an output device that
 * calls bb_audio_mix() from its own task, and provides the lock that audio.c holds around
 * every touch of the mixer state.
 */
#ifndef BB_AUDIO_H
#define BB_AUDIO_H

#include <stdint.h>
#include "boing.h"

/* CreateObject("Boing.Audio"): a handle to the one mixer (owned reference) */
bb_obj *bb_audio_new(void);

/* For the platform's mixer task: mix frames of signed 16-bit stereo (with the lock held). */
void bb_audio_mix(int16_t *out, int frames);

/* ---- platform layer ---- */
/* Start the output device at rate Hz; it calls bb_audio_mix (taking the lock) until
 * audio_plat_close. Returns 1 if a device runs, 0 if there is none (then audio.c falls back
 * to a silent clock-driven mixer). */
int audio_plat_open(int rate);
void audio_plat_close(void);
void audio_plat_lock(void);
void audio_plat_unlock(void);
/* the mixer task's CPU use in 1/10 percent over the last second, -1 if unknown */
int audio_plat_cpu_load(void);
const char *audio_plat_name(void);      /* e.g. "ahi" */

#endif
