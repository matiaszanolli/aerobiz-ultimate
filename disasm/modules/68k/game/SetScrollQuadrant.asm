; ============================================================================
; SetScrollQuadrant -- Select scroll plane geometry via lookup table
;
; (d2,d3) index the byte table at $04737E; the byte is issued as $9000|value
; through GameCommand, which is a write to VDP register 16 -- plane size, not a
; palette register as this comment said until 2026-09-12.  d2 selects VSZ and
; d3 HSZ.  It then stores the matching cell dimensions: $FFA77E = d3*32+32, the
; plane width and the tile-row multiply factor every BAT address goes through,
; and $FFA77C = d2*32+32, the height.
;
; Called from 8 sites.  Note InitScrollModes reaches it by bsr.w, so a grep for
; `jsr SetScrollQuadrant` finds only 7 and misses the one that runs at startup.
; Nothing reaches it indirectly: $005518 appears in the ROM as no jsr target
; and no longword.
; 114 bytes | $005518-$005589
; ============================================================================
SetScrollQuadrant:                                                  ; $005518
    movem.l d2-d4,-(sp)
    move.l  $0014(sp),d2
    move.l  $0010(sp),d3
    cmpi.w  #$3,d3
    bhi.b   .l5530
    cmpi.w  #$3,d2
    bls.b   .l5534
.l5530:                                                 ; $005530
    clr.w   d3
    clr.w   d2
.l5534:                                                 ; $005534
    move.w  d2,d0
    lsl.w   #$2,d0
    add.w   d3,d0
    movea.l #ROM_BASE+$0004737e,a0
    move.b  (a0,d0.w),d4
    andi.l  #$ff,d4
    tst.w   d4
    bne.b   .l5552
    clr.w   d3
    clr.w   d2
.l5552:                                                 ; $005552
    moveq   #$0,d0
    move.w  d4,d0
    ori.l   #$9000,d0
    move.l  d0,-(sp)
    clr.l   -(sp)
    jsr     (ROM_BASE+$000D64).l
    addq.l  #$8,sp
    move.w  d3,d0
    lsl.w   #$5,d0
    addi.w  #$20,d0
    move.w  d0,($00FFA77E).l
    move.w  d2,d0
    lsl.w   #$5,d0
    addi.w  #$20,d0
    move.w  d0,($00FFA77C).l
    movem.l (sp)+,d2-d4
    rts
    dc.w    $2F02,$242F,$0008; $00558A
; === Translated block $005590-$0058FC ===
; 13 functions, 876 bytes
