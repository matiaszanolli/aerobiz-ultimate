; ============================================================================
; DrawPlayerRoutes -- Draw up to 4 numbered route assignment markers on the world map for a player
; Called: ?? times.
; 300 bytes | $009E1C-$009F47
; ============================================================================
DrawPlayerRoutes:                                                  ; $009E1C
    link    a6,#-$20
    movem.l d2-d6/a2-a3,-(sp)
    move.l  $000c(a6),d5
    move.l  $0008(a6),d6
    move.w  d6,d0
    add.w   d0,d0
    movea.l #$00ff0118,a0
    move.w  (a0,d0.w),-$0002(a6)
    pea     ($0001).w
    pea     ($000F).w
    pea     -$0002(a6)
    jsr     (ROM_BASE+$005092).l
    lea     $000c(sp),sp
    move.w  d6,d0
    lsl.w   #$5,d0
    movea.l #$00ff0338,a0
    lea     (a0,d0.w),a0
    movea.l a0,a2
    clr.w   d2
.l9e64:                                                 ; $009E64
    tst.b   $0001(a2)
    beq.w   .l9f32
    cmpi.b  #$06,$0001(a2)
    beq.b   .l9e8a
    moveq   #$0,d3
    move.b  (a2),d3
    move.w  d3,d0
    ext.l   d0
    move.l  d0,-(sp)
    jsr     (ROM_BASE+$00D648).l
    addq.l  #$4,sp
    move.w  d0,d4
    bra.b   .l9ea4
.l9e8a:                                                 ; $009E8A
    moveq   #$0,d4
    move.b  (a2),d4
    move.w  d4,d0
    ext.l   d0
    move.l  d0,-(sp)
    move.w  d6,d0
    ext.l   d0
    move.l  d0,-(sp)
    jsr     (ROM_BASE+$006EEA).l
    addq.l  #$8,sp
    move.w  d0,d3
.l9ea4:                                                 ; $009EA4
    cmp.w   d5,d4
    bne.b   .l9ed4
    move.w  d3,d0
    add.w   d0,d0
    movea.l #$0005e9fa,a0
    lea     (a0,d0.w),a0
    movea.l a0,a3
    clr.l   -(sp)
    pea     ($0002).w
    pea     ($0001).w
    moveq   #$0,d0
    move.b  $0001(a3),d0
    subq.l  #$8,d0
    move.l  d0,-(sp)
    moveq   #$0,d0
    move.b  (a3),d0
    addq.l  #$8,d0
    bra.b   .l9f08
.l9ed4:                                                 ; $009ED4
    cmpi.w  #$7,d5
    bne.b   .l9f32
    move.w  d3,d0
    add.w   d0,d0
    movea.l #$0005e948,a0
    lea     (a0,d0.w),a0
    movea.l a0,a3
    clr.l   -(sp)
    pea     ($0002).w
    pea     ($0001).w
    moveq   #$0,d0
    move.b  $0001(a3),d0
    subi.l  #$c,d0
    move.l  d0,-(sp)
    moveq   #$0,d0
    move.b  (a3),d0
    addq.l  #$4,d0
.l9f08:                                                 ; $009F08
    move.l  d0,-(sp)
    move.w  d2,d0
    ext.l   d0
    addi.l  #$3b,d0
    move.l  d0,-(sp)
    pea     ($0544).w
    jsr     (ROM_BASE+$01E044).l
    pea     ($0001).w
    pea     ($000E).w
    jsr     (ROM_BASE+$000D64).l
    lea     $0024(sp),sp
.l9f32:                                                 ; $009F32
    addq.l  #$8,a2
    addq.w  #$1,d2
    cmpi.w  #$4,d2
    blt.w   .l9e64
    movem.l -$003c(a6),d2-d6/a2-a3
    unlk    a6
    rts
