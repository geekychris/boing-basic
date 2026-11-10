/* canvas_posix.c - the Canvas platform layer without a GUI: canvases are off-screen only */
#include "../canvas.h"

int canvas_plat_present(bb_ctl *ctl, const uint32_t *px, int32_t w, int32_t h, int32_t stride)
{
    (void)ctl; (void)px; (void)w; (void)h; (void)stride;
    return 1;
}

int canvas_blit_mode;
const char *canvas_plat_blit_info(void) { return "off-screen"; }

uint32_t *canvas_plat_load_picture(const char *path, int32_t *w, int32_t *h)
{
    (void)path; (void)w; (void)h;
    return NULL;        /* canvas.c reads PPM itself */
}

int canvas_plat_present_scaled(bb_ctl *ctl, const uint32_t *px, int32_t w, int32_t h, int32_t s)
{
    (void)ctl; (void)px; (void)w; (void)h; (void)s;
    return -1;
}
