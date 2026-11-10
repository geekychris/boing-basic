/* canvas_os4.c - the Canvas platform layer on AmigaOS 4: blit the chunky ARGB32 picture into
 * the control's window with graphics.library's BltBitMapTags (which converts to the screen's
 * format and clips to the window's layer), and load pictures with datatypes. */
#include "../canvas.h"

#include <string.h>
#include <stdio.h>
#include <stdlib.h>
#include <exec/exec.h>
#include <intuition/intuition.h>
#include <graphics/blitattr.h>
#include <graphics/gfx.h>
#include <datatypes/pictureclass.h>
#include <proto/exec.h>
#include <proto/intuition.h>
#include <proto/graphics.h>
#include <proto/datatypes.h>
const char *bb_os4_path(const char *p, char *buf, size_t n);   /* "DH1:/x" -> "DH1:x" (platform.c) */

int canvas_blit_mode;
static const char *blit_info = "none yet";

const char *canvas_plat_blit_info(void) { return blit_info; }

/* mode 2: a 16-bit copy of the picture */
static uint16_t *buf16;
static int32_t buf16_n;

/* mode 3: an off-screen bitmap like the window's (a "friend"), filled through a lock */
static struct BitMap *friend_bm;
static int32_t friend_w, friend_h;
static struct BitMap *friend_of;

static void free_friend(void)
{
    if (friend_bm) IGraphics->FreeBitMap(friend_bm);
    friend_bm = NULL;
    friend_of = NULL;
}

static void cleanup(void)
{
    free_friend();
    free(buf16);
    buf16 = NULL;
}

static inline uint16_t rgb565(uint32_t p)
{
    return (uint16_t)(((p >> 8) & 0xF800u) | ((p >> 5) & 0x07E0u) | ((p >> 3) & 0x001Fu));
}

static int blit_friend(struct Window *win, const uint32_t *px, int32_t w, int32_t h, int32_t stride, int x, int y)
{
    static int registered;
    APTR lock;
    uint8 *base = NULL;
    uint32 bpr = 0, pf = 0;
    int32_t i, j, ok = 0;
    if (!registered) { atexit(cleanup); registered = 1; }
    if (!friend_bm || friend_w < w || friend_h < h || friend_of != win->RPort->BitMap) {
        free_friend();
        friend_bm = IGraphics->AllocBitMapTags(w, h, IGraphics->GetBitMapAttr(win->RPort->BitMap, BMA_DEPTH),
                                               BMATags_Friend, (uint32)win->RPort->BitMap, TAG_DONE);
        if (!friend_bm) { blit_info = "friend bitmap: AllocBitMap failed"; return 0; }
        friend_w = w;
        friend_h = h;
        friend_of = win->RPort->BitMap;
    }
    lock = IGraphics->LockBitMapTags(friend_bm, LBM_BaseAddress, (uint32)&base, LBM_BytesPerRow, (uint32)&bpr,
                                     LBM_PixelFormat, (uint32)&pf, TAG_DONE);
    if (!lock) { blit_info = "friend bitmap: LockBitMap failed"; return 0; }
    if (base && pf == PIXF_R5G6B5) {
        for (j = 0; j < h; j++) {
            const uint32_t *s = px + j * stride;
            uint16_t *d = (uint16_t *)(base + j * bpr);
            for (i = 0; i < w; i++) d[i] = rgb565(s[i]);
        }
        ok = 1;
        blit_info = "friend bitmap R5G6B5";
    } else if (base && pf == PIXF_R5G6B5PC) {
        for (j = 0; j < h; j++) {
            const uint32_t *s = px + j * stride;
            uint16_t *d = (uint16_t *)(base + j * bpr);
            for (i = 0; i < w; i++) d[i] = __builtin_bswap16(rgb565(s[i]));
        }
        ok = 1;
        blit_info = "friend bitmap R5G6B5PC";
    } else if (base && pf == PIXF_B8G8R8A8) {
        for (j = 0; j < h; j++) {
            const uint32_t *s = px + j * stride;
            uint32_t *d = (uint32_t *)(base + j * bpr);
            for (i = 0; i < w; i++) d[i] = __builtin_bswap32(s[i]);
        }
        ok = 1;
        blit_info = "friend bitmap B8G8R8A8";
    } else if (base && pf == PIXF_A8R8G8B8) {
        for (j = 0; j < h; j++) {          /* row by row: the guest's memcpy fails on big copies */
            const uint32_t *s = px + j * stride;
            uint32_t *d = (uint32_t *)(base + j * bpr);
            for (i = 0; i < w; i++) d[i] = s[i];
        }
        ok = 1;
        blit_info = "friend bitmap A8R8G8B8";
    }
    IGraphics->UnlockBitMap(lock);
    if (!ok) {
        static char info[64];
        snprintf(info, sizeof info, "friend bitmap pixel format %lu unsupported", (unsigned long)pf);
        blit_info = info;
        return 0;
    }
    IGraphics->BltBitMapRastPort(friend_bm, 0, 0, win->RPort, x, y, w, h, 0xC0);
    return 1;
}

