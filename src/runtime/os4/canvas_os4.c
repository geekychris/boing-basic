/* canvas_os4.c - the Canvas platform layer on AmigaOS 4: blit the chunky ARGB32 picture into
 * the control's window with graphics.library's BltBitMapTags (which converts to the screen's
 * format and clips to the window's layer), and load pictures with datatypes. */
#include "../canvas.h"

#include <string.h>
#include <stdlib.h>
#include <exec/exec.h>
#include <intuition/intuition.h>
#include <graphics/blitattr.h>
#include <datatypes/pictureclass.h>
#include <proto/exec.h>
#include <proto/intuition.h>
#include <proto/graphics.h>
#include <proto/datatypes.h>

int canvas_plat_present(bb_ctl *ctl, const uint32_t *px, int32_t w, int32_t h, int32_t stride)
{
    void *wp = NULL;
    int x, y, gw, gh;
    struct Window *win;
    if (!bb_ctl_os_window(ctl, &wp, &x, &y, &gw, &gh)) return 1;
    win = (struct Window *)wp;
    /* centred in the control's box when the layout made it bigger */
    if (gw > w) x += (gw - w) / 2;
    if (gh > h) y += (gh - h) / 2;
    if (w > gw) w = gw;
    if (h > gh) h = gh;
    if (w <= 0 || h <= 0) return 1;
    IGraphics->BltBitMapTags(BLITA_Source, (uint32)px, BLITA_SrcType, BLITT_ARGB32,
                             BLITA_SrcBytesPerRow, (uint32)(stride * 4), BLITA_SrcX, 0, BLITA_SrcY, 0,
                             BLITA_Dest, (uint32)win->RPort, BLITA_DestType, BLITT_RASTPORT,
                             BLITA_DestX, x, BLITA_DestY, y, BLITA_Width, w, BLITA_Height, h, TAG_DONE);
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
    if (idt) o = idt->NewDTObject((STRPTR)path, DTA_GroupID, GID_PICTURE, PDTA_DestMode, PMODE_V43,
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
