/* canvas.h - the Canvas control: a drawing surface for games and graphics (docs/graphics.md)
 *
 * The drawing happens in portable C on a chunky 32-bit buffer (0xAARRGGBB); the platform
 * layer only shows it (canvas_plat_present). A Canvas is either a control of a form (.afg kind
 * `canvas`, created by forms_rt.c) or off-screen (CreateObject("Boing.Canvas")), which works
 * on every platform and is what the tests use.
 */
#ifndef BB_CANVAS_H
#define BB_CANVAS_H

#include "boing.h"
#include "bb_forms.h"

typedef struct bb_canvas bb_canvas;

/* A canvas object (owned reference). ctl = the form control it shows in, NULL = off-screen. */
bb_obj *bb_canvas_new(int32_t w, int32_t h, bb_ctl *ctl);
int bb_is_canvas(const bb_obj *o);
/* Show the picture scaled up s times (the .afg's scale=, 1..4); the control is s times bigger. */
void bb_canvas_set_scale(bb_obj *o, int s);

/* For the forms layer: re-show a canvas control's picture (window opened / resized), and
 * forget the control when its form is freed. */
void bb_canvas_ctl_refresh(bb_ctl *ctl);
void bb_canvas_ctl_gone(bb_ctl *ctl);

/* For the forms layer: a key went down (down = 1) or up; key is the VB key code (vbKeyLeft...,
 * 256 + raw code for keys without one). Canvas.KeyDown(k) reads this state. */
void bb_canvas_key_event(int key, int down);
/* For the forms layer: the picture size and scale of a control's canvas (mouse events map
 * window pixels to canvas pixels). 0 if the control has no canvas. */
int bb_canvas_ctl_geometry(bb_ctl *ctl, int *w, int *h, int *scale);
/* For Clipboard.GetPicture: a picture copied into the back buffer (resized to w x h first);
 * 0 if o is not a canvas. */
int bb_canvas_put_picture(bb_obj *o, const uint32_t *px, int32_t w, int32_t h);

/* The pixels of a canvas's current target (back buffer or image): w x h, rows of w pixels,
 * 0xAARRGGBB. NULL if o is not a canvas. For runtime objects that draw into a canvas. */
uint32_t *bb_canvas_pixels(bb_obj *o, int32_t *w, int32_t *h);
/* Boing.Engine3D (engine3d.c, docs/engine3d.md) */
bb_obj *bb_engine3d_new(void);

/* The off-screen object registry (CreateObject). Raises 429 for unknown names. */
bb_obj *bb_create_object(const bb_str *progid);

/* ---- platform layer (os4/canvas_os4.c, posix/canvas_posix.c) ---- */

/* How Refresh gets the picture into the window (Canvas.BlitMode): 0 = the platform's best,
 * 1 = 32-bit ARGB blit, 2 = converted to 16-bit RGB first, 3 = through an off-screen bitmap
 * in the screen's own format. canvas_plat_blit_info() names the method used last. */
extern int canvas_blit_mode;
const char *canvas_plat_blit_info(void);

/* Show w x h pixels (rows of `stride` pixels, 0xAARRGGBB) in the control. Returns 0, or 1
 * when the control has no open window (nothing shown). */
int canvas_plat_present(bb_ctl *ctl, const uint32_t *px, int32_t w, int32_t h, int32_t stride);
/* Load a picture file (any format the platform knows) into a new malloc'd 0xAARRGGBB buffer;
 * NULL if the platform can't (the portable code then tries PPM itself). */
uint32_t *canvas_plat_load_picture(const char *path, int32_t *w, int32_t *h);

#endif