/* Present enlarged s times straight into the friend bitmap: no scaled copy in between (at 2x a
 * 1.3 MB buffer written and read again every frame), and the per-frame loops in one function on
 * its own page. On the QEMU guest a frame's cost depends on how many distinct pages it touches
 * (its small TLB, docs/performance.md): the old path's time moved by 40% with the code's layout
 * (Orbit Docking's blit 5.6-7.9 ms for the same code). */
__attribute__((aligned(4096), noinline))
int canvas_plat_present_scaled(bb_ctl *ctl, const uint32_t *px, int32_t w, int32_t h, int32_t s)
{
    void *wp = NULL;
    int x, y, gw, gh;
    int32_t W = w * s, H = h * s, i, j, k;
    struct Window *win;
    APTR lock;
    uint8 *base = NULL;
    uint32 bpr = 0, pf = 0;
    if (s < 2 || (canvas_blit_mode != 0 && canvas_blit_mode != 3)) return -1;
    if (!bb_ctl_os_window(ctl, &wp, &x, &y, &gw, &gh)) return 0;
    win = (struct Window *)wp;
    if (W > gw || H > gh) return -1;            /* clipped: the general path */
    x += (gw - W) / 2;
    y += (gh - H) / 2;
    if (!friend_bm || friend_w < W || friend_h < H || friend_of != win->RPort->BitMap) {
        free_friend();
        friend_bm = IGraphics->AllocBitMapTags(W, H, IGraphics->GetBitMapAttr(win->RPort->BitMap, BMA_DEPTH),
                                               BMATags_Friend, (uint32)win->RPort->BitMap, TAG_DONE);
        if (!friend_bm) return -1;
        friend_w = W;
        friend_h = H;
        friend_of = win->RPort->BitMap;
    }
    lock = IGraphics->LockBitMapTags(friend_bm, LBM_BaseAddress, (uint32)&base, LBM_BytesPerRow, (uint32)&bpr,
                                     LBM_PixelFormat, (uint32)&pf, TAG_DONE);
    if (!lock) return -1;
    if (!base) { IGraphics->UnlockBitMap(lock); return -1; }
    if (pf == PIXF_R5G6B5 || pf == PIXF_R5G6B5PC) {
        int swap = pf == PIXF_R5G6B5PC;
        for (j = 0; j < h; j++) {
            const uint32_t *src = px + j * w;
            uint16_t *d = (uint16_t *)(base + (size_t)j * s * bpr), *d2;
            for (i = 0; i < w; i++) {
                uint16_t p = rgb565(src[i]);
                if (swap) p = __builtin_bswap16(p);
                for (k = 0; k < s; k++) d[i * s + k] = p;
            }
            for (k = 1; k < s; k++) {           /* the other rows: copies of the first */
                d2 = (uint16_t *)((uint8 *)d + (size_t)k * bpr);
                for (i = 0; i < W; i++) d2[i] = d[i];
            }
        }
        blit_info = swap ? "friend bitmap R5G6B5PC, scaled" : "friend bitmap R5G6B5, scaled";
    } else if (pf == PIXF_A8R8G8B8 || pf == PIXF_B8G8R8A8) {
        int swap = pf == PIXF_B8G8R8A8;
        for (j = 0; j < h; j++) {
            const uint32_t *src = px + j * w;
            uint32_t *d = (uint32_t *)(base + (size_t)j * s * bpr), *d2;
            for (i = 0; i < w; i++) {
                uint32_t p = swap ? __builtin_bswap32(src[i]) : src[i];
                for (k = 0; k < s; k++) d[i * s + k] = p;
            }
            for (k = 1; k < s; k++) {
                d2 = (uint32_t *)((uint8 *)d + (size_t)k * bpr);
                for (i = 0; i < W; i++) d2[i] = d[i];
            }
        }
        blit_info = swap ? "friend bitmap B8G8R8A8, scaled" : "friend bitmap A8R8G8B8, scaled";
    } else {
        IGraphics->UnlockBitMap(lock);
        return -1;
    }
    IGraphics->UnlockBitMap(lock);
    IGraphics->BltBitMapRastPort(friend_bm, 0, 0, win->RPort, x, y, W, H, 0xC0);
    return 0;
}

