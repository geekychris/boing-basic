/* audio.c - the Audio object: music and sound effects from BASIC (docs/audio.md).
 *
 * Every Audio object is a handle to one mixer (audio/bbaudio.h). Each call takes the
 * platform's lock, because on AmigaOS 4 a task of its own mixes the next chunk for AHI at
 * any time. An error raised inside a call releases the lock through a bb_cleanup.
 */
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <ctype.h>
#include "audio.h"
#include "platform.h"
#include "audio/bbaudio.h"
#include "fpath.h"

typedef struct { bb_obj hdr; } bb_audio;

enum { DEV_CLOSED, DEV_PLAT, DEV_NULL, DEV_MANUAL, DEV_WAV };

static bba_mixer mx;
static int dev = DEV_CLOSED, have_plat_dev;
static bba_song **songs;
static int nsongs, edit_song;
static bba_sound **sounds;
static int nsounds;
static FILE *wavf;
static uint32_t wav_frames;
static double null_t0;
static uint64_t null_frames;
static int16_t *scratch;
#define SFX_IDS 64
#define FX_RATE (3546895 / 300)         /* amiga3d's A3_FX_PERIOD 300: 11.8 kHz */
static int sfx_snd[SFX_IDS], sfx_vol[SFX_IDS], sfx_pri[SFX_IDS];
static uint32_t a3_rng = 4242;          /* a3d_sound.c's noise generator, one sequence per program */
static int exit_hooked;

/* ---------------------------------------------------------------- arguments */

static int missing(int argc, const bb_value *argv, int i)
{
    if (i >= argc) return 1;
    return argv[i].type == BB_ERROR && (argv[i].flags & BB_VF_MISSING);
}

static int32_t to_l(const bb_value *v)
{
    bb_value t;
    switch (v->type) {
    case BB_LONG: return v->u.l;
    case BB_INTEGER: return v->u.i;
    case BB_BOOLEAN: return v->u.b;
    case BB_BYTE: return v->u.by;
    case BB_REF | BB_LONG: return *(bb_long *)v->u.p;
    case BB_REF | BB_INTEGER: return *(bb_int *)v->u.p;
    default:
        if (v->type & BB_REF) v = bb_v_deref(v, &t);
        return bb_v_to_long(v);
    }
}

static int32_t argl(int argc, const bb_value *argv, int i)
{
    if (missing(argc, argv, i)) bb_raise(449, NULL);
    return to_l(&argv[i]);
}

static int32_t argl_opt(int argc, const bb_value *argv, int i, int32_t def)
{
    return missing(argc, argv, i) ? def : to_l(&argv[i]);
}

static int argb(int argc, const bb_value *argv, int i)
{
    bb_value t;
    if (missing(argc, argv, i)) bb_raise(449, NULL);
    return bb_v_to_bool(bb_v_deref(&argv[i], &t)) != 0;
}

/* a string argument copied into buf (size n) */
static const char *argstr(int argc, const bb_value *argv, int i, char *buf, size_t n)
{
    bb_value t;
    const bb_value *v;
    if (missing(argc, argv, i)) bb_raise(449, NULL);
    v = bb_v_deref(&argv[i], &t);
    if (v->type == BB_STRING) {
        size_t l = (size_t)bb_str_len(v->u.s);
        if (l >= n) l = n - 1;
        memcpy(buf, bb_str_ptr(v->u.s), l);
        buf[l] = 0;
    } else {
        bb_str *s = bb_v_to_str(v);
        size_t l = (size_t)bb_str_len(s);
        if (l >= n) l = n - 1;
        memcpy(buf, bb_str_ptr(s), l);
        buf[l] = 0;
        bb_str_release(s);
    }
    return buf;
}

static bb_array *arg_array(int argc, const bb_value *argv, int i)
{
    const bb_value *v;
    if (missing(argc, argv, i)) bb_raise(449, NULL);
    v = &argv[i];
    if ((v->type & BB_REF) && (v->type & BB_ARRAY)) return *(bb_array **)v->u.p;
    if (v->type & BB_REF) {
        const bb_value *pv = (const bb_value *)v->u.p;
        if (pv->type & BB_ARRAY) return pv->u.a;
    } else if (v->type & BB_ARRAY) return v->u.a;
    bb_raise(13, NULL);
    return NULL;
}

/* element k (storage order) of a numeric array as a Long */
static int32_t elem_l(const bb_array *a, int32_t k)
{
    const char *p = (const char *)a->data + (size_t)k * (size_t)a->esize;
    switch (a->etype) {
    case BB_BYTE: return *(const bb_byte *)p;
    case BB_INTEGER: return *(const bb_int *)p;
    case BB_LONG: return *(const bb_long *)p;
    case BB_BOOLEAN: return *(const bb_bool *)p;
    case BB_VARIANT: return to_l((const bb_value *)p);
    default: { bb_value t = bb_elem_load(a->etype, p); int32_t r = bb_v_to_long(&t); bb_v_release(&t); return r; }
    }
}

static void range(int32_t v, int32_t lo, int32_t hi, int err)
{
    if (v < lo || v > hi) bb_raise(err, NULL);
}

static uint8_t *read_file(const char *path, long *len)
{
    FILE *f = fopen(path, "rb");
    uint8_t *d;
    long n;
    if (!f) bb_raise(53, NULL);
    fseek(f, 0, SEEK_END);
    n = ftell(f);
    fseek(f, 0, SEEK_SET);
    d = (uint8_t *)malloc(n > 0 ? (size_t)n : 1);
    if (!d) { fclose(f); bb_raise(7, NULL); }
    if (n > 0 && fread(d, 1, (size_t)n, f) != (size_t)n) { fclose(f); free(d); bb_raise(57, NULL); }
    fclose(f);
    *len = n;
    return d;
}

/* ---------------------------------------------------------------- songs and sounds */

static bba_song *song(int32_t n)
{
    if (n < 1 || n > nsongs || !songs[n - 1]) bb_raise(9, NULL);
    return songs[n - 1];
}

static int32_t add_song(bba_song *s)
{
    int i;
    bba_song **ns;
    if (!s) bb_raise(7, NULL);
    for (i = 0; i < nsongs; i++) if (!songs[i]) { songs[i] = s; return edit_song = i + 1; }
    ns = (bba_song **)realloc(songs, sizeof *ns * (size_t)(nsongs + 1));
    if (!ns) { bba_song_free(s); bb_raise(7, NULL); }
    songs = ns;
    songs[nsongs++] = s;
    return edit_song = nsongs;
}

static int32_t song_num(const bba_song *s)
{
    int i;
    for (i = 0; i < nsongs; i++) if (songs[i] == s) return i + 1;
    return 0;
}

static bba_sound *sound(int32_t n)
{
    if (n < 1 || n > nsounds || !sounds[n - 1]) bb_raise(9, NULL);
    return sounds[n - 1];
}

static int32_t add_sound(bba_sound *s)
{
    int i;
    bba_sound **ns;
    if (!s) bb_raise(7, NULL);
    for (i = 0; i < nsounds; i++) if (!sounds[i]) { sounds[i] = s; return i + 1; }
    ns = (bba_sound **)realloc(sounds, sizeof *ns * (size_t)(nsounds + 1));
    if (!ns) { bba_sound_free(s); bb_raise(7, NULL); }
    sounds = ns;
    sounds[nsounds++] = s;
    return nsounds;
}

static bba_sample *sample(bba_song *s, int32_t n)
{
    range(n, 1, 31, 9);
    return &s->smp[n - 1];
}

static uint8_t *cell_arg(int argc, const bb_value *argv, bba_song **ps)
{
    bba_song *s = song(argl(argc, argv, 0));
    int32_t pat = argl(argc, argv, 1), row = argl(argc, argv, 2), ch = argl(argc, argv, 3);
    range(pat, 0, s->npat - 1, 9);
    range(row, 0, BBA_ROWS - 1, 9);
    range(ch, 0, s->nch - 1, 9);
    if (ps) *ps = s;
    return bba_cell(s, pat, row, ch);
}

