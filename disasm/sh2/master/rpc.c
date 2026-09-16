/* ==========================================================================
 * Aerobiz Ultimate -- SH2 master command dispatcher (M5, first slice)
 *
 * The 68000 hands work over through the eight comm registers the adapter
 * shares between the two sides.  On the SH2 those are the cache-through
 * addresses at 0x20004020; docs/32x-hardware-manual.md section 3.4 requires
 * cache-through access for every system register, so nothing here may be
 * given a cached (0x0600xxxx) alias.
 *
 * Slot allocation.  COMM0/COMM1 and COMM2/COMM3 carry the boot handshake
 * ('M_OK' / 'S_OK', see definitions_32x.asm) but are free once the 68000 has
 * cleared them to release us, so all four pairs are available here:
 *
 *   0x20004020  word  command; 0 = idle.  Written last by the 68000 and
 *                     cleared by us, so it doubles as the completion flag.
 *   0x20004022  word  map state, 68000 -> SH2 (see MAP_STATE below)
 *   0x20004024  long  argument 0  ->  result 0
 *   0x20004028  long  argument 1  ->  result 1
 *   0x2000402C  word  call counter, incremented by us
 *   0x2000402E  word  SH2 status, SH2 -> 68000 (see SH2_STATUS below)
 *
 * The call counter was a longword until U-034 needed a word flowing the other
 * way. Nothing on the 68000 read it -- tooling reads sh2_calls_serviced -- so
 * it gave up its low half.
 *
 * Polling rather than the CMD interrupt is deliberate for this first slice:
 * it has no latency subtleties to get wrong, and correctness comes before
 * speed (ROADMAP M5).  Moving to CMD is U-040's business.
 * ========================================================================== */

#define COMM_CMD    (*(volatile unsigned short *)0x20004020)
#define COMM_ARG0   (*(volatile unsigned long  *)0x20004024)
#define COMM_ARG1   (*(volatile unsigned long  *)0x20004028)
#define COMM_COUNT  (*(volatile unsigned short *)0x2000402C)

/* Command numbers.  Keep in step with definitions_32x.asm. */
#define SH2_CMD_PING    0x0001u
#define SH2_CMD_UDIV32  0x0002u
#define SH2_CMD_FBTEST  0x0003u
#define SH2_CMD_MAPTEST 0x0004u
#define SH2_CMD_ZOOM    0x0005u
#define SH2_CMD_TIMING  0x0006u
#define SH2_CMD_LZ      0x0007u
#define SH2_CMD_LZ_JOB  0x0008u
#define SH2_CMD_AFFINE  0x0009u
#define SH2_CMD_SEGA    0x000Au
#define SH2_CMD_SEGA_COVER 0x000Bu

/* Map state, U-034. Comm word 1 is a word the RPC protocol leaves free
 * (command at word 0, arguments at 2-5), and the boot release clears it with
 * the rest of 'M_OK'. The 68000 writes it and we only read it: manual
 * :717 makes a register written from both sides, or read while the other side
 * writes, undefined -- so a write can tear a read, and every read is taken
 * twice and must agree.
 *
 * Why a state word and not an RPC command: the 68000 changes this from its
 * V-Blank handler, and an interrupt-time command would race the LZ thunk's
 * handshake on the same comm slots. A level the SH2 polls has nothing to race.
 * We read ON and the generation; the other bits are the 68000's own
 * bookkeeping. */
#define MAP_STATE     (*(volatile unsigned short *)0x20004022)
#define MAP_STATE_ON  0x0001u
#define MAP_STATE_GEN 0x0F00u       /* bumped by the 68000 on every switch-on */

/* SH2 status, the one word we write and the 68000 only reads. SH2_DRAWN with
 * a generation means "both buffers hold the map for that switch-on". Tagging
 * it is what stops a "drawn" left over from an earlier visit being read as
 * this one's: the 68000 reveals the layer only when the generations match. */
#define SH2_STATUS    (*(volatile unsigned short *)0x2000402E)
#define SH2_DRAWN     0x8000u

/* Interrupt Mask Register, manual 3.2.2 (address 2000 4000h): bit 15 is FM,
 * the VDP access authorization. Read-only use here -- the register also holds
 * the V/H/CMD/PWM enables, and ground rule 11 requires at least one to stay
 * set, so nothing writes it. */
#define SYS_INTMASK (*(volatile unsigned short *)0x20004000)
#define INTMASK_FM  0x8000u

void sh2_fb_test(void);
void sh2_map_test(void);
void sh2_zoom_test(void);
void sh2_map_game_begin(void);
void sh2_map_game_draw(void);
void sh2_affine_test(void);
void sh2_timing_test(void);
void sh2_lz_test(void);
unsigned long sh2_lz_job(unsigned long src, unsigned long fb_byte_offset);
void sh2_sega_cover(void);
void sh2_sega_spin(void);

/* V-Blank tally, incremented by vint_handler in main.s.  Defined here rather
 * than in assembly so the C side gets the type right; U-035 uses it as its
 * clock because manual 5.3 puts the free-running timer off limits. */
volatile unsigned long sh2_vint_count;

/* Answered by PING.  An arbitrary constant that is unlikely to appear in a
 * comm register by accident, so the 68000 can prove the round trip happened
 * rather than reading back its own argument. */
#define SH2_PING_REPLY  0x5A5AC0DEuL

/* Same tally as COMM_COUNT, kept in SDRAM as well.  PicoDrive's debug read
 * serves RAM but not the $A151xx I/O range, so a counter that lives only in a
 * comm register cannot be sampled from outside while the game runs -- reading
 * it returns zero, which looks exactly like "the offload never fired".  This
 * one is reachable as `read master <addr>`. */
