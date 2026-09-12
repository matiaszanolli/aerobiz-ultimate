/* ==========================================================================
 * Aerobiz Ultimate -- U-002: put something on the 32X layer
 *
 * First use of the bitmap layer. Exercises the four things every later M4
 * item depends on: the line table, the palette, the FM handover and the frame
 * buffer swap.
 *
 * Everything here is cache-through. docs/32x-hardware-manual.md section 3.4
 * forbids cached access to system and VDP registers, and the frame buffer is
 * written by the VDP behind our back, so it may not be cached either.
 *
 * The 68000 must have handed us FM = 1 before any of this runs.
 * ========================================================================== */

#define VDP_BITMAP   (*(volatile unsigned short *)0x20004100)
#define VDP_FBCTL    (*(volatile unsigned short *)0x2000410A)
#define PALETTE      ((volatile unsigned short *)0x20004200)
#define FRAMEBUFFER  ((volatile unsigned short *)0x24000000)

#define FBCTL_VBLK   0x8000u
#define FBCTL_FS     0x0001u

/* Packed pixel mode: one byte per pixel, so 320 pixels is 160 words, and the
 * line table is the first 256 words of the buffer (manual 3.3).  Pixel data
 * therefore starts at word 256. */
#define LINE_TABLE_WORDS  256u
#define WORDS_PER_LINE    160u
#define VISIBLE_LINES     224u

static void fb_wait_vblank(void)
{
    while ((VDP_FBCTL & FBCTL_VBLK) == 0u) { }
}

/* A palette that makes a wrong line table or a wrong stride obvious: red
 * ramps along the low nibble of the index, green along the high nibble, so a
 * correct pattern is a smooth two-axis gradient and a broken one is noise. */
static void fb_palette(void)
{
    unsigned int i;

    PALETTE[0] = 0u;                                  /* index 0 stays black */
    for (i = 1u; i < 256u; i++) {
        unsigned int r = (i & 0x0Fu) << 1;            /* 0..30 */
        unsigned int g = ((i >> 4) & 0x0Fu) << 1;
        unsigned int b = 6u;
        PALETTE[i] = (unsigned short)((b << 10) | (g << 5) | r);
    }
}

/* Fill the line table and the pixels of whichever buffer we currently hold.
 *
 * Only word writes are used.  A byte write to the frame buffer cannot store
 * zero (manual :1162, and KNOWN_ISSUES), which would silently leave holes in
 * any pattern containing index 0; writing whole words sidesteps it entirely.
 */
static void fb_paint(void)
{
    unsigned int line, w;

    for (line = 0u; line < LINE_TABLE_WORDS; line++) {
        unsigned int src = (line < VISIBLE_LINES) ? line : (VISIBLE_LINES - 1u);
        FRAMEBUFFER[line] =
            (unsigned short)(LINE_TABLE_WORDS + src * WORDS_PER_LINE);
    }

    for (line = 0u; line < VISIBLE_LINES; line++) {
        volatile unsigned short *row =
            FRAMEBUFFER + LINE_TABLE_WORDS + line * WORDS_PER_LINE;
        unsigned int band = (line >> 4) << 4;         /* green axis */
        for (w = 0u; w < WORDS_PER_LINE; w++) {
            unsigned int x  = w << 1;
            unsigned int hi = 1u + (((x)      >> 4) & 0x0Fu) + band;
            unsigned int lo = 1u + (((x + 1u) >> 4) & 0x0Fu) + band;
            row[w] = (unsigned short)((hi << 8) | lo);
        }
    }
}

/* Paint both buffers.  Only the back buffer is writable, so this swaps and
 * repeats: the pattern is then stable whichever side the VDP ends up
 * displaying, and the result does not depend on which buffer we started with.
 *
 * Manual :1059 -- the FS write is only honoured at the next V Blank, and the
 * frame buffer must not be touched until VBLK = 1 or FS has actually changed.
 */
void sh2_fb_test(void)
{
    unsigned int pass;

    fb_palette();

    for (pass = 0u; pass < 2u; pass++) {
        fb_wait_vblank();
        fb_paint();
        VDP_FBCTL = (unsigned short)((VDP_FBCTL & FBCTL_FS) ^ FBCTL_FS);
        fb_wait_vblank();
    }
}

/* ==========================================================================
 * U-031: draw the world map from cartridge ROM.
 *
 * The asset is built by tools/make_map_asset.py and lives at cartridge offset
 * MAP_ROM_OFFSET, which the SH2 reaches through the cache-through cartridge
 * window at 0x22000000. Its layout is exactly what we need to write, so this
 * is a copy and not an unpack:
 *
 *     +0x0000  256 words  palette, already BGR555
 *     +0x0200  224 * 320  packed pixels, one byte each, rows already padded
 *                         to the full 320 the VDP displays (manual 3.3)
 *
 * The cartridge is unreadable while RV = 1 (manual 3.5). RV is 0 here -- the
 * DMA thunk is the only thing that raises it, and only for the length of a
 * transfer with interrupts masked -- but anything that starts doing SH2 work
 * during a Genesis DMA will have to interlock.
 * ========================================================================== */

#define CART_ROM        ((volatile const unsigned char *)0x22000000)
#define MAP_ROM_OFFSET  0x00020000u