static void set_cell(uint8_t *c, int note, int period, int smp, int eff, int prm)
{
    if (note >= 0) period = note ? bba_note_period(note, 0) : 0;
    c[0] = (uint8_t)((smp & 0xF0) | ((period >> 8) & 0x0F));
    c[1] = (uint8_t)period;
    c[2] = (uint8_t)(((smp & 15) << 4) | (eff & 15));
    c[3] = (uint8_t)prm;
}

static int cell_period(const uint8_t *c) { return ((c[0] & 0x0F) << 8) | c[1]; }
static int cell_sample(const uint8_t *c) { return (c[0] & 0xF0) | (c[2] >> 4); }

static void sound_into_sample(bba_sample *sm, const bba_sound *snd)
{
    uint32_t i, n = snd->len > 131070 ? 131070 : snd->len;
    if (!bba_sample_resize(sm, (n + 1) & ~1u)) bb_raise(7, NULL);
    for (i = 0; i < n; i++)
        sm->data[i] = (int8_t)(snd->bits == 8 ? ((const int8_t *)snd->data)[i] : ((const int16_t *)snd->data)[i] >> 8);
    sm->loop_start = sm->loop_len = 0;
    if (snd->loop) {
        uint32_t ls = snd->loop_len ? snd->loop_start : 0, ll = snd->loop_len ? snd->loop_len : n;
        if (ls < sm->len) {
            sm->loop_start = ls & ~1u;
            sm->loop_len = (ll & ~1u) > sm->len - sm->loop_start ? sm->len - sm->loop_start : ll & ~1u;
        }
    }
    if (!sm->vol) sm->vol = 64;
}

static const char *note_names[12] = { "C-", "C#", "D-", "D#", "E-", "F-", "F#", "G-", "G#", "A-", "A#", "B-" };

static int note_from_name(const char *s)
{
    int i;
    if (strlen(s) < 3) return 0;
    for (i = 0; i < 12; i++)
        if (toupper((unsigned char)s[0]) == note_names[i][0] &&
            (s[1] == note_names[i][1] || (s[1] == ' ' && note_names[i][1] == '-'))) {
            int oct = s[2] - '0';
            if (oct < 1 || oct > 3) return 0;
            return (oct - 1) * 12 + i + 1;
        }
    return 0;
}

/* ---------------------------------------------------------------- the device */

void bb_audio_mix(int16_t *out, int frames)
{
    bba_mix(&mx, out, frames);
}

static void wav_finish(void)
{
    uint8_t h[44];
    if (!wavf) return;
    bba_wav_header(h, mx.rate, wav_frames);
    fseek(wavf, 0, SEEK_SET);
    fwrite(h, 1, 44, wavf);
    fclose(wavf);
    wavf = NULL;
}

static void wav_write(const int16_t *pcm, int frames)
{
    uint8_t buf[4096];
    int i, k = 0;
    for (i = 0; i < frames * 2; i++) {
        buf[k++] = (uint8_t)pcm[i];
        buf[k++] = (uint8_t)((uint16_t)pcm[i] >> 8);
        if (k == sizeof buf) { fwrite(buf, 1, (size_t)k, wavf); k = 0; }
    }
    if (k) fwrite(buf, 1, (size_t)k, wavf);
    wav_frames += (uint32_t)frames;
}

static void dev_close(void)
{
    int i;
    if (dev == DEV_PLAT) audio_plat_close();
    wav_finish();
    dev = DEV_CLOSED;
    bba_stop(&mx.music);
    for (i = 0; i < BBA_VOICES; i++) mx.voice[i].snd = NULL;
}

static void at_exit(void) { if (dev != DEV_CLOSED) dev_close(); }

static void dev_open(const char *name, int rate)
{
    int had = mx.rate, master = mx.master, mv = mx.music_vol, sv = mx.sound_vol;
    int mon = mx.music_on, son = mx.sound_on, loop = mx.music.loop;
    if (dev != DEV_CLOSED) dev_close();
    if (rate < 8000 || rate > 48000) bb_raise(5, NULL);
    bba_mixer_free(&mx);
    bba_mixer_init(&mx, rate);
    if (had) {                  /* keep the settings (volumes, switches) across a re-open */
        mx.master = master;
        mx.music_vol = mv;
        mx.sound_vol = sv;
        mx.music_on = mon;
        mx.sound_on = son;
        mx.music.loop = loop;
    }
    if (!exit_hooked) { atexit(at_exit); exit_hooked = 1; }
    have_plat_dev = 0;
    if (!strcasecmp(name, "manual")) dev = DEV_MANUAL;
    else if (!strncasecmp(name, "wav:", 4)) {
        uint8_t h[44] = { 0 };
        wavf = fopen(name + 4, "wb");
        if (!wavf) bb_raise(75, NULL);
        fwrite(h, 1, 44, wavf);
        wav_frames = 0;
        dev = DEV_WAV;
    } else if (!strcasecmp(name, "null")) dev = DEV_NULL;
    else if (!*name || !strcasecmp(name, "default") || !strcasecmp(name, audio_plat_name())) {
        if (audio_plat_open(rate)) { dev = DEV_PLAT; have_plat_dev = 1; }
        else dev = DEV_NULL;
    } else bb_raise(5, NULL);
    null_t0 = bb_plat_seconds();
    null_frames = 0;
}

/* the silent device: mix what the clock says should have played by now */
static void pump_null(void)
{
    double now;
    uint64_t want;
    if (dev != DEV_NULL) return;
    now = bb_plat_seconds() - null_t0;
    want = (uint64_t)(now * mx.rate);
    if (want <= null_frames) return;
    if (want - null_frames > (uint64_t)mx.rate / 2) null_frames = want - (uint64_t)mx.rate / 2;
    if (!scratch) scratch = (int16_t *)malloc(2048 * 4);
    if (!scratch) return;
    while (null_frames < want) {
        int n = want - null_frames > 2048 ? 2048 : (int)(want - null_frames);
        bba_mix(&mx, scratch, n);
        null_frames += (uint64_t)n;
    }
}

static void render(int32_t frames)
{
    if (!scratch) scratch = (int16_t *)malloc(2048 * 4);
    if (!scratch) bb_raise(7, NULL);
    while (frames > 0) {
        int n = frames > 2048 ? 2048 : frames;
        bba_mix(&mx, scratch, n);
        if (wavf) wav_write(scratch, n);
        frames -= n;
    }
}

/* export: a song from its start into a WAV file, on a mixer of its own */
static void render_to_wav(bba_song *s, const char *path, int32_t maxs)
{
    bba_mixer *m = (bba_mixer *)malloc(sizeof *m);
    int16_t *buf = (int16_t *)malloc(2048 * 4);
    FILE *f;
    FILE *keepf = wavf;
    uint32_t keepn = wav_frames;
    uint64_t total = 0, limit;
    uint8_t h[44] = { 0 };
    if (!m || !buf) { free(m); free(buf); bb_raise(7, NULL); }
    f = fopen(path, "wb");
    if (!f) { free(m); free(buf); bb_raise(75, NULL); }
    fwrite(h, 1, 44, f);
    bba_mixer_init(m, mx.rate ? mx.rate : 22050);
    m->music_vol = 64;
    m->music.loop = 0;
    bba_play(&m->music, s, 0, 0);
    limit = (uint64_t)(maxs > 0 ? maxs : 600) * (uint64_t)m->rate;
    wavf = f;
    wav_frames = 0;
    while (m->music.playing && total < limit) {
        bba_mix(m, buf, 2048);
        wav_write(buf, 2048);
        total += 2048;
    }
    bba_wav_header(h, m->rate, wav_frames);
    fseek(f, 0, SEEK_SET);
    fwrite(h, 1, 44, f);
    fclose(f);
    wavf = keepf;
    wav_frames = keepn;
    bba_mixer_free(m);
    free(m);
    free(buf);
}

