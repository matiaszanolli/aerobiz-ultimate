; ===========================================================================
; SEGA logo intro thunks -- 32X
;
; Two calls from InitGameGraphicsMode, each in place of a `pea (n).w / jsr (a2)`
; pair -- six bytes for six, under SEGA_INTRO:
;
;   MarsSegaCover   GameCommand #12, EnableDisplay, before the SEGA screen is
;                   drawn.  The SH2 first puts an opaque black layer in front,
;                   so nothing of that screen is seen uncovered: its logo
;                   appears at full size at once, not faded in.  Starting the
;                   SH2 only at the second call showed the finished logo before
;                   the spin -- four frames under PicoDrive, one under Ares.
;   MarsSegaIntro   GameCommand #4, which runs InitAnimTable -- the logo's
;                   palette shimmer over a busy-wait on $36(a5) of about 300
;                   frames -- and the pad probe whose result the caller tests
;                   in d0.  The SH2 animates the logo on the layer meanwhile.
;                   Its last frames are the identity, so its logo lands exactly
;                   on the Genesis one and blanking the layer is invisible.
;
; Covering is a command of its own, not the start of the animation, so the SH2
; is idle again while the 68000 draws the SEGA screen between the two calls.
; Anything handed to it in between -- through the LZ thunk, say -- would
; otherwise wait on an SH2 busy animating until it gave up.
;
; Stack contract, at both sites.  The replaced `pea` left its argument on the
; stack -- the caller's `lea` counts it -- and the call returned GameCommand's
; result in d0.  Both are reproduced.  a2 (the caller's GameCommand pointer)
; and d2 are preserved; d1/a0/a1 are dead after either call, since GameCommand
; itself preserves only d2-d7/a2-a5.
; ===========================================================================

; Polls, for each wait.  The SH2 covers the screen within a few frames and
; finishes the animation about 130 frames into a 300-frame hold, so reaching
; this means "never answered", not "slow".
SEGA_TIMEOUT    equ 400000

; --- fixed entries -----------------------------------------------------------
; The game half reaches these by address; definitions_32x.asm must agree.
MarsSegaCoverEntry:
        bra.w   MarsSegaCover
MarsSegaIntroEntry:
        bra.w   MarsSegaIntro
    if (MarsSegaCoverEntry<>MARS_SEGA_COVER)|(MarsSegaIntroEntry<>MARS_SEGA_INTRO)
        fail    "SEGA intro entries do not match definitions_32x.asm"
    endif

; --- in place of `pea ($000C).w / jsr (a2)` ----------------------------------
MarsSegaCover:
        move.l  (sp),-(sp)                      ; return address down one slot
        move.l  #$0000000C,4(sp)                ; the argument, where it was
        moveq   #MARS_SH2_CMD_SEGA_COVER,d0
        bsr.s   SegaStart
        bsr.s   SegaFinish                      ; layer up, FM back
        pea     ($000C).w
        jsr     (a2)
        addq.l  #4,sp
        rts

; --- in place of `pea ($0004).w / jsr (a2)` ----------------------------------
MarsSegaIntro:
        move.l  (sp),-(sp)
        move.l  #$00000004,4(sp)
        moveq   #MARS_SH2_CMD_SEGA,d0
        bsr.s   SegaStart
        pea     ($0004).w                       ; the Genesis hold and pad probe
        jsr     (a2)
        addq.l  #4,sp
        bra.s   SegaFinish                      ; returns to the caller, d0 intact

; --- d0.w = command: give the SH2 FM, then the command ------------------------
; FM arbitration is destructive (KNOWN_ISSUES), so it is handed over before the
; command and taken back only once the SH2 has cleared MARS_RPC_CMD.  The comm
; registers are not gated by FM (manual 3.5).
SegaStart:
        ori.w   #(1<<MARS_FM),(MARS_ADAPTER).l
        move.w  d0,(MARS_RPC_CMD).l
        rts

; --- wait for the SH2, then take FM back.  d1 is scratch; d0 is untouched -----
SegaFinish:
        move.l  #SEGA_TIMEOUT,d1
.wait:
        tst.w   (MARS_RPC_CMD).l
        beq.s   .answered
        subq.l  #1,d1
        bne.s   .wait
; Never answered: take FM regardless and blank the layer ourselves, so a stuck
; SH2 cannot leave it over the rest of the game.
        andi.w  #$7FFF,(MARS_ADAPTER).l
        move.w  #MARS_MODE_BLANK,(MARS_VDP_BITMAP).l
        rts
.answered:
        andi.w  #$7FFF,(MARS_ADAPTER).l
        rts
