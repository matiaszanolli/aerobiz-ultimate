/* ==========================================================================
 * U-046 -- Aerobiz's LZ decompressor on the SH2.
 *
 * A transcription of tools/lz_decompress.py, which is itself a literal
 * transcription of the 68000 at $003FEC.  Kept in that shape deliberately: the
 * three can be diffed against each other, and a decompressor that is subtly
 * wrong produces plausible garbage rather than an error.
 *
 * Why this routine: U-045 measured it at 11.93% of gameplay frames, the single
 * largest non-idle cost, and U-046 measured the 68000 at 285 cycles per output
 * byte -- so the largest block in the game costs it 62 frames, which is where
 * the 74-76 frame quarter-boundary stall comes from.
 *
 * The odd consumption rule survives the port: lz_read_bits(n) shifts n bits
 * out and the caller then clears the new top bit, so a token consumes n + 1
 * bits.  Folding that in would be tidier and would no longer match the 68000.
 *
 * ---------------------------------------------------------------------------
 * Where the output goes, which the original U-046 sketch got wrong twice
 *
 * Not to VRAM: the 68000's call sites decompress into a work-RAM scratch
 * buffer at $FF1804 and then DMA that to VRAM, so the SH2 only has to produce
 * the bytes somewhere the 68000 can reach.
 *
 * And not straight into the frame buffer either, which was the obvious
 * candidate.  Two independent reasons:
 *
 *   - A byte write to the frame buffer cannot store zero
 *     (docs/32x-hardware-manual.md:1162, KNOWN_ISSUES).  Decompressed tile
 *     data is full of zero bytes.
 *   - Back-references read from the output that has already been written, and
 *     an SH2 frame buffer read costs 5-12 wait states (manual 4.1) against
 *     nothing at all for a cached SDRAM hit.
 *
 * So the output is built in SDRAM and copied to the frame buffer afterwards in
 * whole words, which sidesteps both.  The copy is 2 cycles per word against
 * the 285 cycles per byte the decompression itself costs the 68000, so it is
 * noise.
 *
 * Input is read through the CACHED cartridge alias at 0x02000000, not the
 * cache-through 0x22000000 one: the stream is read strictly forwards, so a
 * 16-byte line fill serves 16 bytes of it.  Cache-through would pay the full
 * cartridge wait on every single byte.
 * ========================================================================== */

#include "timing_config.h"

/* The table at $04684C. */
static const unsigned short lz_mask[17] = {
    0x0000, 0x0001, 0x0003, 0x0007, 0x000F, 0x001F, 0x003F, 0x007F,
    0x00FF, 0x01FF, 0x03FF, 0x07FF, 0x0FFF, 0x1FFF, 0x3FFF, 0x7FFF, 0xFFFF
};

typedef struct {
    const unsigned char *d;
    unsigned long        p;
    unsigned short       window;    /* $FFBD56 */
    unsigned short       word;      /* $FFBD54, current source word */
    int                  avail;     /* $FF1802, bits left in word */
} lz_stream;

/* $003F72.  The stream's words are LITTLE-endian: hi = d[p + 1]. */
static void lz_read_bits(lz_stream *s, int n)
{
    unsigned int got, lo, hi;

    s->window = (unsigned short)(s->window << n);
    if (n > s->avail) {
        n -= s->avail;
        got = (unsigned int)(lz_mask[s->avail] & s->word);
        s->window = (unsigned short)(s->window | (got << n));
        lo = s->d[s->p];
        hi = s->d[s->p + 1];
        s->word = (unsigned short)((hi << 8) | lo);
        s->p += 2;
        s->avail = 16 - n;
    } else {
        s->avail -= n;
    }
    s->window = (unsigned short)
        (s->window | ((s->word >> s->avail) & lz_mask[n]));
}

/* $003FEC.  Returns the number of bytes written.
 *
 * Note that literals and control bytes come off the same pointer the bit
 * reader refills from -- the byte and bit streams are interleaved, not
 * separate.  That is the detail most likely to be lost in a tidier rewrite. */
