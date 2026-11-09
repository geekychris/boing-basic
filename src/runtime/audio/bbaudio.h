/* bbaudio.h - Boing BASIC's sound core: a ProTracker player and a sound-effect mixer
 * (docs/audio.md). Portable C, no OS calls: the platform layer (os4/audio_os4.c,
 * posix/audio_posix.c) only moves the mixed PCM to a device.
 *
 * The player is derived from amiga3d's modplay.c (MIT, Copyright (c) 2026 Chris Collins
 * <chris@hitorro.com>, examples/amiga3d in amiga_mcp), extended to 4/6/8 channels, the full
 * ProTracker effect set, editable song data, live notes and scope/VU data.
 *
 * All arithmetic is integer, so a song renders to the same samples on every platform.
 * Nothing here locks: the caller (audio.c) holds the platform's mutex around every call,
 * and the platform's mixer task holds it around bba_mix().
 */
#ifndef BB_AUDIO_CORE_H
#define BB_AUDIO_CORE_H

#include <stdint.h>

#define BBA_MAXCH     8         /* music channels */
#define BBA_VOICES    8         /* effect voices */
#define BBA_ROWS      64
#define BBA_MAXPAT    128
#define BBA_SCOPE     1024      /* scope ring per channel (power of 2) */
#define BBA_NOTES     36        /* notes 1..36 = C-1 .. B-3 */

typedef struct {
    char name[23];
    int8_t *data;               /* malloc'd, owned */
    uint32_t len, loop_start, loop_len;   /* bytes */
    int vol, finetune;          /* 0..64, 0..15 (8..15 = -8..-1) */
} bba_sample;

typedef struct {
    char name[21];
    int nch;                    /* 4, 6 or 8 */
    int song_len, restart;
    int restart_byte;           /* byte 951 as loaded (kept on save) */
    int speed, bpm;             /* what PlayMusic starts with (6, 125) */
    uint8_t order[128];
    int npat;                   /* patterns stored */
    uint8_t *pat;               /* npat * 64 rows * nch cells * 4 bytes, ProTracker cell format */
    bba_sample smp[31];
} bba_song;

typedef struct {
    int smp;                    /* 1..31, 0 = none (index into the song: data may be replaced) */
    uint32_t pos, frac, step;   /* step: 16.16 sample positions per output frame */
    int active, finetune;
    int period, base, target;
    int volume, outvol;         /* volume; after tremolo */
    int pan;                    /* 0..255, -1 = Amiga default for the channel */
    int eff, prm, porta, vib_prm, vib_pos, vib_wave, trem_prm, trem_pos, trem_wave, offset;
    int delay_period, delay_smp;
    int loop_row, loop_count;
    int note;                   /* last note triggered (1..36) */
    int muted;
    int peak, vu;               /* level */
    int8_t scope[BBA_SCOPE];
    uint32_t scope_pos;
} bba_chan;

typedef struct {
    bba_song *song;
    int playing, paused, loop;
    int speed, bpm, tick, row, pos, pat_delay, delay_rows, jump_pos, break_row;
    int tick_left, rate;
    int ended;                  /* times the song reached its end */
    int pat_mode;               /* >= 0: PlayPattern loops this pattern */
    bba_chan ch[BBA_MAXCH];
} bba_player;

typedef struct {
    int bits;                   /* 8 or 16 */
    void *data;                 /* int8_t* or int16_t*, owned */
    uint32_t len;               /* samples */
    int rate, loop;
    uint32_t loop_start, loop_len;
} bba_sound;

typedef struct {
    bba_sound *snd;             /* NULL = free */
    uint32_t id, pos, frac, step;
    int vol, pan, rate, loop, pri;
} bba_voice;

/* ---- songs (bbmod.c) ---- */
bba_song *bba_song_new(int nch);
/* parse a module file image; NULL if it isn't one. The data is copied. */
bba_song *bba_song_load(const uint8_t *d, long len);
void bba_song_free(bba_song *s);
/* serialise as a ProTracker module (malloc'd), *len = size */
uint8_t *bba_song_save(const bba_song *s, long *len);
int bba_song_add_pattern(bba_song *s);           /* new pattern's number, -1 = full / no memory */
uint8_t *bba_cell(bba_song *s, int pat, int row, int ch);
int bba_sample_resize(bba_sample *sm, uint32_t len);   /* 0 = no memory */

int bba_note_period(int note, int finetune);     /* note 1..36 -> period, 0 for 0 */
int bba_period_note(int period);                 /* nearest note, 0 for 0 */

/* ---- the player (bbmod.c) ---- */
void bba_player_init(bba_player *p, int rate);
void bba_play(bba_player *p, bba_song *s, int pos, int row);
void bba_play_pattern(bba_player *p, bba_song *s, int pat, int row);
void bba_stop(bba_player *p);
void bba_jump(bba_player *p, int pos, int row);
/* a cell (4 bytes, ProTracker format) on channel ch now */
void bba_play_cell(bba_player *p, int ch, const uint8_t *cell);
void bba_play_row(bba_player *p, int pat, int row);
void bba_note_off(bba_player *p, int ch);
void bba_song_gone(bba_player *p, bba_song *s);  /* a song is being freed */
void bba_sample_changed(bba_player *p, int smp); /* sample data replaced: cut its channels */
/* advance the player by frames and add the music into mix[] (stereo int32, frames * 2),
 * gains applied; used by bba_mix and RenderToWav */
void bba_player_render(bba_player *p, int32_t *mix, int frames);

/* ---- the mixer (bbmix.c) ---- */
typedef struct {
    bba_player music;
    bba_voice voice[BBA_VOICES];
    uint32_t next_voice_id;
    int rate, master, music_vol, sound_vol, music_on, sound_on;
    uint32_t hash;              /* FNV-1a over every frame mixed */
    int16_t scope_mix[BBA_SCOPE * 2];
    uint32_t scope_mix_pos;
    int32_t *mixbuf;
    int mixcap;
} bba_mixer;

void bba_mixer_init(bba_mixer *m, int rate);
void bba_mixer_free(bba_mixer *m);
/* mix frames of interleaved stereo signed 16-bit into out */
void bba_mix(bba_mixer *m, int16_t *out, int frames);
/* start a sound on a free voice; returns the voice id (0 = none free) */
uint32_t bba_voice_start(bba_mixer *m, bba_sound *s, int vol, int pan, int rate, int loop, int pri);
bba_voice *bba_voice_find(bba_mixer *m, uint32_t id);
void bba_voice_set_rate(bba_mixer *m, bba_voice *v, int rate);
void bba_sound_gone(bba_mixer *m, bba_sound *s);

/* ---- sound files and synthesis (bbsound.c) ---- */
/* 8SVX, WAV or (fmt != NULL) raw "s8" "u8" "s16le" "s16be"; NULL if not a sound,
 * *why = 0 or an error number */
bba_sound *bba_sound_parse(const uint8_t *d, long len, const char *fmt, int rate);
bba_sound *bba_sound_new(uint32_t len, int rate, int bits);
void bba_sound_free(bba_sound *s);
int bba_sound_get(const bba_sound *s, uint32_t i);
void bba_sound_set(bba_sound *s, uint32_t i, int v);
bba_sound *bba_synth_tone(int rate, int ms, int f0, int f1, int vol, int wave);
bba_sound *bba_synth_noise(int rate, int ms, int vol, int smooth, int attack_ms);

/* WAV writer helpers */
void bba_wav_header(uint8_t h[44], int rate, uint32_t frames);

#endif