static void fb_paint_map(void)
{
    const volatile unsigned short *pal =
        (const volatile unsigned short *)(CART_ROM + MAP_ROM_OFFSET);
    const volatile unsigned short *src =
        (const volatile unsigned short *)(CART_ROM + MAP_ROM_OFFSET + 512u);
    unsigned int line, w, i;

    for (i = 0u; i < 256u; i++)
        PALETTE[i] = pal[i];

    for (line = 0u; line < LINE_TABLE_WORDS; line++) {
        unsigned int s = (line < VISIBLE_LINES) ? line : (VISIBLE_LINES - 1u);
        FRAMEBUFFER[line] =
            (unsigned short)(LINE_TABLE_WORDS + s * WORDS_PER_LINE);
    }

    /* Word writes only: a byte write to the frame buffer cannot store zero,
     * and index 0 is exactly what the 64-pixel pad to the right of the map
     * is made of. */
    for (line = 0u; line < VISIBLE_LINES; line++) {
        volatile unsigned short *dst =
            FRAMEBUFFER + LINE_TABLE_WORDS + line * WORDS_PER_LINE;
        const volatile unsigned short *row = src + line * WORDS_PER_LINE;
        for (w = 0u; w < WORDS_PER_LINE; w++)
            dst[w] = row[w];
    }
}

void sh2_map_test(void)
{
    unsigned int pass;

    /* Both buffers, for the same reason as sh2_fb_test: only the back buffer
     * is writable and an FS write lands at the next V Blank, so painting once
     * would leave the result depending on which side the VDP is showing. */
    for (pass = 0u; pass < 2u; pass++) {
        fb_wait_vblank();
        fb_paint_map();
        VDP_FBCTL = (unsigned short)((VDP_FBCTL & FBCTL_FS) ^ FBCTL_FS);
        fb_wait_vblank();
    }
}

/* ==========================================================================
 * U-035: map scaling (zoom).
 *
 * The 32X has no hardware scaler, so this is SH2 software rasterization --
 * but only on one axis.  The frame buffer opens with a 256-word line table
 * whose entries are the word address of each display line's pixel data
 * (docs/32x-hardware-manual.md:1204).  Nothing says two display lines may not
 * name the *same* address, and that is the whole trick:
 *
 *   - Vertical scale costs 256 word writes per frame, whatever the factor.
 *     A source row that covers several display lines is rasterized once and
 *     pointed at repeatedly.
 *   - Horizontal scale is a genuine per-pixel inner loop, because line-table
 *     addresses are word units -- 2-dot granularity -- and SFT only recovers
 *     1-dot *panning*, not scaling (manual:1238).
 *
 * So the cost of a frame is (distinct source rows) x 160 word writes, and the
 * worst case is exactly zoom = 1.0, where every display line needs its own
 * source row.  That is what sh2_zoom_test measures before it animates.
 *
 * Two things are deliberately arranged to make the result checkable:
 *
 *   - Source is the whole 320x224 asset, not the 256x176 world inside it, so
 *     zoom = 1.0 is pixel-identical to U-031's straight blit and can be
 *     diffed against it frame for frame.
 *   - The window is clamped to stay inside the source, so no sample is ever
 *     out of bounds and the inner loop needs no per-pixel test.  Because a
 *     step of 1.0 makes the window exactly the source, this costs no reach:
 *     it only forbids zooming *out* past the full map, which has nothing to
 *     show anyway.
 *
 * Only word writes touch the frame buffer: a byte write there cannot store
 * zero (manual:1162) and index 0 is most of the border.
 * ========================================================================== */

#define SRC_W        320u
#define SRC_H        224u
#define FP_ONE       0x10000uL          /* 16.16 -- one source pixel per dot */

/* The map is pulled out of the cartridge once and rasterized from SDRAM.
 * Reading source pixels straight from the 0x22000000 window would put a slow
 * cartridge access in the inner loop, and horizontal magnification reads the
 * same source pixel several times over. */
static unsigned char map_ram[SRC_H * SRC_W];

/* Incremented by vint_handler in main.s.  The SH7604 free-running timer is off
 * limits (manual 5.3), so V-Blanks are the clock: they are the unit the answer
 * is wanted in anyway -- "does a full-screen scale fit in one frame". */
extern volatile unsigned long sh2_vint_count;

/* Results, in SDRAM so `read master <addr>` can sample them; a value left only
 * in a comm register reads back as zero from outside (see rpc.c).
 *
 * One number per zoom level, because the cost is not flat: magnification cuts
 * the number of source rows and so the number of rasterized rows, while the
 * per-row cost stays at 320 dots whatever the factor. */
volatile unsigned long sh2_zoom_blits;
volatile unsigned long sh2_zoom_frames[3];
volatile unsigned long sh2_zoom_rows[3];

static void map_load(void)
{
    const volatile unsigned short *pal =
        (const volatile unsigned short *)(CART_ROM + MAP_ROM_OFFSET);
    const volatile unsigned short *src =
        (const volatile unsigned short *)(CART_ROM + MAP_ROM_OFFSET + 512u);
    unsigned short *dst = (unsigned short *)map_ram;
    unsigned int i;

    for (i = 0u; i < 256u; i++)
        PALETTE[i] = pal[i];

    for (i = 0u; i < (SRC_H * SRC_W) / 2u; i++)
        dst[i] = src[i];
}

/* One display row.  Two source samples per word, because packed-pixel mode
 * puts two dots in a word and the frame buffer wants word writes. */
static void scale_row(const unsigned char *src, volatile unsigned short *dst,
                      unsigned long u, unsigned long ustep)
{
    unsigned int w;

    for (w = 0u; w < WORDS_PER_LINE; w++) {
        unsigned int hi = src[u >> 16]; u += ustep;
        unsigned int lo = src[u >> 16]; u += ustep;
        dst[w] = (unsigned short)((hi << 8) | lo);
    }
}

static void fb_draw_airports(unsigned long u0, unsigned long v0,
                             unsigned long step, unsigned int slots);
