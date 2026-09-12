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