/* ---------------------------------------------------------------- the object */

enum {
    M_OPEN = 1, M_CLOSE, P_DEVICE, P_RATE, M_RENDER, P_PCMHASH, M_RESETHASH, M_RENDERTOWAV,
    P_VOLUME, P_CPULOAD,
    M_LOADMUSIC, M_NEWSONG, M_SAVEMUSIC, M_FREEMUSIC, M_PLAYMUSIC, M_STOPMUSIC, M_PAUSE,
    M_RESUME, P_PLAYING, P_PAUSED, P_CURRENTSONG, P_MUSICVOLUME, P_MUSICENABLED, P_LOOP,
    P_SONGENDED, P_POSITION, P_ROW, P_PATTERN, P_TICK, M_JUMPTO, P_SPEED, P_TEMPO, P_MUTE,
    M_SOLO, P_CHANNELVOLUME, P_CHANNELVU, P_CHANNELNOTE, P_CHANNELSAMPLE, M_SCOPE,
    M_PLAYNOTE, M_PLAYROW, M_NOTEOFF, P_EDITSONG,
    P_SONGNAME, P_CHANNELS, P_SONGLENGTH, P_ORDER, P_PATTERNCOUNT, M_ADDPATTERN,
    M_CLEARPATTERN, M_COPYPATTERN, P_CELLNOTE, P_CELLPERIOD, P_CELLSAMPLE, P_CELLEFFECT,
    P_CELLPARAM, P_CELL, M_SETCELL, P_SAMPLENAME, P_SAMPLELENGTH, P_SAMPLEVOLUME,
    P_SAMPLEFINETUNE, P_SAMPLELOOPSTART, P_SAMPLELOOPLENGTH, P_SAMPLEDATA, M_LOADSAMPLE,
    M_SETSAMPLEFROMSOUND, M_NOTENAME, M_NOTEFROMNAME, M_NOTEPERIOD,
    M_LOADSOUND, M_CREATESOUND, P_SOUNDDATA, P_SOUNDLENGTH, P_SOUNDRATE, P_SOUNDBITS,
    P_SOUNDLOOP, P_SOUNDLOOPSTART, P_SOUNDLOOPLENGTH, M_SYNTHTONE, M_SYNTHNOISE, M_FREESOUND,
    M_PLAYSOUND, M_PLAYSOUNDPRI, M_STOPVOICE, M_STOPSOUNDS, P_VOICEPLAYING, P_VOICEVOLUME,
    P_VOICEPAN, P_VOICERATE, P_SOUNDVOLUME, P_SOUNDENABLED, P_VOICES,
    M_PLAYPATTERN, M_SETSAMPLEBYTES, M_GETSAMPLEBYTES, P_CHANNELPOS, P_SONGSPEED, P_SONGTEMPO,
    P_SONGRESTART, M_SFXDEFINE, M_SFXTONE, M_SFXNOISE, M_SFX, P_SFXSOUND, M_STATE, M_SCOPES
};

static const struct { const char *name; int32_t id; } members[] = {
    {"Open", M_OPEN}, {"Close", M_CLOSE}, {"Device", P_DEVICE}, {"Rate", P_RATE},
    {"Render", M_RENDER}, {"PcmHash", P_PCMHASH}, {"ResetHash", M_RESETHASH},
    {"RenderToWav", M_RENDERTOWAV}, {"Volume", P_VOLUME}, {"CpuLoad", P_CPULOAD},
    {"LoadMusic", M_LOADMUSIC}, {"NewSong", M_NEWSONG}, {"SaveMusic", M_SAVEMUSIC},
    {"FreeMusic", M_FREEMUSIC}, {"PlayMusic", M_PLAYMUSIC}, {"StopMusic", M_STOPMUSIC},
    {"Pause", M_PAUSE}, {"Resume", M_RESUME}, {"Playing", P_PLAYING}, {"Paused", P_PAUSED},
    {"CurrentSong", P_CURRENTSONG}, {"MusicVolume", P_MUSICVOLUME},
    {"MusicEnabled", P_MUSICENABLED}, {"Loop", P_LOOP}, {"SongEnded", P_SONGENDED},
    {"Position", P_POSITION}, {"Row", P_ROW}, {"Pattern", P_PATTERN}, {"Tick", P_TICK},
    {"JumpTo", M_JUMPTO}, {"Speed", P_SPEED}, {"Tempo", P_TEMPO}, {"Mute", P_MUTE},
    {"Solo", M_SOLO}, {"ChannelVolume", P_CHANNELVOLUME}, {"ChannelVU", P_CHANNELVU},
    {"ChannelNote", P_CHANNELNOTE}, {"ChannelSample", P_CHANNELSAMPLE}, {"Scope", M_SCOPE},
    {"PlayNote", M_PLAYNOTE}, {"PlayRow", M_PLAYROW}, {"NoteOff", M_NOTEOFF},
    {"EditSong", P_EDITSONG}, {"SongName", P_SONGNAME}, {"Channels", P_CHANNELS},
    {"SongLength", P_SONGLENGTH}, {"Order", P_ORDER}, {"PatternCount", P_PATTERNCOUNT},
    {"AddPattern", M_ADDPATTERN}, {"ClearPattern", M_CLEARPATTERN},
    {"CopyPattern", M_COPYPATTERN}, {"CellNote", P_CELLNOTE}, {"CellPeriod", P_CELLPERIOD},
    {"CellSample", P_CELLSAMPLE}, {"CellEffect", P_CELLEFFECT}, {"CellParam", P_CELLPARAM},
    {"Cell", P_CELL}, {"SetCell", M_SETCELL}, {"SampleName", P_SAMPLENAME},
    {"SampleLength", P_SAMPLELENGTH}, {"SampleVolume", P_SAMPLEVOLUME},
    {"SampleFinetune", P_SAMPLEFINETUNE}, {"SampleLoopStart", P_SAMPLELOOPSTART},
    {"SampleLoopLength", P_SAMPLELOOPLENGTH}, {"SampleData", P_SAMPLEDATA},
    {"LoadSample", M_LOADSAMPLE}, {"SetSampleFromSound", M_SETSAMPLEFROMSOUND},
    {"NoteName", M_NOTENAME}, {"NoteFromName", M_NOTEFROMNAME}, {"NotePeriod", M_NOTEPERIOD},
    {"LoadSound", M_LOADSOUND}, {"CreateSound", M_CREATESOUND}, {"SoundData", P_SOUNDDATA},
    {"SoundLength", P_SOUNDLENGTH}, {"SoundRate", P_SOUNDRATE}, {"SoundBits", P_SOUNDBITS},
    {"SoundLoop", P_SOUNDLOOP}, {"SoundLoopStart", P_SOUNDLOOPSTART},
    {"SoundLoopLength", P_SOUNDLOOPLENGTH}, {"SynthTone", M_SYNTHTONE},
    {"SynthNoise", M_SYNTHNOISE}, {"FreeSound", M_FREESOUND}, {"PlaySound", M_PLAYSOUND},
    {"PlaySoundPri", M_PLAYSOUNDPRI}, {"StopVoice", M_STOPVOICE}, {"StopSounds", M_STOPSOUNDS},
    {"VoicePlaying", P_VOICEPLAYING}, {"VoiceVolume", P_VOICEVOLUME}, {"VoicePan", P_VOICEPAN},
    {"VoiceRate", P_VOICERATE}, {"SoundVolume", P_SOUNDVOLUME},
    {"SoundEnabled", P_SOUNDENABLED}, {"Voices", P_VOICES},
    {"PlayPattern", M_PLAYPATTERN}, {"SetSampleBytes", M_SETSAMPLEBYTES},
    {"GetSampleBytes", M_GETSAMPLEBYTES}, {"ChannelPos", P_CHANNELPOS}, {"SongSpeed", P_SONGSPEED},
    {"SongTempo", P_SONGTEMPO}, {"SongRestart", P_SONGRESTART}, {"SfxDefine", M_SFXDEFINE},
    {"SfxTone", M_SFXTONE}, {"SfxNoise", M_SFXNOISE}, {"Sfx", M_SFX}, {"SfxSound", P_SFXSOUND}, {"State", M_STATE}, {"Scopes", M_SCOPES},
};