void fb_draw_overlay(unsigned long u0, unsigned long v0, unsigned long step,
                     unsigned int slots);
#define PAL_ARC        252u
#define PAL_MAJOR      250u
#define PAL_MINOR      251u

/* The window fb_blit_scaled last used, so the airport overlay lands in the
 * same coordinate space without recomputing the clamps. */
static unsigned long fb_u0, fb_v0, fb_step;
static unsigned int  fb_slots;

/* step is 16.16 source pixels per display dot: FP_ONE is 1:1, FP_ONE/2 is 2x
 * magnification.  (cx, cy) is the source pixel held at the centre of the
 * screen, clamped so the window stays inside the source.
 *
 * Returns the number of source rows actually rasterized, which is the cost. */
static unsigned int fb_blit_scaled(unsigned int cx, unsigned int cy,
                                   unsigned long step)
{
    unsigned long span_x = step * 320uL;         /* window size, 16.16 */
    unsigned long span_y = step * VISIBLE_LINES;
    unsigned long u0, v0;
    unsigned int y, slots = 0u, prev = 0xFFFFu;

    /* Clamp rather than test per pixel.  step <= FP_ONE keeps both spans no
     * larger than the source, so a valid placement always exists. */
    u0 = ((unsigned long)cx << 16) - (span_x >> 1);
    if ((long)u0 < 0L)
        u0 = 0uL;
    else if (u0 + span_x > ((unsigned long)SRC_W << 16))
        u0 = ((unsigned long)SRC_W << 16) - span_x;

    v0 = ((unsigned long)cy << 16) - (span_y >> 1);
    if ((long)v0 < 0L)
        v0 = 0uL;
    else if (v0 + span_y > ((unsigned long)SRC_H << 16))
        v0 = ((unsigned long)SRC_H << 16) - span_y;

    for (y = 0u; y < VISIBLE_LINES; y++) {
        unsigned int sy = (unsigned int)((v0 + step * y) >> 16);

        /* A new source row gets rasterized into the next free slot; a repeat
         * of the previous one just aims another line-table entry at the slot
         * already holding it.  This is where vertical magnification becomes
         * free. */
        if (sy != prev) {
            scale_row(map_ram + sy * SRC_W,
                      FRAMEBUFFER + LINE_TABLE_WORDS + slots * WORDS_PER_LINE,
                      u0, step);
            prev = sy;
            slots++;
        }
        FRAMEBUFFER[y] = (unsigned short)(LINE_TABLE_WORDS
                                          + (slots - 1u) * WORDS_PER_LINE);
    }

    /* Lines 224-255 are not displayed, but the table is 256 entries and a
     * stale entry could aim one at memory we never wrote. */
    for (y = VISIBLE_LINES; y < LINE_TABLE_WORDS; y++)
        FRAMEBUFFER[y] = FRAMEBUFFER[VISIBLE_LINES - 1u];

    fb_u0 = u0; fb_v0 = v0; fb_step = step; fb_slots = slots;
    return slots;
}

/* Centre of the world map proper -- the asset is 256 wide inside a 320 frame,
 * so this is not the centre of the screen. */
#define ZOOM_CX      128u
#define ZOOM_CY       88u

#define ZOOM_MIN     (FP_ONE / 4uL)     /* 4x magnification */
#define ZOOM_STEP    0x400uL

/* How many worst-case blits the benchmark runs.  Enough that the V-Blank
 * quantisation is a rounding error rather than the measurement. */
#define BENCH_BLITS  32u

void sh2_zoom_test(void)
{
    unsigned long step = FP_ONE;
    long dir = -(long)ZOOM_STEP;
    unsigned long t0;
    unsigned int i;

    map_load();
    PALETTE[PAL_MAJOR] = 0x001Fu;       /* red   -- major airports */
    PALETTE[PAL_MINOR] = 0x03FFu;       /* yellow -- secondaries */
    PALETTE[PAL_ARC]   = 0x7FFFu;       /* white  -- route arcs */

    /* 1:1 first, which is the worst case: it needs a distinct source row per
     * display line, so nothing the animation does afterwards costs more.
     * No buffer flip and no V-Blank wait -- the point is the raw blit rate. */
    for (i = 0u; i < 3u; i++) {
        unsigned long s = FP_ONE >> i;          /* 1x, 2x, 4x */
        unsigned int j, rows = 0u;

        t0 = sh2_vint_count;
        for (j = 0u; j < BENCH_BLITS; j++)
            rows = fb_blit_scaled(ZOOM_CX, ZOOM_CY, s);
        sh2_zoom_frames[i] = sh2_vint_count - t0;
        sh2_zoom_rows[i]   = rows;
    }
    sh2_zoom_blits = BENCH_BLITS;

    for (;;) {
        fb_wait_vblank();
        (void)fb_blit_scaled(ZOOM_CX, ZOOM_CY, step);
        fb_draw_overlay(fb_u0, fb_v0, fb_step, fb_slots);
        VDP_FBCTL = (unsigned short)((VDP_FBCTL & FBCTL_FS) ^ FBCTL_FS);

        step = (unsigned long)((long)step + dir);
        if (step <= ZOOM_MIN) {
            step = ZOOM_MIN;
            dir = (long)ZOOM_STEP;
        } else if (step >= FP_ONE) {
            step = FP_ONE;
            dir = -(long)ZOOM_STEP;
        }
    }
}
/* ==========================================================================
 * U-077: level of detail -- the 32 major airports always, the 57 secondaries
 * only once the map is zoomed in.
 *
 * This is what U-035's zoom is *for*. At 4x each map pixel is a 4x4 block and
 * the terrain has no more detail to give, so the reward for zooming has to be
 * information the zoomed-out view could not fit.
 *
 * No new data is needed, which is the pleasant part: the tier is already the
 * index. Cities 0-31 are the majors and 32-88 the secondaries, and the
 * coordinate table at Genesis $05E948 is two bytes per city, x then y, in map
 * pixels -- exactly the space the rasterizer works in. `DrawRouteLines`
 * ($0098D2) reads it the same way to place route endpoints.
 *
 * Markers scale with the map rather than staying a constant size on screen,
 * and that is a property of the line-table trick rather than a choice: display
 * lines that share a slot share its pixels, so anything drawn into a slot is
 * repeated by however many lines point at it. Breaking that would mean giving
 * every display line its own row and paying full price for the vertical axis.
 * U-032's arcs and U-033's aircraft inherit the same constraint.
 * ========================================================================== */