int canvas_plat_present(bb_ctl *ctl, const uint32_t *px, int32_t w, int32_t h, int32_t stride)
{
    void *wp = NULL;
    int x, y, gw, gh, mode = canvas_blit_mode;
    struct Window *win;
    if (!bb_ctl_os_window(ctl, &wp, &x, &y, &gw, &gh)) return 1;
    win = (struct Window *)wp;
    /* centred in the control's box when the layout made it bigger */
    if (gw > w) x += (gw - w) / 2;
    if (gh > h) y += (gh - h) / 2;
    if (w > gw) w = gw;
    if (h > gh) h = gh;
    if (w <= 0 || h <= 0) return 1;
    if ((mode == 0 || mode == 3) && blit_friend(win, px, w, h, stride, x, y)) return 0;
    if (mode == 2) {
        int32_t i, j;
        if (buf16_n < w * h) {
            free(buf16);
            buf16 = (uint16_t *)malloc((size_t)w * (size_t)h * 2);
            buf16_n = buf16 ? w * h : 0;
        }
        if (buf16) {
            for (j = 0; j < h; j++)
                for (i = 0; i < w; i++) buf16[j * w + i] = rgb565(px[j * stride + i]);
            IGraphics->BltBitMapTags(BLITA_Source, (uint32)buf16, BLITA_SrcType, BLITT_RGB16,
                                     BLITA_SrcBytesPerRow, (uint32)(w * 2), BLITA_SrcX, 0, BLITA_SrcY, 0,
                                     BLITA_Dest, (uint32)win->RPort, BLITA_DestType, BLITT_RASTPORT,
                                     BLITA_DestX, x, BLITA_DestY, y, BLITA_Width, w, BLITA_Height, h, TAG_DONE);
            blit_info = "RGB16 buffer";
            return 0;
        }
    }
    IGraphics->BltBitMapTags(BLITA_Source, (uint32)px, BLITA_SrcType, BLITT_ARGB32,
                             BLITA_SrcBytesPerRow, (uint32)(stride * 4), BLITA_SrcX, 0, BLITA_SrcY, 0,
                             BLITA_Dest, (uint32)win->RPort, BLITA_DestType, BLITT_RASTPORT,
                             BLITA_DestX, x, BLITA_DestY, y, BLITA_Width, w, BLITA_Height, h, TAG_DONE);
    if (mode != 3) blit_info = "ARGB32 buffer";
    return 0;
}

/* any picture datatypes can read (IFF ILBM, PNG, JPEG, ...), as 0xAARRGGBB */
uint32_t *canvas_plat_load_picture(const char *path, int32_t *w, int32_t *h)
{
    struct Library *dtbase = IExec->OpenLibrary("datatypes.library", 45);
    struct DataTypesIFace *idt = NULL;
    Object *o = NULL;
    uint32_t *px = NULL;
    struct BitMapHeader *bmh = NULL;
    if (!dtbase) return NULL;
    idt = (struct DataTypesIFace *)IExec->GetInterface(dtbase, "main", 1, NULL);
    char nb_[1024];
    if (idt) o = idt->NewDTObject((STRPTR)bb_os4_path(path, nb_, sizeof nb_), DTA_GroupID, GID_PICTURE, PDTA_DestMode, PMODE_V43,
                                  PDTA_Remap, FALSE, TAG_DONE);
    if (o && idt->GetDTAttrs(o, PDTA_BitMapHeader, (uint32)&bmh, TAG_DONE) && bmh && bmh->bmh_Width > 0) {
        int32_t ww = bmh->bmh_Width, hh = bmh->bmh_Height;
        px = (uint32_t *)malloc((size_t)ww * (size_t)hh * 4);
        if (px) {
            struct pdtBlitPixelArray bpa;
            memset(&bpa, 0, sizeof bpa);
            bpa.MethodID = PDTM_READPIXELARRAY;
            bpa.pbpa_PixelData = px;
            bpa.pbpa_PixelFormat = PBPAFMT_ARGB;
            bpa.pbpa_PixelArrayMod = (uint32)(ww * 4);
            bpa.pbpa_Left = 0;
            bpa.pbpa_Top = 0;
            bpa.pbpa_Width = (uint32)ww;
            bpa.pbpa_Height = (uint32)hh;
            if (idt->DoDTMethodA(o, NULL, NULL, (Msg)&bpa)) {
                *w = ww;
                *h = hh;
            } else {
                free(px);
                px = NULL;
            }
        }
    }
    if (o) idt->DisposeDTObject(o);
    if (idt) IExec->DropInterface((struct Interface *)idt);
    IExec->CloseLibrary(dtbase);
    return px;
}
