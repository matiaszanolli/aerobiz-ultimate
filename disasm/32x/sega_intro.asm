; ===========================================================================
; SEGA logo intro thunk -- 32X
;
; Reached from InitGameGraphicsMode in place of `pea ($0004).w / jsr (a2)`:
; GameCommand #4, which runs InitAnimTable -- the Genesis fade-in of the SEGA
; screen, a busy-wait on $36(a5) of about 300 frames, and the pad probe whose
; result the caller tests in d0.  Six bytes for six, under SEGA_INTRO.
;
; The SH2 is started first and animates the logo on the 32X layer, opaque and
; in front, while that call fades the Genesis logo in behind it.  The SH2's
; last frames are the identity, so its logo lands exactly on the Genesis one,
; which has finished fading in by then, and blanking the layer is invisible.
; The hold is the Genesis game's own, so the boot takes exactly as long as it
; did.
;
; Stack contract.  The replaced `pea` left $00000004 on the stack -- the
; caller's `lea $2c(a7),a7` counts it -- and the call returned GameCommand's
; result in d0.  Both are reproduced.  a2 (the caller's GameCommand pointer)
; and d2 are preserved; d1/a0/a1 are dead in the caller at this point.
;
; FM is handed to the SH2 before the command and taken back only once the SH2
; has cleared MARS_RPC_CMD, by which time it has blanked the layer.  Taking it
; earlier would abort an SH2 access mid-way (KNOWN_ISSUES: FM arbitration is
; destructive).  Nothing else uses the comm registers this early in the boot.
; ===========================================================================

; Polls after the Genesis hold returns.  The SH2 finishes about 130 frames into
; a 300-frame hold, so reaching this means "never answered", not "slow".
SEGA_TIMEOUT    equ 400000

MarsSegaIntro:
; --- leave the argument the replaced `pea` would have left -----------------
        subq.l  #4,sp
        move.l  4(sp),(sp)                      ; return address down one slot
        move.l  #$00000004,4(sp)                ; the argument, where it was

; --- start the SH2; it owns the 32X VDP from here --------------------------
        ori.w   #(1<<MARS_FM),(MARS_ADAPTER).l
        move.w  #MARS_SH2_CMD_SEGA,(MARS_RPC_CMD).l

; --- the Genesis fade, hold and pad probe, as the caller would have run it --
        pea     ($0004).w
        jsr     (a2)
        addq.l  #4,sp
        move.l  d0,-(sp)                        ; GameCommand's result

; --- wait for the SH2, then take FM back -----------------------------------
        move.l  #SEGA_TIMEOUT,d1
.wait:
        tst.w   (MARS_RPC_CMD).l
        beq.s   .answered
        subq.l  #1,d1
        bne.s   .wait
; Never answered: take FM regardless and blank the layer ourselves, so a stuck
; SH2 cannot leave the logo over the rest of the game.
        andi.w  #$7FFF,(MARS_ADAPTER).l
        move.w  #MARS_MODE_BLANK,(MARS_VDP_BITMAP).l
        bra.s   .done
.answered:
        andi.w  #$7FFF,(MARS_ADAPTER).l
.done:
        move.l  (sp)+,d0
        rts