/* Cartridge offset of the coordinate table: the game half lives at cartridge
 * $100000, so the Genesis address $05E948 lands here. Cached alias, since it
 * is read repeatedly. */
#define CITY_TABLE     ((const unsigned char *)0x0215E948u)
#define CITY_COUNT     89u
#define CITY_MAJOR     32u          /* U-070 wants this as CITY_MAJOR_COUNT */

/* Palette entries the asset does not use: declared with the forward
 * declaration above, where sh2_zoom_test can see them. */

/* Secondaries appear once a source pixel covers at least two dots. Discrete,
 * not a fade: at this scale a pin either reads or it does not, and the
 * threshold is a single comparison. */
#define LOD_STEP       (FP_ONE / 2uL)

static void fb_mark(unsigned int slot, unsigned int col, unsigned int w,
                    unsigned int colour)
{
    volatile unsigned char *row = (volatile unsigned char *)
        (FRAMEBUFFER + LINE_TABLE_WORDS + slot * WORDS_PER_LINE);
    unsigned int i;

    /* Byte writes are safe here where they are not for the map: the manual's
     * restriction is that a byte write cannot store *zero*, and a marker
     * colour never is. */
    for (i = 0u; i < w; i++)
        if (col + i < 320u)
            row[col + i] = (unsigned char)colour;
}

/* Draw the airports over an already-rasterized frame.  u0/v0/step describe the
 * same window fb_blit_scaled used, and slots were allocated in source-row
 * order from v0, so a source row's slot is just its offset from the first. */
static void fb_draw_airports(unsigned long u0, unsigned long v0,
                             unsigned long step, unsigned int slots)
{
    const unsigned char *city = CITY_TABLE;
    unsigned long recip = 0x01000000uL / step;   /* one divide, not 178 */
    unsigned int first_row = (unsigned int)(v0 >> 16);
    unsigned int show_minor = (step <= LOD_STEP);
    unsigned int i;

    for (i = 0u; i < CITY_COUNT; i++) {
        unsigned int cx = city[i * 2u];
        unsigned int cy = city[i * 2u + 1u];
        unsigned long ux, vy;
        unsigned int col, slot, major;

        major = (i < CITY_MAJOR);
        if (!major && !show_minor)
            continue;

        ux = ((unsigned long)cx << 16);
        vy = ((unsigned long)cy << 16);
        if (ux < u0 || vy < v0)
            continue;
        col  = (unsigned int)(((ux - u0) >> 8) * recip >> 16);
        slot = cy - first_row;
        if (col >= 320u || slot >= slots)
            continue;

        fb_mark(slot, col, major ? 3u : 2u, major ? PAL_MAJOR : PAL_MINOR);
    }
}
/* ==========================================================================
 * U-037: affine transform (rotate + scale) on the SH2.
 *
 * U-035's scaler is axis-aligned, and cheap because of it: the vertical axis
 * costs nothing because display lines share line-table slots. Rotation breaks
 * that. Once the source Y varies *along* a scanline, no two display lines hold
 * the same pixels, so every one needs its own row and the vertical axis costs
 * full price. An affine frame is therefore always the 1:1 worst case U-035
 * measured -- 2.13 frames full-screen -- and the way to afford it is to
 * transform a region rather than the screen.
 *
 * The mapping is the standard one, everything 16.16:
 *
 *     u = u0 + x*dudx + y*dudy
 *     v = v0 + x*dvdx + y*dvdy
 *
 * so a rotation by t at scale s is dudx = cos(t)/s, dvdx = sin(t)/s,
 * dudy = -sin(t)/s, dvdy = cos(t)/s.
 *
 * Correctness is checkable rather than a matter of opinion: with dudx = dvdy =
 * 1.0 and the cross terms zero, the output must be pixel-identical to the 1:1
 * blit -- which is itself already known identical to U-031's straight copy.
 * That is what sh2_affine_test asserts before anything is rotated.
 * ========================================================================== */

/* Per display line, rather than per source row: no slot sharing is possible. */
static void fb_affine_line(volatile unsigned short *dst,
                           const unsigned char *src,
                           long u, long v, long dudx, long dvdx)
{
    unsigned int w;

    for (w = 0u; w < WORDS_PER_LINE; w++) {
        unsigned int hi, lo, su, sv;

        su = (unsigned int)(u >> 16); sv = (unsigned int)(v >> 16);
        hi = (su < SRC_W && sv < SRC_H) ? src[sv * SRC_W + su] : 0u;
        u += dudx; v += dvdx;

        su = (unsigned int)(u >> 16); sv = (unsigned int)(v >> 16);
        lo = (su < SRC_W && sv < SRC_H) ? src[sv * SRC_W + su] : 0u;
        u += dudx; v += dvdx;

        dst[w] = (unsigned short)((hi << 8) | lo);
    }
}

