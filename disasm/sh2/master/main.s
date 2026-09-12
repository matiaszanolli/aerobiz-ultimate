! ==========================================================================
! Aerobiz Ultimate -- SH2 master
!
! The 32X boot ROM copies this image from the cartridge into SDRAM, sets VBR
! from the MARS user header and jumps to master_start.  By then the boot ROM
! has already written 'M_OK' into comm0; the 68000 clears it to release us.
! docs/32x-hardware-manual.md section 5.1.
! ==========================================================================

        .include "disasm/sh2/shared/mars.inc"

! --------------------------------------------------------------------------
! Master vector table, VBR = 0x06000000, 0x120 bytes.
! Every IRL auto-vector is populated; unused ones land on a halt so a stray
! interrupt is visible in a debugger rather than silently corrupting state.
! --------------------------------------------------------------------------
        .section .master_vectors, "a"
        .align  4
master_vectors:
        .rept   67
        .long   halt                            ! vectors 0-66
        .endr
        .long   pwm_handler                     ! 67: PWM,  level 6
        .long   cmd_handler                     ! 68: CMD,  level 8
        .long   hint_handler                    ! 69: HINT, level 10
        .long   vint_handler                    ! 70: VINT, level 12
        .long   vres_handler                    ! 71: VRES, level 14

! --------------------------------------------------------------------------
        .section .master_text, "ax"
        .align  4
        .global master_start
master_start:
        ! Mask every interrupt while we bring ourselves up.  Manual 5.3
        ! requires at least one mask to remain set at all times, so the
        ! interrupt mask register is only opened once handlers are live.
        mov     #0xF0, r0
        ldc     r0, sr

        mov.l   .L_stack, r15

        ! Release: the boot ROM put 'M_OK' in comm0 and the 68000 clears it
        ! when it is ready for us.  Manual 5.1 -- the SH2 must wait for that
        ! clear before touching anything the 68000 is still initialising.
        mov.l   .L_comm_mok, r1
.Lwait_release:
        mov.l   @r1, r0
        tst     r0, r0
        bf      .Lwait_release

        ! Interrupts we are prepared to service.  V is enough for a heartbeat;
        ! CMD is how the 68000 will hand us work later.
        mov.l   .L_sysreg, r1
        mov.w   @r1, r0
        mov     #(SYSREG_V | SYSREG_CMD), r2
        or      r2, r0
        mov.w   r0, @r1

        ! Manual 5.3: "There should always be 1 or more interrupt masks."
        ! Mask level 6 leaves PWM (level 6) blocked -- we do not use it yet --
        ! while admitting CMD (8), HINT (10), VINT (12) and VRES (14).
        mov     #0x60, r0                       ! SR I3-I0 = 6
        ldc     r0, sr

        ! Cache on.  The boot ROM flow in 32x-hardware-manual.md:1359 ends with
        ! "Cache Clear / Cache ON", but nothing observable confirms it ran, and
        ! the cost of it not having run is severe: SDRAM reads are 8-word-burst
        ! fixed (manual:897), so a cache-through fetch of a single word pays for
        ! eight.  Doing it ourselves is idempotent -- a purge and a re-enable.
        !
        ! sh7604-hardware-manual.md 8.2: CP purges and self-clears, CE enables.
        ! Manual 8.2 also requires CCR only be changed while the cache is
        ! disabled, hence the explicit 0 first.
        mov.l   .L_ccr, r1
        mov     #0x00, r0
        mov.b   r0, @r1                         ! CE = 0 before changing CCR
        mov     #0x10, r0
        mov.b   r0, @r1                         ! CP = 1: purge, valid + LRU
        mov     #0x01, r0
        mov.b   r0, @r1                         ! CE = 1

        ! Zero .bss before any C runs.  objcopy -O binary drops NOBITS, so
        ! the cartridge image carries no .bss and SDRAM holds whatever the
        ! boot ROM left there.  Bounds come from sh2.lds.
        mov.l   .L_bss_start, r1
        mov.l   .L_bss_end, r2
        mov     #0, r0
