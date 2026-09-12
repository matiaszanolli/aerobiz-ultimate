; ===========================================================================
; M5 first slice -- does 68000 -> SH2 -> 68000 actually work, and what does a
; round trip cost?
;
; ROADMAP M5 requires that "each ported routine keeps its 68K implementation
; selectable so results can be diffed against the original".  This probe is
; that diff, run before any game logic depends on the answer: the same test
; vectors go through Aerobiz's own UnsignedDivide ($03E0C6, rebased) and
; through the SH2 master's C dispatcher, and the two results are compared
; longword for longword.
;
; Unsigned 32/32 division is the subject because it is the largest piece of
; genuinely pure arithmetic in the game -- no work RAM, no ROM tables, two
; longwords in and two out -- so it can cross the comm ports without any of
; the state transport U-040 still has to solve.  It is emphatically NOT
; expected to be faster this way; see the poll counts in the results.
;
; The probe parks instead of starting the game, exactly as the RV probe does.
; That is what makes $FFFD00 safe to write: PORT_ARCHITECTURE.md section 2.1
; records that no work RAM is permanently free, and $FFFC80-$FFFFFF is only
; untouched because the game never runs here.
; ===========================================================================

SH2P_RESULT     equ $00FFFD00           ; see the header note above
SH2P_VECTORS    equ 16

; Comm-register slots.  Must match disasm/sh2/master/rpc.c.
SH2P_CMD        equ MARS_COMM0          ; word: command; 0 = idle/complete
SH2P_ARG0       equ MARS_COMM2          ; long: arg 0 -> result 0
SH2P_ARG1       equ MARS_COMM4          ; long: arg 1 -> result 1
SH2P_COUNT      equ MARS_COMM6          ; long: dispatcher's own call counter

SH2_CMD_PING    equ $0001
SH2_CMD_UDIV32  equ $0002
SH2_PING_REPLY  equ $5A5AC0DE

; A stuck SH2 must not hang the probe.  The cap is deliberately far above any
; plausible latency so that reaching it means "never answered", not "slow".
SH2P_TIMEOUT    equ 200000

; Batch size for the cost comparison.  Large enough to span several frames at
; 60 Hz so the sampling resolution is not the thing being measured.
SH2P_BENCH      equ 20000

; The game's own routine, at its rebased address.  In: d0 = dividend,
; d1 = divisor.  Out: d0 = quotient, d1 = remainder.
GameUnsignedDivide equ GAME_BASE+$03E0C6


Sh2ProbeRun:
        movem.l d2-d7/a2-a3,-(sp)

        lea     (SH2P_RESULT).l,a3
        move.l  #'SH2P',(a3)                    ; +$00 magic
        clr.l   $04(a3)                         ; +$04 ping reply
        move.w  #SH2P_VECTORS,$08(a3)           ; +$08 vectors attempted
        clr.w   $0A(a3)                         ; +$0A passes
        clr.w   $0C(a3)                         ; +$0C failures
        move.w  #$FFFF,$0E(a3)                  ; +$0E first failing index
        clr.l   $10(a3)                         ; +$10 dispatcher call counter
        clr.w   $14(a3)                         ; +$14 timeouts
        clr.w   $16(a3)                         ; +$16 max poll iterations
        move.w  #$FFFF,$18(a3)                  ; +$18 min poll iterations
        clr.l   $1C(a3)                         ; +$1C benchmark: SH2 calls done
        clr.l   $20(a3)                         ; +$20 benchmark: 68K calls done
        clr.l   $24(a3)                         ; +$24 benchmark phase marker
        clr.l   $28(a3)                         ; +$28 correctness max/min polls
        clr.l   $2C(a3)                         ; +$2C benchmark: SH2, fast path
        clr.l   $30(a3)                         ; +$30 benchmark: 68K, fast path

; ---------------------------------------------------------------------------
; Transport check first.  If PING does not come back there is no point
; reporting sixteen division mismatches.
; ---------------------------------------------------------------------------
        move.w  #SH2_CMD_PING,d0
        moveq   #0,d1
        moveq   #0,d2
        bsr.w   Sh2Call                         ; -> d1 = reply, d7 = polls
        move.l  d1,$04(a3)