static int32_t au_find(const bb_class *cls, const char *name)
{
    size_t i;
    (void)cls;
    if (!name || !*name) return BB_NOMEMBER;
    for (i = 0; i < sizeof members / sizeof members[0]; i++)
        if (strcasecmp(members[i].name, name) == 0) return members[i].id;
    return BB_NOMEMBER;
}

static void unlock_cb(void *ctx) { (void)ctx; audio_plat_unlock(); }

#define SETTING (kind & (BB_INV_LET | BB_INV_SET))
/* a property with nidx index arguments: the new value when setting */
#define NEWV(nidx) argl(argc, argv, (nidx))

static bba_chan *chan_arg(int argc, const bb_value *argv, int i)
{
    int32_t c = argl(argc, argv, i);
    range(c, 0, BBA_MAXCH - 1, 9);
    return &mx.music.ch[c];
}

/* the song live notes use: the playing one, else the edit song */
static bba_song *live_song(void)
{
    bba_player *p = &mx.music;
    if (p->playing && p->song) return p->song;
    if (edit_song >= 1 && edit_song <= nsongs && songs[edit_song - 1]) p->song = songs[edit_song - 1];
    if (!p->song) bb_raise(5, NULL);
    return p->song;
}

static void dispatch(int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    bba_player *p = &mx.music;
    char buf[1024];
    switch (id) {
    /* ---- device ---- */
    case P_DEVICE:
        *ret = bb_v_str(bb_str_from_c(dev == DEV_PLAT ? audio_plat_name() : dev == DEV_MANUAL ? "manual" :
                                      dev == DEV_WAV ? "wav" : dev == DEV_NULL ? (have_plat_dev || !strcmp(audio_plat_name(), "null") ? "null" : "none") : "closed"));
        return;
    case P_RATE: *ret = bb_v_long(mx.rate); return;
    case M_RENDER: {
        int32_t n = argl(argc, argv, 0);
        range(n, 0, 0x7FFFFFF, 5);
        if (dev != DEV_MANUAL && dev != DEV_WAV) bb_raise(5, NULL);
        render(n);
        return;
    }
    case P_PCMHASH: *ret = bb_v_long((int32_t)mx.hash); return;
    case M_RESETHASH: mx.hash = 2166136261u; return;
    case P_VOLUME:
        if (SETTING) { int32_t v = NEWV(0); range(v, 0, 64, 380); mx.master = v; }
        else *ret = bb_v_long(mx.master);
        return;
    case P_CPULOAD: *ret = bb_v_long(audio_plat_cpu_load()); return;

    /* ---- music ---- */
    case M_LOADMUSIC: {
        long len;
        uint8_t *d = read_file(argstr(argc, argv, 0, buf, sizeof buf), &len);
        bba_song *s = bba_song_load(d, len);
        free(d);
        if (!s) bb_raise(380, NULL);
        *ret = bb_v_long(add_song(s));
        return;
    }
    case M_NEWSONG: {
        int32_t n = argl_opt(argc, argv, 0, 4);
        if (n != 4 && n != 6 && n != 8) bb_raise(5, NULL);
        *ret = bb_v_long(add_song(bba_song_new(n)));
        return;
    }
    case M_SAVEMUSIC: {
        bba_song *s = song(argl(argc, argv, 0));
        long len;
        uint8_t *d = bba_song_save(s, &len);
        FILE *f;
        if (!d) bb_raise(7, NULL);
        f = fopen(argstr(argc, argv, 1, buf, sizeof buf), "wb");
        if (!f) { free(d); bb_raise(75, NULL); }
        if (fwrite(d, 1, (size_t)len, f) != (size_t)len) { fclose(f); free(d); bb_raise(61, NULL); }
        fclose(f);
        free(d);
        return;
    }
    case M_FREEMUSIC: {
        int32_t n = argl(argc, argv, 0);
        bba_song *s = song(n);
        bba_song_gone(p, s);
        bba_song_free(s);
        songs[n - 1] = NULL;
        if (edit_song == n) edit_song = 0;
        return;
    }
    case M_PLAYMUSIC: {
        int32_t n = argl(argc, argv, 0);
        bba_song *s = song(n);
        bba_play(p, s, argl_opt(argc, argv, 1, 0), argl_opt(argc, argv, 2, 0));
        edit_song = n;
        return;
    }
    case M_STOPMUSIC: bba_stop(p); return;
    case M_PAUSE: if (p->playing) p->paused = 1; return;
    case M_RESUME: p->paused = 0; return;
    case P_PLAYING: *ret = bb_v_bool(p->playing); return;
    case P_PAUSED: *ret = bb_v_bool(p->paused); return;
    case P_CURRENTSONG: *ret = bb_v_long(p->playing && p->song ? song_num(p->song) : 0); return;
    case P_MUSICVOLUME:
        if (SETTING) { int32_t v = NEWV(0); range(v, 0, 64, 380); mx.music_vol = v; }
        else *ret = bb_v_long(mx.music_vol);
        return;
    case P_MUSICENABLED:
        if (SETTING) mx.music_on = argb(argc, argv, 0);
        else *ret = bb_v_bool(mx.music_on);
        return;
    case P_LOOP:
        if (SETTING) p->loop = argb(argc, argv, 0);
        else *ret = bb_v_bool(p->loop);
        return;
    case P_SONGENDED: *ret = bb_v_long(p->ended); return;
    case P_POSITION: case P_ROW: case M_JUMPTO:
        if (id == M_JUMPTO || SETTING) {
            int32_t pos = id == P_ROW ? p->pos : argl(argc, argv, 0);
            int32_t row = id == P_ROW ? NEWV(0) : id == M_JUMPTO ? argl_opt(argc, argv, 1, 0) : 0;
            if (!p->song) bb_raise(5, NULL);
            range(pos, 0, p->song->song_len - 1, 9);
            range(row, 0, BBA_ROWS - 1, 9);
            p->pos = pos;
            p->row = row;
            p->tick = 0;
            p->tick_left = 0;
            p->jump_pos = p->break_row = -1;
            p->pat_delay = p->delay_rows = 0;
        } else *ret = bb_v_long(id == P_POSITION ? p->pos : p->row);
        return;
    case P_PATTERN: *ret = bb_v_long(!p->song ? 0 : p->pat_mode >= 0 ? p->pat_mode : p->song->order[p->pos]); return;
    case P_TICK: *ret = bb_v_long(p->tick); return;
    case P_SPEED:
        if (SETTING) { int32_t v = NEWV(0); range(v, 1, 31, 380); p->speed = v; }
        else *ret = bb_v_long(p->speed);
        return;
    case P_TEMPO:
        if (SETTING) { int32_t v = NEWV(0); range(v, 32, 255, 380); p->bpm = v; }
        else *ret = bb_v_long(p->bpm);
        return;
    case P_MUTE: {
        bba_chan *c = chan_arg(argc, argv, 0);
        if (SETTING) c->muted = argb(argc, argv, 1);
        else *ret = bb_v_bool(c->muted);
        return;
    }
    case M_SOLO: {
        int32_t ch = argl(argc, argv, 0), i;
        range(ch, -1, BBA_MAXCH - 1, 9);
        for (i = 0; i < BBA_MAXCH; i++) p->ch[i].muted = ch >= 0 && i != ch;
        return;
    }
    case P_CHANNELVOLUME: *ret = bb_v_long(chan_arg(argc, argv, 0)->outvol); return;
    case P_CHANNELVU: { bba_chan *c = chan_arg(argc, argv, 0); *ret = bb_v_long(c->active ? c->vu : 0); return; }
    case P_CHANNELNOTE: *ret = bb_v_long(chan_arg(argc, argv, 0)->note); return;
    case P_CHANNELSAMPLE: *ret = bb_v_long(chan_arg(argc, argv, 0)->smp); return;
    case M_SCOPE: {
        /* Scope(channel, n): a Long array (0 To n-1) of the last n output samples */
        int32_t ch = argl(argc, argv, 0), n = argl(argc, argv, 1), k;
        bb_array *a;
        bb_value v;
        range(ch, -1, BBA_MAXCH - 1, 9);
        range(n, 1, BBA_SCOPE, 5);
        a = bb_arr_new1(BB_LONG, 0, n - 1);
        for (k = 0; k < n; k++) {
            int32_t x;
            if (ch < 0) {
                uint32_t q = mx.scope_mix_pos - (uint32_t)(n - k) * 2;
                x = (mx.scope_mix[q & (BBA_SCOPE * 2 - 1)] + mx.scope_mix[(q + 1) & (BBA_SCOPE * 2 - 1)]) / 2;
            } else {
                const bba_chan *c = &p->ch[ch];
                x = c->scope[(c->scope_pos - (uint32_t)(n - k)) & (BBA_SCOPE - 1)];
            }
            ((bb_long *)a->data)[k] = x;
        }
        v = bb_v_make(BB_ARRAY | BB_LONG);
        v.u.a = a;
        *ret = v;
        return;
    }
    /* ---- live ---- */
    case M_PLAYNOTE: {
        int32_t ch = argl(argc, argv, 0), note = argl(argc, argv, 1), smp = argl(argc, argv, 2);
        int32_t vol = argl_opt(argc, argv, 3, -1), eff = argl_opt(argc, argv, 4, 0), prm = argl_opt(argc, argv, 5, 0);
        uint8_t cell[4];
        bba_song *s = live_song();
        range(ch, 0, s->nch - 1, 9);
        range(note, 0, BBA_NOTES, 5);
        range(smp, 0, 31, 9);
        range(vol, -1, 64, 5);
        range(eff, 0, 15, 5);
        range(prm, 0, 255, 5);
        set_cell(cell, note, 0, smp, eff, prm);
        bba_play_cell(p, ch, cell);
        if (vol >= 0) p->ch[ch].volume = p->ch[ch].outvol = vol;
        return;
    }
    case M_PLAYROW: {
        int32_t n = argl(argc, argv, 0), pat = argl(argc, argv, 1), row = argl(argc, argv, 2);
        bba_song *s = song(n);
        if (p->playing && p->song != s) bb_raise(5, NULL);
        range(pat, 0, s->npat - 1, 9);
        range(row, 0, BBA_ROWS - 1, 9);
        p->song = s;
        bba_play_row(p, pat, row);
        return;
    }
    case M_NOTEOFF: chan_arg(argc, argv, 0)->active = 0; return;
    case P_EDITSONG:
        if (SETTING) { int32_t n = NEWV(0); song(n); edit_song = n; }
        else *ret = bb_v_long(edit_song);
        return;

    /* ---- song data ---- */
    case P_SONGNAME: {
        bba_song *s = song(argl(argc, argv, 0));
        if (SETTING) argstr(argc, argv, 1, s->name, sizeof s->name);
        else *ret = bb_v_str(bb_str_from_c(s->name));
        return;
    }
    case P_CHANNELS: *ret = bb_v_long(song(argl(argc, argv, 0))->nch); return;
    case P_SONGLENGTH: {
        bba_song *s = song(argl(argc, argv, 0));
        if (SETTING) {
            int32_t v = NEWV(1);
            range(v, 1, 128, 380);
            s->song_len = v;
            if (s->restart >= v) s->restart = 0;
            if (p->song == s && p->pos >= v) { p->pos = 0; p->row = 0; }
        } else *ret = bb_v_long(s->song_len);
        return;
    }
    case P_ORDER: {
        bba_song *s = song(argl(argc, argv, 0));
        int32_t pos = argl(argc, argv, 1);
        range(pos, 0, 127, 9);
        if (SETTING) { int32_t v = NEWV(2); range(v, 0, s->npat - 1, 380); s->order[pos] = (uint8_t)v; }
        else *ret = bb_v_long(s->order[pos]);
        return;
    }
    case P_PATTERNCOUNT: *ret = bb_v_long(song(argl(argc, argv, 0))->npat); return;
    case M_ADDPATTERN: {
        int n = bba_song_add_pattern(song(argl(argc, argv, 0)));
        if (n < 0) bb_raise(7, NULL);
        *ret = bb_v_long(n);
        return;
    }
    case M_CLEARPATTERN: case M_COPYPATTERN: {
        bba_song *s = song(argl(argc, argv, 0));
        int32_t a = argl(argc, argv, 1), b = id == M_COPYPATTERN ? argl(argc, argv, 2) : a;
        size_t psize = (size_t)BBA_ROWS * s->nch * 4;
        range(a, 0, s->npat - 1, 9);
        range(b, 0, s->npat - 1, 9);
        if (id == M_CLEARPATTERN) memset(bba_cell(s, a, 0, 0), 0, psize);
        else if (a != b) memmove(bba_cell(s, b, 0, 0), bba_cell(s, a, 0, 0), psize);
        return;
    }
    case P_CELLNOTE: case P_CELLPERIOD: case P_CELLSAMPLE: case P_CELLEFFECT: case P_CELLPARAM: case P_CELL: {
        uint8_t *c = cell_arg(argc, argv, NULL);
        int per = cell_period(c), smp = cell_sample(c), eff = c[2] & 15, prm = c[3];
        if (SETTING) {
            int32_t v = NEWV(4);
            switch (id) {
            case P_CELLNOTE: range(v, 0, BBA_NOTES, 380); per = v ? bba_note_period(v, 0) : 0; break;
            case P_CELLPERIOD: range(v, 0, 4095, 380); per = v; break;
            case P_CELLSAMPLE: range(v, 0, 31, 380); smp = v; break;
            case P_CELLEFFECT: range(v, 0, 15, 380); eff = v; break;
            case P_CELLPARAM: range(v, 0, 255, 380); prm = v; break;
            default: {
                uint32_t u = (uint32_t)v;
                int note = (int)(u >> 24);
                if (note > BBA_NOTES || ((u >> 16) & 255) > 31 || ((u >> 8) & 255) > 15) bb_raise(380, NULL);
                per = note ? bba_note_period(note, 0) : 0;
                smp = (int)((u >> 16) & 255);
                eff = (int)((u >> 8) & 255);
                prm = (int)(u & 255);
            }
            }
            set_cell(c, -1, per, smp, eff, prm);
        } else {
            int note = bba_period_note(per);
            switch (id) {
            case P_CELLNOTE: *ret = bb_v_long(note); break;
            case P_CELLPERIOD: *ret = bb_v_long(per); break;
            case P_CELLSAMPLE: *ret = bb_v_long(smp); break;
            case P_CELLEFFECT: *ret = bb_v_long(eff); break;
            case P_CELLPARAM: *ret = bb_v_long(prm); break;
            default: *ret = bb_v_long((int32_t)(((uint32_t)note << 24) | ((uint32_t)smp << 16) | ((uint32_t)eff << 8) | (uint32_t)prm));
            }
        }
        return;
    }
    case M_SETCELL: {
        uint8_t *c = cell_arg(argc, argv, NULL);
        int32_t note = argl(argc, argv, 4), smp = argl(argc, argv, 5), eff = argl(argc, argv, 6), prm = argl(argc, argv, 7);
        range(note, 0, BBA_NOTES, 380);
        range(smp, 0, 31, 380);
        range(eff, 0, 15, 380);
        range(prm, 0, 255, 380);
        set_cell(c, note, 0, smp, eff, prm);
        return;
    }
    case P_SAMPLENAME: case P_SAMPLELENGTH: case P_SAMPLEVOLUME: case P_SAMPLEFINETUNE:
    case P_SAMPLELOOPSTART: case P_SAMPLELOOPLENGTH: {
        bba_song *s = song(argl(argc, argv, 0));
        int32_t sn = argl(argc, argv, 1);
        bba_sample *sm = sample(s, sn);
        if (id == P_SAMPLENAME) {
            if (SETTING) argstr(argc, argv, 2, sm->name, sizeof sm->name);
            else *ret = bb_v_str(bb_str_from_c(sm->name));
            return;
        }
        if (SETTING) {
            int32_t v = NEWV(2);
            switch (id) {
            case P_SAMPLELENGTH:
                range(v, 0, 131070, 380);
                if (!bba_sample_resize(sm, (uint32_t)v)) bb_raise(7, NULL);
                break;
            case P_SAMPLEVOLUME: range(v, 0, 64, 380); sm->vol = v; break;
            case P_SAMPLEFINETUNE: range(v, -8, 7, 380); sm->finetune = v & 15; break;
            case P_SAMPLELOOPSTART:
                range(v, 0, (int32_t)sm->len, 380);
                sm->loop_start = (uint32_t)v & ~1u;
                if (sm->loop_start + sm->loop_len > sm->len) sm->loop_len = sm->len - sm->loop_start;
                break;
            default:
                range(v, 0, (int32_t)(sm->len - sm->loop_start), 380);
                sm->loop_len = (uint32_t)v & ~1u;
            }
        } else {
            switch (id) {
            case P_SAMPLELENGTH: *ret = bb_v_long((int32_t)sm->len); break;
            case P_SAMPLEVOLUME: *ret = bb_v_long(sm->vol); break;
            case P_SAMPLEFINETUNE: *ret = bb_v_long(sm->finetune > 7 ? sm->finetune - 16 : sm->finetune); break;
            case P_SAMPLELOOPSTART: *ret = bb_v_long((int32_t)sm->loop_start); break;
            default: *ret = bb_v_long((int32_t)sm->loop_len);
            }
        }
        return;
    }
    case P_SAMPLEDATA: {
        bba_sample *sm = sample(song(argl(argc, argv, 0)), argl(argc, argv, 1));
        int32_t i = argl(argc, argv, 2);
        range(i, 0, (int32_t)sm->len - 1, 9);
        if (SETTING) { int32_t v = NEWV(3); range(v, -128, 127, 380); sm->data[i] = (int8_t)v; }
        else *ret = bb_v_long(sm->data[i]);
        return;
    }
    case M_LOADSAMPLE: case M_SETSAMPLEFROMSOUND: {
        bba_song *s = song(argl(argc, argv, 0));
        int32_t sn = argl(argc, argv, 1);
        bba_sample *sm = sample(s, sn);
        if (id == M_LOADSAMPLE) {
            long len;
            const char *path = argstr(argc, argv, 2, buf, sizeof buf), *base;
            uint8_t *d = read_file(path, &len);
            bba_sound *snd = bba_sound_parse(d, len, NULL, 0);
            free(d);
            if (!snd) bb_raise(380, NULL);
            bba_sample_changed(p, sn);
            sound_into_sample(sm, snd);
            bba_sound_free(snd);
            base = strrchr(path, '/');
            if (!base) base = strrchr(path, ':');
            base = base ? base + 1 : path;
            snprintf(sm->name, sizeof sm->name, "%s", base);
        } else {
            bba_sound *snd = sound(argl(argc, argv, 2));
            bba_sample_changed(p, sn);
            sound_into_sample(sm, snd);
        }
        return;
    }
    case M_NOTENAME: {
        int32_t n = argl(argc, argv, 0);
        if (n < 1 || n > BBA_NOTES) *ret = bb_v_str(bb_str_from_c("---"));
        else {
            snprintf(buf, sizeof buf, "%s%d", note_names[(n - 1) % 12], (int)((n - 1) / 12 + 1));
            *ret = bb_v_str(bb_str_from_c(buf));
        }
        return;
    }
    case M_NOTEFROMNAME: *ret = bb_v_long(note_from_name(argstr(argc, argv, 0, buf, sizeof buf))); return;
    case M_NOTEPERIOD: {
        int32_t n = argl(argc, argv, 0), ft = argl_opt(argc, argv, 1, 0);
        range(ft, -8, 7, 5);
        *ret = bb_v_long(bba_note_period(n, ft & 15));
        return;
    }

    /* ---- sound effects ---- */
    case M_LOADSOUND: {
        long len;
        char fmt[16];
        int32_t rate = argl_opt(argc, argv, 1, 0);
        uint8_t *d = read_file(argstr(argc, argv, 0, buf, sizeof buf), &len);
        bba_sound *s;
        fmt[0] = 0;
        if (!missing(argc, argv, 2)) argstr(argc, argv, 2, fmt, sizeof fmt);
        s = bba_sound_parse(d, len, fmt[0] ? fmt : NULL, rate);
        free(d);
        if (!s) bb_raise(380, NULL);
        if (rate > 0) s->rate = rate;
        *ret = bb_v_long(add_sound(s));
        return;
    }
    case M_CREATESOUND: {
        int32_t n = argl(argc, argv, 0), rate = argl_opt(argc, argv, 1, 22050), bits = argl_opt(argc, argv, 2, 16);
        range(n, 1, 0x1000000, 5);
        range(rate, 1, 200000, 5);
        if (bits != 8 && bits != 16) bb_raise(5, NULL);
        *ret = bb_v_long(add_sound(bba_sound_new((uint32_t)n, rate, bits)));
        return;
    }
    case P_SOUNDDATA: {
        bba_sound *s = sound(argl(argc, argv, 0));
        int32_t i = argl(argc, argv, 1);
        range(i, 0, (int32_t)s->len - 1, 9);
        if (SETTING) bba_sound_set(s, (uint32_t)i, NEWV(2));
        else *ret = bb_v_long(bba_sound_get(s, (uint32_t)i));
        return;
    }
    case P_SOUNDLENGTH: *ret = bb_v_long((int32_t)sound(argl(argc, argv, 0))->len); return;
    case P_SOUNDBITS: *ret = bb_v_long(sound(argl(argc, argv, 0))->bits); return;
    case P_SOUNDRATE: case P_SOUNDLOOP: case P_SOUNDLOOPSTART: case P_SOUNDLOOPLENGTH: {
        bba_sound *s = sound(argl(argc, argv, 0));
        if (SETTING) {
            int32_t v = id == P_SOUNDLOOP ? argb(argc, argv, 1) : NEWV(1);
            switch (id) {
            case P_SOUNDRATE: range(v, 1, 200000, 380); s->rate = v; break;
            case P_SOUNDLOOP: s->loop = v != 0; break;
            case P_SOUNDLOOPSTART: range(v, 0, (int32_t)s->len, 380); s->loop_start = (uint32_t)v; break;
            default: range(v, 0, (int32_t)s->len, 380); s->loop_len = (uint32_t)v;
            }
        } else {
            switch (id) {
            case P_SOUNDRATE: *ret = bb_v_long(s->rate); break;
            case P_SOUNDLOOP: *ret = bb_v_bool(s->loop); break;
            case P_SOUNDLOOPSTART: *ret = bb_v_long((int32_t)s->loop_start); break;
            default: *ret = bb_v_long((int32_t)s->loop_len);
            }
        }
        return;
    }
    case M_SYNTHTONE: {
        int32_t ms = argl(argc, argv, 0), f0 = argl(argc, argv, 1), f1 = argl(argc, argv, 2);
        int32_t vol = argl_opt(argc, argv, 3, 64), w = argl_opt(argc, argv, 4, 0);
        bba_sound *s;
        range(ms, 1, 60000, 5);
        range(f0, 1, 20000, 5);
        range(f1, 1, 20000, 5);
        range(w, 0, 3, 5);
        s = bba_synth_tone(mx.rate, ms, f0, f1, vol, w);
        *ret = bb_v_long(add_sound(s));
        return;
    }
    case M_SYNTHNOISE: {
        int32_t ms = argl(argc, argv, 0), vol = argl_opt(argc, argv, 1, 64);
        int32_t sm = argl_opt(argc, argv, 2, 0), att = argl_opt(argc, argv, 3, 0);
        range(ms, 1, 60000, 5);
        *ret = bb_v_long(add_sound(bba_synth_noise(mx.rate, ms, vol, sm, att)));
        return;
    }
    case M_FREESOUND: {
        int32_t n = argl(argc, argv, 0);
        bba_sound *s = sound(n);
        bba_sound_gone(&mx, s);
        bba_sound_free(s);
        sounds[n - 1] = NULL;
        return;
    }
    case M_PLAYSOUND: case M_PLAYSOUNDPRI: {
        int k = id == M_PLAYSOUNDPRI;
        bba_sound *s = sound(argl(argc, argv, 0));
        int32_t pri = k ? argl(argc, argv, 1) : 0;
        int32_t vol = argl_opt(argc, argv, 1 + k, 64), pan = argl_opt(argc, argv, 2 + k, 0);
        int32_t rate = argl_opt(argc, argv, 3 + k, 0);
        int32_t loop = missing(argc, argv, 4 + k) ? -1 : argb(argc, argv, 4 + k);
        range(vol, 0, 64, 5);
        range(pan, -64, 64, 5);
        range(rate, 0, 200000, 5);
        *ret = bb_v_long(mx.sound_on ? (int32_t)bba_voice_start(&mx, s, vol, pan, rate, loop, pri) : 0);
        return;
    }
    case M_STOPVOICE: {
        bba_voice *v = bba_voice_find(&mx, (uint32_t)argl(argc, argv, 0));
        if (v) v->snd = NULL;
        return;
    }
    case M_STOPSOUNDS: { int i; for (i = 0; i < BBA_VOICES; i++) mx.voice[i].snd = NULL; return; }
    case P_VOICEPLAYING: *ret = bb_v_bool(bba_voice_find(&mx, (uint32_t)argl(argc, argv, 0)) != NULL); return;
    case P_VOICEVOLUME: case P_VOICEPAN: case P_VOICERATE: {
        bba_voice *v = bba_voice_find(&mx, (uint32_t)argl(argc, argv, 0));
        if (SETTING) {
            int32_t x = NEWV(1);
            if (id == P_VOICEVOLUME) range(x, 0, 64, 380);
            else if (id == P_VOICEPAN) range(x, -64, 64, 380);
            else range(x, 1, 200000, 380);
            if (!v) return;                     /* ended: harmless */
            if (id == P_VOICEVOLUME) v->vol = x;
            else if (id == P_VOICEPAN) v->pan = x;
            else bba_voice_set_rate(&mx, v, x);
        } else *ret = bb_v_long(!v ? 0 : id == P_VOICEVOLUME ? v->vol : id == P_VOICEPAN ? v->pan : v->rate);
        return;
    }
    case P_SOUNDVOLUME:
        if (SETTING) { int32_t v = NEWV(0); range(v, 0, 64, 380); mx.sound_vol = v; }
        else *ret = bb_v_long(mx.sound_vol);
        return;
    case P_SOUNDENABLED:
        if (SETTING) {
            mx.sound_on = argb(argc, argv, 0);
            if (!mx.sound_on) { int i; for (i = 0; i < BBA_VOICES; i++) mx.voice[i].snd = NULL; }
        } else *ret = bb_v_bool(mx.sound_on);
        return;
    case P_VOICES: *ret = bb_v_long(BBA_VOICES); return;

    /* ---- batched reads: one late-bound call per frame instead of many ---- */
    case M_STATE: {
        /* State(): Long array 0..55, see docs/audio.md */
        bb_array *a = bb_arr_new1(BB_LONG, 0, 55);
        bb_long *d = (bb_long *)a->data;
        bb_value v;
        int c;
        d[0] = p->playing ? -1 : 0;
        d[1] = p->paused ? -1 : 0;
        d[2] = p->pos;
        d[3] = p->row;
        d[4] = !p->song ? 0 : p->pat_mode >= 0 ? p->pat_mode : p->song->order[p->pos];
        d[5] = p->tick;
        d[6] = p->speed;
        d[7] = p->bpm;
        d[8] = p->ended;
        d[9] = p->playing && p->song ? song_num(p->song) : 0;
        d[10] = p->song ? p->song->nch : 0;
        d[11] = audio_plat_cpu_load();
        for (c = 0; c < BBA_MAXCH; c++) {
            const bba_chan *ch = &p->ch[c];
            bb_long *e = d + 16 + c * 5;
            e[0] = ch->active ? ch->vu : 0;
            e[1] = ch->note;
            e[2] = ch->smp;
            e[3] = ch->outvol;
            e[4] = ch->active && !p->paused ? (bb_long)ch->pos : -1;
        }
        v = bb_v_make(BB_ARRAY | BB_LONG);
        v.u.a = a;
        *ret = v;
        return;
    }
    case M_SCOPES: {
        /* Scopes(n [, channels]): channel c's last n samples at c * n */
        int32_t n = argl(argc, argv, 0), nc = argl_opt(argc, argv, 1, p->song ? p->song->nch : 4), c, k;
        bb_array *a;
        bb_value v;
        range(n, 1, BBA_SCOPE, 5);
        range(nc, 1, BBA_MAXCH, 5);
        a = bb_arr_new1(BB_LONG, 0, n * nc - 1);
        for (c = 0; c < nc; c++) {
            const bba_chan *ch = &p->ch[c];
            for (k = 0; k < n; k++)
                ((bb_long *)a->data)[c * n + k] = ch->scope[(ch->scope_pos - (uint32_t)(n - k)) & (BBA_SCOPE - 1)];
        }
        v = bb_v_make(BB_ARRAY | BB_LONG);
        v.u.a = a;
        *ret = v;
        return;
    }

    /* ---- tracker extras ---- */
    case M_PLAYPATTERN: {
        int32_t n = argl(argc, argv, 0), pat = argl(argc, argv, 1), row = argl_opt(argc, argv, 2, 0);
        bba_song *s = song(n);
        range(pat, 0, s->npat - 1, 9);
        range(row, 0, BBA_ROWS - 1, 9);
        bba_play_pattern(p, s, pat, row);
        edit_song = n;
        return;
    }
    case M_SETSAMPLEBYTES: {
        bba_song *s = song(argl(argc, argv, 0));
        int32_t sn = argl(argc, argv, 1), n, k;
        bba_sample *sm = sample(s, sn);
        bb_array *a = arg_array(argc, argv, 2);
        n = argl_opt(argc, argv, 3, a ? a->count : 0);
        if (!a || n < 0 || n > a->count) bb_raise(9, NULL);
        range(n, 0, 131070, 5);
        bba_sample_changed(p, sn);
        if (!bba_sample_resize(sm, (uint32_t)n)) bb_raise(7, NULL);
        for (k = 0; k < (int32_t)sm->len; k++) sm->data[k] = (int8_t)(uint8_t)(elem_l(a, k) & 255);
        return;
    }
    case M_GETSAMPLEBYTES: {
        bba_sample *sm = sample(song(argl(argc, argv, 0)), argl(argc, argv, 1));
        bb_array *a;
        bb_value v;
        if (!sm->len) { *ret = bb_v_empty(); return; }
        a = bb_arr_new1(BB_BYTE, 0, (int32_t)sm->len - 1);
        memcpy(a->data, sm->data, sm->len);
        v = bb_v_make(BB_ARRAY | BB_BYTE);
        v.u.a = a;
        *ret = v;
        return;
    }
    case P_CHANNELPOS: {
        bba_chan *c = chan_arg(argc, argv, 0);
        *ret = bb_v_long(c->active && !p->paused ? (int32_t)c->pos : -1);
        return;
    }
    case P_SONGSPEED: case P_SONGTEMPO: case P_SONGRESTART: {
        bba_song *s = song(argl(argc, argv, 0));
        if (SETTING) {
            int32_t v = NEWV(1);
            if (id == P_SONGSPEED) { range(v, 1, 31, 380); s->speed = v; }
            else if (id == P_SONGTEMPO) { range(v, 32, 255, 380); s->bpm = v; }
            else { range(v, 0, 127, 380); s->restart_byte = v; s->restart = v < s->song_len ? v : 0; }
        } else *ret = bb_v_long(id == P_SONGSPEED ? s->speed : id == P_SONGTEMPO ? s->bpm : s->restart_byte);
        return;
    }
    case M_SFXDEFINE: {
        /* a3d_sound.c's a3_sfx_define: an 8-bit buffer of len samples played at 11.8 kHz */
        int32_t i = argl(argc, argv, 0), len = argl(argc, argv, 1), vol = argl_opt(argc, argv, 2, 64), pri = argl_opt(argc, argv, 3, 0);
        range(i, 0, SFX_IDS - 1, 9);
        range(len, 2, 131070, 5);
        range(vol, 0, 64, 5);
        if (sfx_snd[i] && sfx_snd[i] <= nsounds && sounds[sfx_snd[i] - 1]) {
            bba_sound_gone(&mx, sounds[sfx_snd[i] - 1]);
            bba_sound_free(sounds[sfx_snd[i] - 1]);
            sounds[sfx_snd[i] - 1] = NULL;
        }
        sfx_snd[i] = 0;
        sfx_snd[i] = add_sound(bba_sound_new((uint32_t)len & ~1u, FX_RATE, 8));
        sfx_vol[i] = vol;
        sfx_pri[i] = pri;
        return;
    }
    case M_SFXTONE: case M_SFXNOISE: {
        int32_t i = argl(argc, argv, 0), off = argl(argc, argv, 1), n = argl(argc, argv, 2), k;
        bba_sound *snd;
        int8_t *d;
        range(i, 0, SFX_IDS - 1, 9);
        snd = sound(sfx_snd[i]);
        if (off < 0 || n < 0 || (uint32_t)off + (uint32_t)n > snd->len) bb_raise(9, NULL);
        d = (int8_t *)snd->data + off;
        if (id == M_SFXTONE) {          /* a3_tone: a triangle f0 -> f1 Hz, fading over the last fade */
            int32_t f0 = argl(argc, argv, 3), f1 = argl(argc, argv, 4), amp = argl(argc, argv, 5), fade = argl_opt(argc, argv, 6, 1);
            uint32_t ph = 0;
            if (fade < 1) fade = 1;
            for (k = 0; k < n; k++) {
                int32_t f = f0 + (int32_t)(((int64_t)(f1 - f0) * k) / n), t, a = amp;
                ph += (uint32_t)(((int64_t)f * 65536) / FX_RATE);
                t = (int32_t)((ph >> 8) & 255);
                t = t < 128 ? t * 2 - 128 : 383 - t * 2;
                if (k > n - fade) a = (amp * (n - k)) / fade;
                d[k] = (int8_t)((t * a) / 128);
            }
        } else {                        /* a3_noise: noise, low-passed, attack then decay */
            int32_t amp = argl(argc, argv, 3), lp = argl_opt(argc, argv, 4, 1), att = argl_opt(argc, argv, 5, 0), acc = 0;
            if (lp < 1) lp = 1;
            if (att < 0) att = 0;
            for (k = 0; k < n; k++) {
                int32_t env, x;
                if (k < att) env = (amp * k) / att;
                else env = n - att > 0 ? (amp * (n - k)) / (n - att) : 0;
                a3_rng = a3_rng * 1103515245u + 12345u;
                x = (int32_t)((a3_rng >> 16) & 255) - 128;
                acc += x - acc / lp;
                d[k] = (int8_t)(((acc / lp) * env) / 128);
            }
        }
        return;
    }
    case M_SFX: {
        int32_t i = argl(argc, argv, 0), vol;
        range(i, 0, SFX_IDS - 1, 9);
        vol = argl_opt(argc, argv, 1, sfx_vol[i]);
        range(vol, 0, 64, 5);
        if (sfx_snd[i] && mx.sound_on)
            *ret = bb_v_long((int32_t)bba_voice_start(&mx, sound(sfx_snd[i]), vol, 0, 0, 0, sfx_pri[i]));
        else *ret = bb_v_long(0);
        return;
    }
    case P_SFXSOUND: {
        int32_t i = argl(argc, argv, 0);
        range(i, 0, SFX_IDS - 1, 9);
        *ret = bb_v_long(sfx_snd[i]);
        return;
    }
    }
    bb_raise(438, NULL);
}