volatile unsigned long sh2_calls_serviced;

/* Set after answering an LZ job: the 68000 is about to take FM back and copy
 * the result out of the frame buffer, and a draw started now would be cut off
 * part way when it does. Cleared once the copy is over; see sh2_rpc_loop. */
static int lz_copy_pending;

/* Service one command if the 68000 has queued one. Split out of sh2_rpc_loop
 * so the render path and the idle path go through the same code rather than
 * through two copies that can drift apart. */
static void sh2_service(void)
{
    unsigned short cmd = COMM_CMD;

    if (cmd == 0u)
        return;

    switch (cmd) {
    case SH2_CMD_PING:
        COMM_ARG0 = SH2_PING_REPLY;
        break;

    case SH2_CMD_UDIV32: {
        /* Both arguments must be read before either result is written --
         * the argument and result slots are the same registers. */
        unsigned long dividend = COMM_ARG0;
        unsigned long divisor  = COMM_ARG1;
        unsigned long quotient, remainder;

        if (divisor == 0uL) {
            /* The 68000 routine would trap here; the probe never sends
             * it.  Answer with a value it can recognise instead. */
            quotient  = 0xFFFFFFFFuL;
            remainder = 0uL;
        } else {
            quotient  = dividend / divisor;
            remainder = dividend % divisor;
        }

        COMM_ARG0 = quotient;
        COMM_ARG1 = remainder;
        break;
    }

    case SH2_CMD_FBTEST:
        sh2_fb_test();
        break;

    case SH2_CMD_MAPTEST:
        sh2_map_test();
        break;

    case SH2_CMD_AFFINE:
        sh2_affine_test();         /* animates; does not return */
        break;

    case SH2_CMD_SEGA:
        sh2_sega_spin();           /* returns with the layer blank again */
        break;

    case SH2_CMD_SEGA_COVER:
        sh2_sega_cover();          /* returns with the layer up, black */
        break;

    case SH2_CMD_ZOOM:
        sh2_zoom_test();           /* animates; does not return */
        break;

    case SH2_CMD_TIMING:
        sh2_timing_test();         /* halts when done; does not return */
        break;

    case SH2_CMD_LZ:
        sh2_lz_test();             /* halts when done; does not return */
        break;

    case SH2_CMD_LZ_JOB: {
        /* Both arguments must be read before either result is written --
         * the argument and result slots are the same registers. */
        unsigned long src = COMM_ARG0;
        unsigned long fbo = COMM_ARG1;
        COMM_ARG0 = sh2_lz_job(src, fbo);
        lz_copy_pending = 1;
        break;
    }

    default:
        COMM_ARG0 = 0xDEAD0000uL | (unsigned long)cmd;
        break;
    }

    sh2_calls_serviced = sh2_calls_serviced + 1uL;
    COMM_COUNT = (unsigned short)(COMM_COUNT + 1u);
    COMM_CMD   = 0u;               /* release the 68000 */
}

/* Buffers still to draw before the map may be shown. Two, because the frame
 * buffer is double and the picture is static: one draw per buffer, then the
 * layer goes up and the SH2 has nothing more to do until the state changes. */
#define MAP_BUFFERS 2u

void sh2_rpc_loop(void)
{
    int map_on = 0;
    unsigned short map_gen = 0u;
    unsigned int map_draws = 0u;
    int fm_seen_low = 0;
    unsigned long lz_answered_at = 0uL;

    COMM_COUNT = 0;
    SH2_STATUS = 0;
    sh2_calls_serviced = 0;

    for (;;) {
        unsigned short a = MAP_STATE;
        unsigned short b = MAP_STATE;
        int fm = (SYS_INTMASK & INTMASK_FM) != 0u;

        if (a == b) {
            int want = (a & MAP_STATE_ON) != 0u;
            unsigned short gen = (unsigned short)(a & MAP_STATE_GEN);
            if (want && (!map_on || gen != map_gen)) {
                SH2_STATUS = 0u;
                sh2_map_game_begin();
                map_gen = gen;
                map_draws = MAP_BUFFERS;
            } else if (!want && map_on) {
                SH2_STATUS = 0u;
                map_draws = 0u;
            }
            map_on = want;
        }

        /* Wait out the LZ thunk's copy. It takes FM the moment it sees the
         * answer and gives it back when the copy is done, so "FM seen low,
         * then high again" is the end of it. A small copy can finish between
         * two polls; if FM was never seen low two V-Blanks after answering,
         * the copy is over and nothing is left to cut off. */
        if (lz_copy_pending) {
            if (lz_answered_at == 0uL)
                lz_answered_at = sh2_vint_count + 1uL;
            if (!fm)
                fm_seen_low = 1;
            else if (fm_seen_low || sh2_vint_count > lz_answered_at + 1uL) {
                lz_copy_pending = 0;
                fm_seen_low = 0;
                lz_answered_at = 0uL;
            }
        }

        /* Draw only while FM is actually granted: with FM = 0 an SH2 write to
         * the frame buffer is ignored outright (manual:285), so drawing
         * through that window would silently drop part of a picture. */
        if (map_on && map_draws != 0u && fm && !lz_copy_pending) {
            sh2_map_game_draw();
            map_draws = map_draws - 1u;
            if (map_draws == 0u)
                SH2_STATUS = (unsigned short)(SH2_DRAWN | map_gen);
        }

        sh2_service();
    }
}