; ---------------------------------------------------------------------------
; Division vectors.  Each is run through both implementations and compared.
; ---------------------------------------------------------------------------
        lea     (Sh2ProbeVectors).l,a2
        lea     $40(a3),a0                      ; per-vector detail block
        moveq   #0,d6                           ; d6 = vector index
.next:
        move.l  (a2)+,d4                        ; d4 = dividend
        move.l  (a2)+,d5                        ; d5 = divisor

        ; --- reference: the game's own routine -------------------------
        move.l  d4,d0
        move.l  d5,d1
        jsr     (GameUnsignedDivide).l
        move.l  d0,(a0)                         ; +$00 68K quotient
        move.l  d1,$04(a0)                      ; +$04 68K remainder
        move.l  d0,d2                           ; keep for the comparison
        move.l  d1,d3

        ; --- subject: the SH2 -------------------------------------------
        ; Sh2Call clobbers d0-d2/d7/a1 and returns in d1/d2, so the reference
        ; results in d2/d3 go on the stack and the SH2's answers are stored
        ; before anything is restored.  Restoring over the results is exactly
        ; the bug this probe caught on its first run.
        move.l  d2,-(sp)                        ; 68K quotient
        move.l  d3,-(sp)                        ; 68K remainder
        move.w  #SH2_CMD_UDIV32,d0
        move.l  d4,d1
        move.l  d5,d2
        bsr.w   Sh2Call                         ; -> d1 = quot, d2 = rem
        move.l  d1,$08(a0)                      ; +$08 SH2 quotient
        move.l  d2,$0C(a0)                      ; +$0C SH2 remainder
        move.l  (sp)+,d3
        move.l  (sp)+,d2

        ; --- compare ------------------------------------------------------
        cmp.l   $08(a0),d2
        bne.s   .fail
        cmp.l   $0C(a0),d3
        bne.s   .fail
        addq.w  #1,$0A(a3)
        bra.s   .step
.fail:
        addq.w  #1,$0C(a3)
        cmpi.w  #$FFFF,$0E(a3)
        bne.s   .step
        move.w  d6,$0E(a3)                      ; remember the first one
.step:
        lea     $10(a0),a0
        addq.w  #1,d6
        cmpi.w  #SH2P_VECTORS,d6
        blt.s   .next

        move.l  (SH2P_COUNT).l,$10(a3)          ; what the SH2 thinks it did
        move.w  $16(a3),$28(a3)                 ; freeze the correctness-phase
        move.w  $18(a3),$2A(a3)                 ; poll spread before benching

; ---------------------------------------------------------------------------
; Is offloading worth it?  Two equal batches of the same division, one over
; the comm ports and one in-place, each incrementing its own counter.  The
; counters are read from outside every few frames, so the frame at which each
; saturates is a directly measured duration -- no cycle-table arithmetic.
;
; The vector is deliberately the 68000's worst case: a divisor >= $10000 sends
; UnsignedDivide down the 16-iteration shift-subtract path.  That is the most
; favourable case offloading will ever get, so if it loses here it loses
; everywhere.
; ---------------------------------------------------------------------------
        move.l  #'BEG1',$24(a3)
        move.l  #SH2P_BENCH,d6
.bench_sh2:
        move.w  #SH2_CMD_UDIV32,d0
        move.l  #$12345678,d1
        move.l  #$00ABCDEF,d2
        bsr.w   Sh2Call
        addq.l  #1,$1C(a3)
        subq.l  #1,d6
        bne.s   .bench_sh2
        move.l  #'END1',$24(a3)

        move.l  #SH2P_BENCH,d6
.bench_68k:
        move.l  #$12345678,d0
        move.l  #$00ABCDEF,d1
        jsr     (GameUnsignedDivide).l
        addq.l  #1,$20(a3)
        subq.l  #1,d6
        bne.s   .bench_68k
        move.l  #'END2',$24(a3)

; Now the other end of the range.  A divisor below $10000 whose quotient fits
; in 16 bits takes UnsignedDivide's single DIVU.W path, which is the cheapest
; thing the 68000 can do here.  Measuring only the worst case would make
; offloading look better than it is.
        move.l  #SH2P_BENCH,d6
