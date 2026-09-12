! ==========================================================================
! Aerobiz Ultimate -- SH2 slave
!
! Started by the boot ROM at slave_start with VBR from the MARS user header.
! The boot ROM has already written 'S_OK' at $20004024; the 68000 clears it to
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

        ! Cache on, for the same reason as the master (main.s) and with more
        ! at stake: this CPU's only job today is a spin loop, and with the
        ! cache off every instruction fetch of it is an 8-word SDRAM burst
        ! (32x-hardware-manual.md:897).  Measured with VRD_SH2_TIMING: 12.8M
        ! uncached accesses and 139M wait cycles over 500 frames, seven times
        ! the master's, for a CPU doing nothing at all.  On hardware that is
        ! bus traffic competing with the master.
        mov.l   .L_sccr, r1
        mov     #0x00, r0
        mov.b   r0, @r1                         ! CE = 0 before changing CCR
        mov     #0x10, r0
        mov.b   r0, @r1                         ! CP = 1: purge, valid + LRU
        mov     #0x01, r0
        mov.b   r0, @r1                         ! CE = 1

        mov.l   .L_comm_sok, r1
.Lwait_release:
        mov.l   @r1, r0
        tst     r0, r0
        bf      .Lwait_release

slave_loop:
        bra     slave_loop
        nop

        .align  4
! RTE restores PC and SR only, so the handler saves what it touches -- r1 is
! a scratch register the compiler uses freely.  Same fix as the master's.
slave_cmd_handler:
        mov.l   r0, @-r15
        mov.l   r1, @-r15
        mov.l   .L_scmd_clr, r1
        mov.w   r0, @r1
        mov.l   @r15+, r1
        mov.l   @r15+, r0
        rte
        nop

        .align  4
slave_halt:
        bra     slave_halt
        nop

        .align  4
.L_sstack:      .long   SLAVE_STACK
.L_sccr:        .long   0xFFFFFE92      ! sh7604 8.2
.L_comm_sok:    .long   COMM_SOK
.L_scmd_clr:    .long   CMD_CLR