.Lbss_clear:
        cmp/hs  r2, r1                          ! T = (r1 >= r2), unsigned
        bt      .Lbss_done
        mov.l   r0, @r1
        add     #4, r1
        bra     .Lbss_clear
        nop
.Lbss_done:

! --------------------------------------------------------------------------
! Hand over to the C command dispatcher, which never returns.  Manual 5.3
! forbids SLEEP in an application, so its idle path is a plain spin.
!
! sh-elf prefixes C symbols with an underscore.
! --------------------------------------------------------------------------
        mov.l   .L_rpc_loop, r0
        jsr     @r0
        nop

! Only reached if the dispatcher ever returns, which it does not.
main_loop:
        bra     main_loop
        nop

! --------------------------------------------------------------------------
! Interrupt handlers.  Each interrupt except CMD keeps asserting until its
! clear register is written -- manual 3.2.2 -- so every handler clears first.
!
! RTE restores PC and SR and nothing else, so every register a handler touches
! has to be saved by hand.  These originally clobbered r1, which is a caller-
! saved scratch register gcc uses freely: with V interrupts enabled that is a
! rare, timing-dependent corruption of whatever C code was running.
! --------------------------------------------------------------------------
        .align  4
vint_handler:
        mov.l   r0, @-r15
        mov.l   r1, @-r15
        mov.l   .L_vint_clr, r1
        mov.w   r0, @r1                         ! any write clears
        ! Frame tally.  U-035 uses V-Blanks as its clock because manual 5.3
        ! puts the free-running timer off limits.
        mov.l   .L_vint_cnt, r1
        mov.l   @r1, r0
        add     #1, r0
        mov.l   r0, @r1
        mov.l   @r15+, r1
        mov.l   @r15+, r0
        rte
        nop

        .align  4
hint_handler:
        mov.l   r0, @-r15
        mov.l   r1, @-r15
        mov.l   .L_hint_clr, r1
        mov.w   r0, @r1
        mov.l   @r15+, r1
        mov.l   @r15+, r0
        rte
        nop

        .align  4
cmd_handler:
        mov.l   r0, @-r15
        mov.l   r1, @-r15
        mov.l   .L_cmd_clr, r1
        mov.w   r0, @r1
        mov.l   @r15+, r1
        mov.l   @r15+, r0
        rte
        nop

        .align  4
pwm_handler:
        mov.l   r0, @-r15
        mov.l   r1, @-r15
        mov.l   .L_pwm_clr, r1
        mov.w   r0, @r1
        mov.l   @r15+, r1
        mov.l   @r15+, r0
        rte
        nop

        .align  4
vres_handler:
        mov.l   r0, @-r15
        mov.l   r1, @-r15
        mov.l   .L_vres_clr, r1
        mov.w   r0, @r1
        mov.l   @r15+, r1
        mov.l   @r15+, r0
        rte
        nop

! An interrupt we never armed.  Park rather than run off into SDRAM.
        .align  4
halt:
        bra     halt
        nop

        .align  4
.L_stack:       .long   MASTER_STACK
.L_ccr:         .long   0xFFFFFE92      ! sh7604 8.2
.L_bss_start:   .long   __bss_start
.L_bss_end:     .long   __bss_end
.L_rpc_loop:    .long   _sh2_rpc_loop
.L_comm_mok:    .long   COMM_MOK
.L_sysreg:      .long   SYSREG
.L_vint_clr:    .long   VINT_CLR
.L_vint_cnt:    .long   _sh2_vint_count
.L_hint_clr:    .long   HINT_CLR
.L_cmd_clr:     .long   CMD_CLR
.L_pwm_clr:     .long   PWM_CLR
.L_vres_clr:    .long   VRES_CLR