static void fb_blit_affine(long u0, long v0,
                           long dudx, long dudy, long dvdx, long dvdy)
{
    unsigned int y;

    /* Identity line table: one frame-buffer row per display line. */
    for (y = 0u; y < LINE_TABLE_WORDS; y++) {
        unsigned int s = (y < VISIBLE_LINES) ? y : (VISIBLE_LINES - 1u);
        FRAMEBUFFER[y] =
            (unsigned short)(LINE_TABLE_WORDS + s * WORDS_PER_LINE);
    }

    for (y = 0u; y < VISIBLE_LINES; y++)
        fb_affine_line(FRAMEBUFFER + LINE_TABLE_WORDS + y * WORDS_PER_LINE,
                       map_ram,
                       u0 + (long)y * dudy, v0 + (long)y * dvdy, dudx, dvdx);
}

/* Q15 sine, 256 steps to the turn.  Generated, not derived at runtime: the
 * SH2 has no FPU and a table this small costs 512 bytes of an image that is
 * currently 4 KB. */
static const short fb_sin[256] = {
         0,    804,   1608,   2410,   3212,   4011,   4808,   5602,
      6393,   7179,   7962,   8739,   9512,  10278,  11039,  11793,
     12539,  13279,  14010,  14732,  15446,  16151,  16846,  17530,
     18204,  18868,  19519,  20159,  20787,  21403,  22005,  22594,
     23170,  23731,  24279,  24811,  25329,  25832,  26319,  26790,
     27245,  27683,  28105,  28510,  28898,  29268,  29621,  29956,
     30273,  30571,  30852,  31113,  31356,  31580,  31785,  31971,
     32137,  32285,  32412,  32521,  32609,  32678,  32728,  32757,
     32767,  32757,  32728,  32678,  32609,  32521,  32412,  32285,
     32137,  31971,  31785,  31580,  31356,  31113,  30852,  30571,
     30273,  29956,  29621,  29268,  28898,  28510,  28105,  27683,
     27245,  26790,  26319,  25832,  25329,  24811,  24279,  23731,
     23170,  22594,  22005,  21403,  20787,  20159,  19519,  18868,
     18204,  17530,  16846,  16151,  15446,  14732,  14010,  13279,
     12539,  11793,  11039,  10278,   9512,   8739,   7962,   7179,
      6393,   5602,   4808,   4011,   3212,   2410,   1608,    804,
         0,   -804,  -1608,  -2410,  -3212,  -4011,  -4808,  -5602,
     -6393,  -7179,  -7962,  -8739,  -9512, -10278, -11039, -11793,
    -12539, -13279, -14010, -14732, -15446, -16151, -16846, -17530,
    -18204, -18868, -19519, -20159, -20787, -21403, -22005, -22594,
    -23170, -23731, -24279, -24811, -25329, -25832, -26319, -26790,
    -27245, -27683, -28105, -28510, -28898, -29268, -29621, -29956,
    -30273, -30571, -30852, -31113, -31356, -31580, -31785, -31971,
    -32137, -32285, -32412, -32521, -32609, -32678, -32728, -32757,
    -32767, -32757, -32728, -32678, -32609, -32521, -32412, -32285,
    -32137, -31971, -31785, -31580, -31356, -31113, -30852, -30571,
    -30273, -29956, -29621, -29268, -28898, -28510, -28105, -27683,
    -27245, -26790, -26319, -25832, -25329, -24811, -24279, -23731,
    -23170, -22594, -22005, -21403, -20787, -20159, -19519, -18868,
    -18204, -17530, -16846, -16151, -15446, -14732, -14010, -13279,
    -12539, -11793, -11039, -10278,  -9512,  -8739,  -7962,  -7179,
     -6393,  -5602,  -4808,  -4011,  -3212,  -2410,  -1608,   -804,
};

#define FB_COS(a)  fb_sin[((a) + 64u) & 255u]
#define FB_SIN(a)  fb_sin[(a) & 255u]

extern volatile unsigned long sh2_vint_count;

volatile unsigned long sh2_aff_sum_scaled;   /* 1:1 blit, for comparison */
volatile unsigned long sh2_aff_sum_identity; /* affine with the identity matrix */
volatile unsigned long sh2_aff_frames;
volatile unsigned long sh2_aff_blits;
volatile unsigned long sh2_aff_done;

/* FNV-1a over the visible frame buffer.  Reading it back is slow -- 5-12 wait
 * states per access (manual 4.1) -- but this runs twice, not per frame. */
static unsigned long fb_checksum(void)
{
    const volatile unsigned short *p = FRAMEBUFFER + LINE_TABLE_WORDS;
    unsigned long h = 2166136261uL;
    unsigned int i, n = VISIBLE_LINES * WORDS_PER_LINE;

    for (i = 0u; i < n; i++) {
        unsigned short w = p[i];
        h ^= (unsigned char)(w >> 8); h *= 16777619uL;
        h ^= (unsigned char)w;        h *= 16777619uL;
    }
    return h;
}

#define AFF_BLITS  8u

