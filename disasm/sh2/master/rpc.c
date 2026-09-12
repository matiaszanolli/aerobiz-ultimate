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
 *   0x20004024  long  argument 0  ->  result 0
 *   0x20004028  long  argument 1  ->  result 1
 *   0x2000402C  long  call counter, incremented by us; lets the 68000 tell
 *                     "no reply yet" apart from "replied with zero".
 *
 * Polling rather than the CMD interrupt is deliberate for this first slice:
 * it has no latency subtleties to get wrong, and correctness comes before
 * speed (ROADMAP M5).  Moving to CMD is U-040's business.
 * ========================================================================== */

#define COMM_CMD    (*(volatile unsigned short *)0x20004020)
#define COMM_ARG0   (*(volatile unsigned long  *)0x20004024)
#define COMM_ARG1   (*(volatile unsigned long  *)0x20004028)
#define COMM_COUNT  (*(volatile unsigned long  *)0x2000402C)

/* Command numbers.  Keep in step with definitions_32x.asm. */
#define SH2_CMD_PING    0x0001u
#define SH2_CMD_UDIV32  0x0002u
#define SH2_CMD_FBTEST  0x0003u
#define SH2_CMD_MAPTEST 0x0004u

void sh2_fb_test(void);
void sh2_map_test(void);

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

void sh2_rpc_loop(void)
{
    COMM_COUNT = 0;
    sh2_calls_serviced = 0;

    for (;;) {
        unsigned short cmd = COMM_CMD;

        if (cmd == 0u)
            continue;

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

        default:
            COMM_ARG0 = 0xDEAD0000uL | (unsigned long)cmd;
            break;
        }

        sh2_calls_serviced = sh2_calls_serviced + 1uL;
        COMM_COUNT = COMM_COUNT + 1uL;
        COMM_CMD   = 0u;               /* release the 68000 */
    }
}