unsigned long lz_decompress(const unsigned char *src, unsigned char *dst)
{
    lz_stream s;
    unsigned long out = 0;
    unsigned int i;

    s.d = src;
    s.p = 0;
    s.window = 0;
    s.word = 0;
    s.avail = 0;
    lz_read_bits(&s, 16);                       /* prime the window */

    for (;;) {
        unsigned int ctrl = s.d[s.p++];

        for (i = 0u; i < 8u; i++) {
            if (ctrl & 0x80u) {
                dst[out++] = s.d[s.p++];        /* literal */
            } else {
                unsigned int w = s.window;
                unsigned int length, dist;
                int n;
                unsigned long back;
                unsigned long k;

                if      (w & 0x8000u) { length = 1;                      n = 0;  }
                else if (w & 0x4000u) { length = (w & 0x6000u) >> 13;    n = 2;  }
                else if (w & 0x2000u) { length = (w & 0x3800u) >> 11;    n = 4;  }
                else if (w & 0x1000u) { length = (w & 0x1E00u) >> 9;     n = 6;  }
                else if (w & 0x0800u) { length = (w & 0x0F80u) >> 7;     n = 8;  }
                else if (w & 0x0400u) { length = (w & 0x07E0u) >> 5;     n = 10; }
                else if (w & 0x0200u) { length = (w & 0x03F8u) >> 3;     n = 12; }
                else {
                    length = ((w & 0x01FCu) >> 2) + 0x80u;
                    if (length == 0xFFu)        /* $004232, end of stream */
                        return out;
                    n = 13;
                }
                if (n)
                    lz_read_bits(&s, n);
                s.window &= 0x7FFFu;            /* $0040F0 */

                w = s.window;
                if      (w < 0x0800u) { dist = (w & 0x0600u) >> 9;                    n = 7;  }
                else if (w < 0x0C00u) { dist = ((w & 0x0300u) >> 8) + 4u;             n = 8;  }
                else if (w < 0x1800u) { dist = (((w - 0x0C00u) & 0x0F80u) >> 7) + 8u; n = 9;  }
                else if (w < 0x3000u) { dist = (((w - 0x1800u) & 0x1FC0u) >> 6) + 0x20u; n = 10; }
                else if (w < 0x4000u) { dist = ((w & 0x1FFFu) | 0x1000u) >> 5;        n = 11; }
                else if (w < 0x5000u) { dist = ((w & 0x1FFFu) | 0x1000u) >> 4;        n = 12; }
                else if (w < 0x6000u) { dist = ((w & 0x1FFFu) | 0x1000u) >> 3;        n = 13; }
                else if (w < 0x7000u) { dist = ((w & 0x1FFFu) | 0x1000u) >> 2;        n = 14; }
                else                  { dist = ((w & 0x1FFFu) | 0x1000u) >> 1;        n = 15; }
                lz_read_bits(&s, n);

                /* Byte at a time and forwards, so an overlapping copy
                 * replicates -- that is what makes a run cheap to encode. */
                back = out - dist - 1u;
                for (k = 0u; k <= (unsigned long)length; k++)
                    dst[out++] = dst[back + k];
            }
            ctrl = (ctrl + ctrl) & 0xFFu;       /* ADD.B d0,$FFA78C */
        }
    }
}

/* ==========================================================================
 * Test and benchmark.
 *
 * Correctness first and separately: decompress one known block and publish its
 * length and an FNV-1a checksum, which tools/lz_decompress.py can compute
 * independently.  A wrong decompressor yields plausible-looking bytes, so
 * "it produced 22,528 bytes" proves nothing on its own.
 *
 * Then timing, bracketed by the V-Blank counter rather than accumulated from
 * power-on, so no slope subtraction is needed here.
 * ========================================================================== */

/* Cartridge offset of the world map's compressed tiles.  The Genesis address
 * is $088CF8; the game half sits at cartridge $100000, so the SH2 sees it at
 * that offset from the cartridge base. */
#define LZ_SRC_OFFSET  0x00188CF8u

/* CACHED cartridge alias -- see the header note. */
#define CART_CACHED    ((const unsigned char *)0x02000000u)

#define LZ_OUT_MAX     32768u

static unsigned char lz_out[LZ_OUT_MAX];

extern volatile unsigned long sh2_vint_count;

volatile unsigned long sh2_lz_len;
volatile unsigned long sh2_lz_sum;
volatile unsigned long sh2_lz_frames;
volatile unsigned long sh2_lz_iters;
volatile unsigned long sh2_lz_done;

void sh2_lz_test(void)
{
    unsigned long t0, n, i;

    n = lz_decompress(CART_CACHED + LZ_SRC_OFFSET, lz_out);
    sh2_lz_len = n;

    {   unsigned long h = 2166136261uL;
        for (i = 0u; i < n && i < LZ_OUT_MAX; i++) {
            h ^= lz_out[i];
            h *= 16777619uL;
        }
        sh2_lz_sum = h;
    }

    sh2_lz_iters = LZ_ITERS;
    t0 = sh2_vint_count;
    for (i = 0u; i < (unsigned long)LZ_ITERS; i++)
        (void)lz_decompress(CART_CACHED + LZ_SRC_OFFSET, lz_out);
    sh2_lz_frames = sh2_vint_count - t0;

    sh2_lz_done = 0x7D07E;
    for (;;) { }
}