static int is_snapshot(int32_t id)
{
    switch (id) {
    case P_PLAYING: case P_PAUSED: case P_CURRENTSONG: case P_SONGENDED: case P_POSITION:
    case P_ROW: case P_PATTERN: case P_TICK: case P_SPEED: case P_TEMPO: case P_MUTE:
    case P_CHANNELVOLUME: case P_CHANNELVU: case P_CHANNELNOTE: case P_CHANNELSAMPLE:
    case P_CHANNELPOS: case P_VOICEPLAYING: case P_CPULOAD: case P_RATE: case P_PCMHASH:
        return 1;
    }
    return 0;
}

static void au_invoke(bb_obj *self, int32_t id, int kind, int argc, bb_value *argv, bb_value *ret)
{
    bb_cleanup cl;
    char buf[1024];
    (void)self;
    /* calls that start or stop the mixer task, or run long, go without the lock */
    if (id == M_OPEN) {
        const char *name = missing(argc, argv, 0) ? "" : argstr(argc, argv, 0, buf, sizeof buf);
        dev_open(name, argl_opt(argc, argv, 1, 22050));
        return;
    }
    if (id == M_CLOSE) { if (dev != DEV_CLOSED) dev_close(); return; }
    if (dev == DEV_CLOSED && id != P_DEVICE) dev_open("", 22050);
    if (id == M_RENDERTOWAV) {
        bba_song *s = song(argl(argc, argv, 0));
        const char *path = argstr(argc, argv, 1, buf, sizeof buf);
        int32_t maxs = argl_opt(argc, argv, 2, 600);
        range(maxs, 1, 3600, 5);
        render_to_wav(s, path, maxs);
        return;
    }
    /* reads the mixer only writes (positions, levels, scopes): no lock. They are single
     * aligned words (a racy read is at worst one chunk old), and MutexObtain/Release cost
     * two exec calls per Audio call, which is slow under QEMU. Songs and sounds are only
     * freed by this task, so the pointers stay valid. */
    if (id == M_SCOPE || id == M_STATE || id == M_SCOPES || (kind == BB_INV_GET && argc <= 1 && is_snapshot(id))) {
        pump_null();
        dispatch(id, kind, argc, argv, ret);
        return;
    }
    cl.prev = bb_cleanups;
    cl.fn = unlock_cb;
    cl.ctx = NULL;
    audio_plat_lock();
    bb_cleanups = &cl;
    pump_null();
    dispatch(id, kind, argc, argv, ret);
    bb_cleanups = cl.prev;
    audio_plat_unlock();
}

static const bb_class audio_class = {
    "Audio", sizeof(bb_audio), au_find, au_invoke, NULL, NULL, NULL, 0, NULL, 0, NULL, NULL
};
const bb_class *bb_audio_class(void) { return &audio_class; }     /* compile-time member ids (canvas.c) */

bb_obj *bb_audio_new(void)
{
    return bb_obj_new(&audio_class);
}
