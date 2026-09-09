! ==========================================================================
! Aerobiz Ultimate -- SH2 slave
!
! Started by the boot ROM at slave_start with VBR from the MARS user header.
! The boot ROM has already written 'S_OK' into comm4; the 68000 clears it to
! release us.  docs/32x-hardware-manual.md section 5.1.
!
! The slave holds no work yet.  It exists so both CPUs are in a known state
! from milestone M1 onward, ready for the AI/economy split described in
! PORT_ARCHITECTURE.md section 4.2.
! ==========================================================================

        .include "disasm/sh2/shared/mars.inc"

        .section .slave_vectors, "a"
        .align  4
slave_vectors:
        .rept   67
        .long   slave_halt
        .endr
        .long   slave_halt                      ! 67: PWM
        .long   slave_cmd_handler               ! 68: CMD
        .long   slave_halt                      ! 69: HINT
        .long   slave_halt                      ! 70: VINT
        .long   slave_halt                      ! 71: VRES

        .section .slave_text, "ax"
        .align  4
        .global slave_start
slave_start:
        mov     #0xF0, r0
        ldc     r0, sr

        mov.l   .L_sstack, r15

        ! Same masking rule as the master (manual 5.3): keep PWM masked.
        mov     #0x60, r0
        ldc     r0, sr

        mov.l   .L_comm4, r1
.Lwait_release:
        mov.l   @r1, r0
        tst     r0, r0
        bf      .Lwait_release

slave_loop:
        bra     slave_loop
        nop

        .align  4
slave_cmd_handler:
        mov.l   .L_scmd_clr, r1
        mov.w   r0, @r1
        rte
        nop

        .align  4
slave_halt:
        bra     slave_halt
        nop

        .align  4
.L_sstack:      .long   SLAVE_STACK
.L_comm4:       .long   COMM4
.L_scmd_clr:    .long   CMD_CLR