void sh2_affine_test(void)
{
    unsigned long t0;
    unsigned int i;
    unsigned char angle = 0u;

    map_load();

    /* The identity assertion, before anything is rotated. */
    (void)fb_blit_scaled(ZOOM_CX, ZOOM_CY, FP_ONE);
    sh2_aff_sum_scaled = fb_checksum();

    fb_blit_affine(0L, 0L, 0x10000L, 0L, 0L, 0x10000L);
    sh2_aff_sum_identity = fb_checksum();

    /* Cost of a full-screen affine frame, which is the worst case by
     * construction -- there is no slot sharing to reduce it. */
    t0 = sh2_vint_count;
    for (i = 0u; i < AFF_BLITS; i++)
        fb_blit_affine(0L, 0L, 0x10000L, 0L, 0L, 0x10000L);
    sh2_aff_frames = sh2_vint_count - t0;
    sh2_aff_blits = AFF_BLITS;
    sh2_aff_done = 0x7D07E;

    /* Then rotate about the centre of the map, forever. */
    for (;;) {
        long c = FB_COS(angle), s = FB_SIN(angle);
        long dudx =  (c << 1), dvdx =  (s << 1);   /* Q15 -> 16.16 */
        long dudy = -(s << 1), dvdy =  (c << 1);
        long cx = (long)ZOOM_CX << 16, cy = (long)ZOOM_CY << 16;

        fb_wait_vblank();
        fb_blit_affine(cx - 160L * dudx - 112L * dudy,
                       cy - 160L * dvdx - 112L * dvdy,
                       dudx, dudy, dvdx, dvdy);
        VDP_FBCTL = (unsigned short)((VDP_FBCTL & FBCTL_FS) ^ FBCTL_FS);
        angle++;
    }
}

/* ==========================================================================
 * U-032: great-circle route arcs.
 *
 * A route between two cities is a great circle, and on the equirectangular
 * map that is a curve, not the straight line the Genesis renderer draws.
 *
 * The projection had to be measured before any of this could be written. A
 * least-squares fit of 34 cities whose real positions are known independently:
 *
 *     x = 0.5972 * longitude + 35.13     mean error 3.5 px, max 7.7
 *     y = -0.7854 * latitude  + 92.25     mean error 4.4 px, max 11.2
 *
 * so the map is equirectangular -- Mercator fits no better, 4.1 px against
 * 4.4 -- at about 215 px to a full turn, with a mid-Atlantic seam. The
 * residual is hand-drawn art, not projection error, and it is why arcs are
 * **anchored**: the endpoints are forced onto the table coordinates and the
 * error distributed along the curve, so an arc always touches its cities even
 * though the projection would miss them by up to 8 px.
 *
 * A quadratic Bezier through the endpoints and the true spherical midpoint was
 * measured as a cheaper substitute and rejected: median deviation 1.8 px but
 * 90th percentile 15.9 and worst case 87 (Baghdad to Los Angeles). Long routes
 * need the real thing, so the arc is sampled by spherical interpolation and
 * the inverse projection is done properly, which is what these tables are for.
 *
 * Angle unit throughout is 1/256 turn in Q8, so 90 degrees is 64*256 = 16384.
 * ========================================================================== */

static const short fb_atan[257] = {
         0,     41,     81,    122,    163,    204,    244,    285,
       326,    367,    407,    448,    489,    529,    570,    610,
       651,    692,    732,    773,    813,    854,    894,    935,
       975,   1015,   1056,   1096,   1136,   1177,   1217,   1257,
      1297,   1337,   1377,   1417,   1457,   1497,   1537,   1577,
      1617,   1656,   1696,   1736,   1775,   1815,   1854,   1894,
      1933,   1973,   2012,   2051,   2090,   2129,   2168,   2207,
      2246,   2285,   2324,   2363,   2401,   2440,   2478,   2517,
      2555,   2594,   2632,   2670,   2708,   2746,   2784,   2822,
      2860,   2897,   2935,   2973,   3010,   3047,   3085,   3122,
      3159,   3196,   3233,   3270,   3307,   3344,   3380,   3417,
      3453,   3490,   3526,   3562,   3599,   3635,   3670,   3706,
      3742,   3778,   3813,   3849,   3884,   3920,   3955,   3990,
      4025,   4060,   4095,   4129,   4164,   4199,   4233,   4267,
      4302,   4336,   4370,   4404,   4438,   4471,   4505,   4539,
      4572,   4605,   4639,   4672,   4705,   4738,   4771,   4803,
      4836,   4869,   4901,   4933,   4966,   4998,   5030,   5062,
      5094,   5125,   5157,   5188,   5220,   5251,   5282,   5313,
      5344,   5375,   5406,   5437,   5467,   5498,   5528,   5559,
      5589,   5619,   5649,   5679,   5708,   5738,   5768,   5797,
      5826,   5856,   5885,   5914,   5943,   5972,   6000,   6029,
      6058,   6086,   6114,   6142,   6171,   6199,   6227,   6254,
      6282,   6310,   6337,   6365,   6392,   6419,   6446,   6473,
      6500,   6527,   6554,   6580,   6607,   6633,   6660,   6686,
      6712,   6738,   6764,   6790,   6815,   6841,   6867,   6892,
      6917,   6943,   6968,   6993,   7018,   7043,   7068,   7092,
      7117,   7141,   7166,   7190,   7214,   7238,   7262,   7286,
      7310,   7334,   7358,   7381,   7405,   7428,   7451,   7475,
      7498,   7521,   7544,   7566,   7589,   7612,   7635,   7657,
      7679,   7702,   7724,   7746,   7768,   7790,   7812,   7834,
      7856,   7877,   7899,   7920,   7942,   7963,   7984,   8005,
      8026,   8047,   8068,   8089,   8110,   8131,   8151,   8172,
      8192,
};

