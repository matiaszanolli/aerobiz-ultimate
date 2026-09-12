; ===========================================================================
; SH2 LZ decompression thunk -- U-046
;
; Reached from LZ_Decompress's entry in place of its first eight bytes, a
; size-neutral swap under `ifne ROM_BASE` exactly like UnsignedDivide's.
; Patching the routine rather than its 92 call sites is the whole point: one
; edit covers every screen load in the game.
;
; Why it is worth the round trip, where U-044's divide was not: U-046 measured
; the 68000 at 285 cycles per output byte and the SH2 at 59.7, which is 14x in
; wall clock. The largest block in the game costs the 68000 62 frames and the
; SH2 4.4. Against that the ~560-cycle comm handshake is noise -- this is batch
; work, which is exactly the shape U-039 said would clear the break-even.
;
;   In:  4(sp) = destination in 68000 work RAM, 8(sp) = compressed source
;   Out: d0.l  = bytes written, as the stock routine returns
;
; d2-d4/a2-a4 are untouched, so the caller sees the same preservation the
; stock routine gives. d0/d1/a0/a1 are scratch there too.
;
; Transport: the SH2 cannot reach 68000 work RAM and the 68000 cannot reach
; SDRAM, so the bytes come back through the 32X frame buffer, which the
; shipping build leaves entirely unused (the layer is blanked, M3).
; ===========================================================================

; A stuck SH2 must not hang a screen load.  Far above any plausible latency, so
; reaching it means "never answered", not "slow" -- and then we simply do the
; work on the 68000, which is what the fallback below is for.
SH2LZ_TIMEOUT   equ 400000

; Where the two replaced instructions continue.  LZ_Decompress is at $003FEC;
; the movem and the first movea occupy eight bytes.
GameLzResume    equ GAME_BASE+$003FF4

; Bank 1 maps cartridge $100000-$1FFFFF at $900000, and the SH2 sees the
; cartridge from $02000000 through its cached alias, so a 68000 game-half
; address plus this constant is the same bytes as the SH2 addresses them.
; Cached rather than cache-through on purpose: the stream is read strictly
; forwards, so one 16-byte line fill serves 16 bytes of it.
SH2LZ_CART_BIAS equ $01800000


MarsSh2Lz:
        move.w  sr,-(sp)
        ori.w   #$0700,sr                       ; the four comm slots are one
                                                ; shared resource; an interrupt
                                                ; decompressing mid-call would
                                                ; read another call's results

; --- hand the job over ------------------------------------------------------
; FM = 1 gives the SH2 the frame buffer.  The comm registers are not gated by
; FM (manual 3.5), so the handshake still works while it is set.
        ori.w   #(1<<MARS_FM),(MARS_ADAPTER).l

        move.l  $A(sp),d0                       ; compressed source, 68000 view
        addi.l  #SH2LZ_CART_BIAS,d0
        move.l  d0,(MARS_RPC_ARG0).l
        move.l  #MARS_LZ_FB_OFFSET,(MARS_RPC_ARG1).l
        move.l  #SH2LZ_TIMEOUT,d1
        move.w  #MARS_SH2_CMD_LZ_JOB,(MARS_RPC_CMD).l

.wait:
        tst.w   (MARS_RPC_CMD).l
        beq.s   .answered
        subq.l  #1,d1
        bne.s   .wait
        bra.w   .fallback

.answered:
        move.l  (MARS_RPC_ARG0).l,d0            ; bytes written
        andi.w  #$7FFF,(MARS_ADAPTER).l         ; FM = 0: our turn to read it

; --- copy the result into the caller's buffer -------------------------------
; The destination is read while the saved SR is still on the stack, because
; popping it moves every offset by two.  Getting that wrong is silent: the copy
; runs, reads the right bytes and writes them somewhere harmless, and the
; caller sees an untouched buffer.
        movea.l $6(sp),a0                       ; destination
        lea     (MARS_LZ_FB_ADDR).l,a1

; Interrupts come back on before the copy: the largest block is ~14,000 words
; and holding them off for that long would cost a V-Blank, which is a worse
; bargain than the copy itself.
        move.w  (sp)+,sr

        tst.l   d0
        beq.s   .done                           ; nothing to copy
        move.l  d0,d1
        addq.l  #1,d1
        lsr.l   #1,d1                           ; words, rounding up
        subq.l  #1,d1                           ; dbra counts to -1
.copy:
        move.w  (a1)+,(a0)+
        dbra    d1,.copy
.done:
        rts

; --- the SH2 never answered -------------------------------------------------
; Undo everything and run the stock 68000 routine, re-creating the two
; instructions the patch displaced.  A slow screen load beats a hung one.
.fallback:
        andi.w  #$7FFF,(MARS_ADAPTER).l
        move.w  (sp)+,sr
        movem.l d2-d4/a2-a4,-(sp)
        movea.l $1C(sp),a0
        jmp     (GameLzResume).l
