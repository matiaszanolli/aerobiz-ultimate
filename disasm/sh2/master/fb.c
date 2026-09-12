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