static const short fb_asin_t[257] = {
    -16384, -15079, -14538, -14121, -13770, -13459, -13178, -12919,
    -12677, -12449, -12234, -12028, -11831, -11642, -11460, -11284,
    -11113, -10947, -10785, -10628, -10475, -10324, -10177, -10034,
     -9892,  -9754,  -9618,  -9484,  -9353,  -9223,  -9095,  -8970,
     -8846,  -8723,  -8602,  -8483,  -8365,  -8249,  -8133,  -8019,
     -7907,  -7795,  -7684,  -7575,  -7466,  -7359,  -7252,  -7147,
     -7042,  -6938,  -6835,  -6732,  -6631,  -6530,  -6430,  -6330,
     -6231,  -6133,  -6035,  -5938,  -5842,  -5746,  -5651,  -5556,
     -5461,  -5367,  -5274,  -5181,  -5089,  -4997,  -4905,  -4814,
     -4723,  -4633,  -4543,  -4453,  -4364,  -4275,  -4186,  -4097,
     -4009,  -3922,  -3834,  -3747,  -3660,  -3573,  -3487,  -3401,
     -3315,  -3229,  -3144,  -3059,  -2974,  -2889,  -2804,  -2720,
     -2636,  -2551,  -2468,  -2384,  -2300,  -2217,  -2134,  -2050,
     -1967,  -1884,  -1802,  -1719,  -1636,  -1554,  -1472,  -1389,
     -1307,  -1225,  -1143,  -1061,   -979,   -897,   -816,   -734,
      -652,   -571,   -489,   -408,   -326,   -244,   -163,    -81,
         0,     81,    163,    244,    326,    408,    489,    571,
       652,    734,    816,    897,    979,   1061,   1143,   1225,
      1307,   1389,   1472,   1554,   1636,   1719,   1802,   1884,
      1967,   2050,   2134,   2217,   2300,   2384,   2468,   2551,
      2636,   2720,   2804,   2889,   2974,   3059,   3144,   3229,
      3315,   3401,   3487,   3573,   3660,   3747,   3834,   3922,
      4009,   4097,   4186,   4275,   4364,   4453,   4543,   4633,
      4723,   4814,   4905,   4997,   5089,   5181,   5274,   5367,
      5461,   5556,   5651,   5746,   5842,   5938,   6035,   6133,
      6231,   6330,   6430,   6530,   6631,   6732,   6835,   6938,
      7042,   7147,   7252,   7359,   7466,   7575,   7684,   7795,
      7907,   8019,   8133,   8249,   8365,   8483,   8602,   8723,
      8846,   8970,   9095,   9223,   9353,   9484,   9618,   9754,
      9892,  10034,  10177,  10324,  10475,  10628,  10785,  10947,
     11113,  11284,  11460,  11642,  11831,  12028,  12234,  12449,
     12677,  12919,  13178,  13459,  13770,  14121,  14538,  15079,
     16384,
};

#define ANG_90   16384
#define ANG_180  32768

/* atan2 by octant, the standard reduction: the table covers |y| <= |x| and
 * everything else is a reflection of it. */
static int fb_atan2(int y, int x)
{
    int ax = (x < 0) ? -x : x, ay = (y < 0) ? -y : y, a;

    if (ax == 0 && ay == 0) return 0;
    if (ay <= ax) a = fb_atan[(int)(((long)ay << 8) / ax)];
    else          a = ANG_90 - fb_atan[(int)(((long)ax << 8) / ay)];
    if (x < 0) a = ANG_180 - a;
    return (y < 0) ? -a : a;
}

/* d is Q15. The table is 257 entries over [-1,1] with linear interpolation;
 * asin steepens without bound near the poles, but every city in the game is
 * inside 37 degrees of latitude, so the ill-conditioned end is never used. */
static int fb_asin(int d)
{
    int i, f;

    if (d >  32767) d =  32767;
    if (d < -32767) d = -32767;
    i = (d + 32768) >> 8;                    /* 0..255 */
    f = (d + 32768) & 255;
    return fb_asin_t[i] + (((fb_asin_t[i + 1] - fb_asin_t[i]) * f) >> 8);
}

/* Interpolated sine: the raw table is 1/256 turn per step, which is 1.4
 * degrees and visibly faceted on an arc. */
static int fb_sin_i(int a)
{
    int i = (a >> 8) & 255, f = a & 255;
    int s0 = fb_sin[i], s1 = fb_sin[(i + 1) & 255];
    return s0 + (((s1 - s0) * f) >> 8);
}
static int fb_cos_i(int a) { return fb_sin_i(a + ANG_90); }

/* The measured projection, as integers.  Q8 angle units per map pixel:
 * 1 degree is 182.04 units, and the fit gives 0.5972 px/deg of longitude and
 * 0.7854 px/deg of latitude, so 182.04/0.5972 = 305 and 182.04/0.7854 = 232.
 * The rounding is far inside the 4 px of artistic scatter it sits on. */
#define PROJ_X0   35
#define PROJ_Y0   92
#define PROJ_LON  305
#define PROJ_LAT  232

static void fb_city_vec(unsigned int px, unsigned int py, int *v)
{
    int lon = ((int)px - PROJ_X0) * PROJ_LON;
    int lat = (PROJ_Y0 - (int)py) * PROJ_LAT;
    int cl  = fb_cos_i(lat);

    v[0] = (int)(((long)cl * fb_cos_i(lon)) >> 15);
    v[1] = (int)(((long)cl * fb_sin_i(lon)) >> 15);
    v[2] = fb_sin_i(lat);
}

#define ARC_STEPS  16

/* Draws one great-circle arc between two cities, in source-map space, so it
 * scales with the zoom exactly as the airport markers do (U-077).
 *
 * The endpoints are anchored: the projection misses the table coordinates by
 * up to 8 px, so the raw curve is shifted to touch both cities and the
 * discrepancy spread linearly along it.  Without that, arcs would visibly
 * miss the pins they connect.
 */