.bench_sh2_fast:
        move.w  #SH2_CMD_UDIV32,d0
        move.l  #$000003E8,d1
        move.l  #$00000007,d2
        bsr.w   Sh2Call
        addq.l  #1,$2C(a3)
        subq.l  #1,d6
        bne.s   .bench_sh2_fast
        move.l  #'END3',$24(a3)

        move.l  #SH2P_BENCH,d6
.bench_68k_fast:
        move.l  #$000003E8,d0
        move.l  #$00000007,d1
        jsr     (GameUnsignedDivide).l
        addq.l  #1,$30(a3)
        subq.l  #1,d6
        bne.s   .bench_68k_fast
        move.l  #'END4',$24(a3)

        movem.l (sp)+,d2-d7/a2-a3
        rts

; ---------------------------------------------------------------------------
; Sh2Call -- one synchronous request.
;   In:  d0.w = command, d1.l = arg 0, d2.l = arg 1
;   Out: d1.l = result 0, d2.l = result 1, d7.l = poll iterations used
;
; The command word is written last: the SH2 treats a non-zero command as the
; signal that both argument slots are already valid, and clears it to signal
; that both result slots are.
; ---------------------------------------------------------------------------
Sh2Call:
        move.l  d1,(SH2P_ARG0).l
        move.l  d2,(SH2P_ARG1).l
        move.w  d0,(SH2P_CMD).l                 ; go

        moveq   #0,d7
        move.l  #SH2P_TIMEOUT,d0
.poll:
        tst.w   (SH2P_CMD).l
        beq.s   .done
        addq.l  #1,d7
        subq.l  #1,d0
        bne.s   .poll

        ; Timed out.  Record it and give the caller recognisable rubbish
        ; rather than a stale slot that might accidentally compare equal.
        lea     (SH2P_RESULT).l,a1
        addq.w  #1,$14(a1)
        move.l  #$DEADBEEF,d1
        move.l  #$DEADBEEF,d2
        rts

.done:
        move.l  (SH2P_ARG0).l,d1
        move.l  (SH2P_ARG1).l,d2

        ; Track the spread of the round trip in poll iterations.
        lea     (SH2P_RESULT).l,a1
        cmp.w   $16(a1),d7
        bls.s   .not_max
        move.w  d7,$16(a1)
.not_max:
        cmp.w   $18(a1),d7
        bcc.s   .not_min
        move.w  d7,$18(a1)
.not_min:
        rts

; ---------------------------------------------------------------------------
; Test vectors: dividend, divisor.  Chosen to cover all three paths through
; UnsignedDivide -- the DIVU.W fast path, the two-step overflow path taken
; when the quotient exceeds 16 bits, and the shift-subtract path taken when
; the divisor reaches $10000 -- plus the boundaries between them.
; ---------------------------------------------------------------------------
Sh2ProbeVectors:
        dc.l    $000003E8,$00000007     ;  0 fast path, 1000 / 7
        dc.l    $0000FFFF,$000000FF     ;  1 fast path, exact
        dc.l    $00000000,$00000001     ;  2 zero dividend
        dc.l    $00003039,$00000001     ;  3 divide by one
        dc.l    $0001869F,$000003E8     ;  4 fast path, larger
        dc.l    $10000000,$00000002     ;  5 overflow path, quotient > 16 bits
        dc.l    $FFFFFFFF,$00000003     ;  6 overflow path, maximum dividend
        dc.l    $ABCDEF01,$00001234     ;  7 overflow path, arbitrary
        dc.l    $000F4240,$0000000A     ;  8 overflow path, 1000000 / 10
        dc.l    $FFFFFFFF,$00010000     ;  9 shift path, divisor at the boundary
        dc.l    $12345678,$00ABCDEF     ; 10 shift path, arbitrary
        dc.l    $FFFFFFFF,$FFFFFFFF     ; 11 shift path, quotient 1 remainder 0
        dc.l    $80000000,$7FFFFFFF     ; 12 shift path, quotient 1 remainder 1
        dc.l    $00000064,$00010000     ; 13 shift path, quotient 0
        dc.l    $FFFFFFFE,$FFFFFFFF     ; 14 shift path, quotient 0, rem = dividend
        dc.l    $7FFFFFFF,$00008000     ; 15 fast/overflow boundary
