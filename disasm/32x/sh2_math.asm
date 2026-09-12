; ===========================================================================
; SH2 math thunk -- U-044
;
; Reached from UnsignedDivide's slow path in place of its first six bytes, a
; size-neutral swap under `ifne ROM_BASE` exactly like ConfigVDPDMA's.
;
; Only the slow path comes here, and that is the whole point.  U-039 measured
; the comm-port round trip at a flat ~560 68000 cycles regardless of the work
; carried, against these two costs for the division itself:
;
;   divisor >= $10000   16-iteration shift-subtract   ~900 cycles  -> offload
;   divisor <  $10000   a single DIVU.W               ~200 cycles  -> keep
;
; So the entry test the game already performs (`cmpi.l #$10000,d1 / bcc`) is
; also, by luck, exactly the right offload predicate.  The cheap path never
; reaches the adapter and pays nothing.
;
;   In:  d0.l = dividend, d1.l = divisor  (divisor >= $10000 guaranteed)
;   Out: d0.l = quotient, d1.l = remainder
;
; Clobbers nothing else -- the caller's contract is the stock routine's, and
; the stock routine preserves d2/d3 by saving them.  We never touch them.
; ===========================================================================

; A stalled SH2 must not hang the game.  The bound is far above the five poll
; iterations U-039 measured, so reaching it means "not answering", not "slow".
MARS_SH2_UDIV_WAIT  equ 4096

MarsSh2UDiv:
        move.w  sr,-(sp)
        ori.w   #$0700,sr                       ; the four comm slots are one
                                                ; shared resource; an interrupt
                                                ; that divided mid-call would
                                                ; read another call's results

        move.l  d0,(MARS_RPC_ARG0).l            ; dividend
        move.l  d1,(MARS_RPC_ARG1).l            ; divisor
        move.w  #MARS_SH2_CMD_UDIV32,(MARS_RPC_CMD).l

        move.w  #MARS_SH2_UDIV_WAIT,d0
.wait:
        tst.w   (MARS_RPC_CMD).l
        beq.s   .answered
        subq.w  #1,d0
        bne.s   .wait

; --- The SH2 did not answer.  Do it here rather than leave the game wedged.
; This is the stock UDiv_Full32 body, which the 32X build has jumped over.
        move.l  (MARS_RPC_ARG0).l,d0            ; recover the operands we sent
        move.l  (MARS_RPC_ARG1).l,d1
        move.w  (sp)+,sr
        movem.l d2-d3,-(sp)
        move.l  d1,d3                           ; d3 = divisor
        move.l  d0,d1                           ; d1 = dividend
        swap    d0
        clr.w   d0                              ; d0 = quotient accumulator
        clr.w   d1
        swap    d1                              ; d1 = remainder seed
        moveq   #15,d2                          ; 16 iterations
.shift:
        add.l   d0,d0
        addx.l  d1,d1
        cmp.l   d3,d1
        bcs.s   .nosub
        sub.l   d3,d1
        addq.b  #1,d0
.nosub:
        dbra    d2,.shift
        movem.l (sp)+,d2-d3
        rts

.answered:
        move.l  (MARS_RPC_ARG0).l,d0            ; quotient
        move.l  (MARS_RPC_ARG1).l,d1            ; remainder
        move.w  (sp)+,sr
        rts