static void fb_arc(unsigned int i0, unsigned int i1, unsigned long u0,
                   unsigned long v0, unsigned long recip, unsigned int slots,
                   unsigned int colour)
{
    const unsigned char *city = CITY_TABLE;
    unsigned int x0 = city[i0 * 2u], y0 = city[i0 * 2u + 1u];
    unsigned int x1 = city[i1 * 2u], y1 = city[i1 * 2u + 1u];
    int a[3], b[3];
    int dot, omega, sino, k;
    int rx[ARC_STEPS + 1], ry[ARC_STEPS + 1];
    /* Seeded from the start city's own map position, not zero: atan2 returns
     * -180..180 and the map's seam is mid-Atlantic, so an unreferenced first
     * sample can land a whole turn away and drag the arc across the world. */
    int prev_lon;

    fb_city_vec(x0, y0, a);
    fb_city_vec(x1, y1, b);
    prev_lon = ((int)x0 - PROJ_X0) * PROJ_LON;

    dot = (int)(((long)a[0] * b[0] + (long)a[1] * b[1] + (long)a[2] * b[2]) >> 15);
    omega = ANG_90 - fb_asin(dot);
    sino = fb_sin_i(omega);

    for (k = 0; k <= ARC_STEPS; k++) {
        int t = (omega * k) / ARC_STEPS;
        int vx, vy, vz, lon, lat;

        if (sino < 64) {
            /* Nearly coincident: the spherical form degenerates and linear
             * interpolation is its limit anyway. */
            rx[k] = (int)x0 + (((int)x1 - (int)x0) * k) / ARC_STEPS;
            ry[k] = (int)y0 + (((int)y1 - (int)y0) * k) / ARC_STEPS;
            continue;
        }
        {
            /* w = sin(theta)/sin(omega) in Q15.  Written as a shift then a
             * divide, not a reciprocal multiply: sin(omega) is small for short
             * routes, so a Q15 reciprocal reaches ~16.7M and sin * recip
             * overflows the SH2's 32-bit long.  That produced wild lines out
             * of the London cluster, where the shortest arcs are. */
            int w1 = (int)((((long)fb_sin_i(omega - t)) << 15) / sino);
            int w2 = (int)((((long)fb_sin_i(t)) << 15) / sino);
            vx = (int)((((long)w1 * a[0]) + ((long)w2 * b[0])) >> 15);
            vy = (int)((((long)w1 * a[1]) + ((long)w2 * b[1])) >> 15);
            vz = (int)((((long)w1 * a[2]) + ((long)w2 * b[2])) >> 15);
        }
        lat = fb_asin(vz);
        lon = fb_atan2(vy, vx);
        /* Unwrap against the previous sample -- and for k = 0 against the
         * start city itself -- so a route crossing the seam stays continuous
         * instead of jumping the width of the map. */
        while (lon - prev_lon >  ANG_180) lon -= 2 * ANG_180;
        while (lon - prev_lon < -ANG_180) lon += 2 * ANG_180;
        prev_lon = lon;
        rx[k] = PROJ_X0 + lon / PROJ_LON;
        ry[k] = PROJ_Y0 - lat / PROJ_LAT;
    }

    /* Anchor both ends onto the table coordinates. */
    {
        int ex0 = (int)x0 - rx[0], ey0 = (int)y0 - ry[0];
        int ex1 = (int)x1 - rx[ARC_STEPS], ey1 = (int)y1 - ry[ARC_STEPS];
        for (k = 0; k <= ARC_STEPS; k++) {
            rx[k] += ex0 + ((ex1 - ex0) * k) / ARC_STEPS;
            ry[k] += ey0 + ((ey1 - ey0) * k) / ARC_STEPS;
        }
    }

    /* Draw it, in the same slot/column space the markers use. */
    for (k = 0; k < ARC_STEPS; k++) {
        int sx = rx[k], sy = ry[k], ex = rx[k + 1], ey = ry[k + 1];
        int dx = (ex > sx) ? ex - sx : sx - ex;
        int dy = (ey > sy) ? ey - sy : sy - ey;
        int n = (dx > dy ? dx : dy), s;

        if (n == 0) n = 1;
        for (s = 0; s <= n; s++) {
            int px = sx + ((ex - sx) * s) / n;
            int py = sy + ((ey - sy) * s) / n;
            unsigned long ux;
            unsigned int col, slot;

            if (px < 0 || py < 0) continue;
            ux = ((unsigned long)px << 16);
            if (ux < u0 || ((unsigned long)py << 16) < v0) continue;
            col  = (unsigned int)(((ux - u0) >> 8) * recip >> 16);
            slot = (unsigned int)py - (unsigned int)(v0 >> 16);
            if (col >= 320u || slot >= slots) continue;
            fb_mark(slot, col, 1u, colour);
        }
    }
}

/* Airports plus a fan of routes from London, which is city 0.  Drawn after the
 * map so the arcs sit on top of it, and in the same slot/column space, so the
 * whole overlay scales with the zoom. */
#define ARC_HUB    0u

void fb_draw_overlay(unsigned long u0, unsigned long v0, unsigned long step,
                     unsigned int slots)
{
    unsigned long recip = 0x01000000uL / step;
    unsigned int i;

    for (i = 1u; i < CITY_MAJOR; i++)
        fb_arc(ARC_HUB, i, u0, v0, recip, slots, PAL_ARC);

    fb_draw_airports(u0, v0, step, slots);
}
