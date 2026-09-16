; ===========================================================================
; World map on the 32X layer -- U-034 stage 2, first integration
;
; Driven from V-Blank, with no call from the game half.  The game's own screen
; id says which map plane B holds -- 7 is the world overview -- and the layer
; follows it.  The one game-half change, also under MAPSCREEN, is in
; LoadScreenGfx: it fills the map's 32x22 cells with tile 0, which is fully
; transparent (U-036), instead of placing the map tiles, so the layer shows
; through where the map was.
;
; Who does what:
;
;   switch-on   A new generation goes into MARS_MAP_STATE and FM goes to the
;               SH2.  The layer stays blank while the SH2 draws both buffers.
;   drawn       The SH2 echoes the generation in MARS_SH2_STATUS.  From the
;               next V-Blank on, FM is ours: the palette follows the game's
;               CRAM, the layer is shown with PRI = 0, and the screen is H40.
;   switch-off  FM back, layer blank, the game's own register 12 restored.
;
; The screen id moves before the screen does.  Leaving the world map, the game
; sets the new id first and then fades out, with the map still on plane B for
; the whole fade -- measured on the first turn change of a DEMO game.  So once
; the id has moved on, the layer stays while CRAM line 1 is still the world
; palette faded down, and goes when the fade reaches black, where switching it
; off cannot be seen.  If line 1 turns into anything else the layer goes at
; once, and if it lingers past MAP_LINGER_MAX frames it goes regardless.
;
; The generation is what stops a "drawn" left over from an earlier visit being
; taken for this one.  The 68000 decides when the layer appears, and it does
; so only once there is a picture and the right colours to show.
;
; H40 while the layer is visible: manual 3.3 (32x-hardware-manual.md:1121)
; lists H32 only for a blank layer.  Register 12 is forced from the game's own
; shadow every frame the layer is up -- the H40 probe's technique, measured
; there to register pixel for pixel -- and nothing is forced while the SH2 is
; still drawing, since the layer is blank and H32 is allowed.
;
; Palette.  Fades and dimmed backdrops are CRAM changes, and the layer has a
; palette of its own, so entries 16-31 are kept equal to the game's CRAM line 1
; every frame.  WriteCharUIDisplay keeps a copy of CRAM at $FF1400; in 222
; states sampled across a DEMO game, fades included, it equalled CRAM in all 64
; words every time.  Reading it costs no VDP access.
;
; Mirroring from V-Blank alone runs a frame behind.  The game writes CRAM from
; its main line just after its own V-Blank handler returns, still inside the
; blanking interval, so the new colours cover the whole next frame -- but this
; handler ran at the start of that V-Blank, before the write.  Measured: on
; every fade step the Genesis band showed the new colour and all 45,056 map
; pixels the old one.  So WriteCharUIDisplay is hooked too (MarsPaletteWrite)
; and mirrors at the moment of the write; the V-Blank copy stays, for the
; first frame of a visit and for a write that finds PEN already closed.
;
; Nothing changes while the LZ thunk holds MAP_STATE_BUSY.  It is copying out
; of the frame buffer with FM = 0 and interrupts open, and handing FM to the
; SH2 now would cut that copy short (manual :739).  The change waits a frame.
;
; Called ahead of the game's own V-Blank handler; preserves every register.
; ===========================================================================

; ---------------------------------------------------------------------------
; Fixed entry, reached from WriteCharUIDisplay in the game half in place of its
; `jsr GameCommand` -- six bytes for six, under MAPSCREEN.  Must stay first.
; ---------------------------------------------------------------------------
MarsPaletteWriteEntry:
        bra.w   MarsPaletteWrite
    if MarsPaletteWriteEntry<>MARS_PALETTE_WRITE
        fail    "palette hook entry does not match definitions_32x.asm"
    endif

GAME_SCREEN_ID      equ $00FF9A1C   ; analysis/RAM_MAP.md; LoadScreen writes 0-6
GAME_SCREEN_WORLD   equ 7           ; written by LoadScreenGfx
GAME_VDP_REG12      equ $00FFF01C   ; CmdSetVDPReg's shadow of register 12
GAME_CRAM_SHADOW    equ $00FF1400   ; WriteCharUIDisplay's copy of CRAM
GAME_CRAM_LINE1     equ GAME_CRAM_SHADOW+16*2
GAME_COMMAND        equ GAME_BASE+$000D64
GAME_MAP_PALETTE    equ GAME_BASE+$07677E   ; the world palette LoadScreenGfx loads
MAP_LINGER_MAX      equ 48              ; a turn fade takes about 20 frames
MAP_SIDEBAR_ENTRY   equ 5               ; line 1 colour the sidebar takes, $0400

MapScreenVBlank:
        movem.l d0-d4/a0-a2,-(sp)
        move.w  (MARS_MAP_STATE).l,d1
        btst    #MAP_STATE_BUSY_BIT,d1
        bne.w   .hold                           ; the LZ thunk owns FM

        cmpi.w  #GAME_SCREEN_WORLD,(GAME_SCREEN_ID).l
        bne.s   .want_off

        btst    #MAP_STATE_ON_BIT,d1
        beq.s   .switch_on
        andi.w  #MAP_STATE_LINGER,d1
        beq.s   .on                             ; nothing to forget
        andi.w  #($FFFF-MAP_STATE_LINGER),(MARS_MAP_STATE).l  ; back on the map
        bra.s   .on

.switch_on:
        addi.w  #MAP_STATE_GEN_STEP,d1          ; a new generation
        andi.w  #MAP_STATE_GEN,d1
        ori.w   #MAP_STATE_ON,d1
        ori.w   #(1<<MARS_FM),(MARS_ADAPTER).l  ; the SH2 may draw
        move.w  d1,(MARS_MAP_STATE).l           ; BUSY is clear: this is all of it
        bra.w   .done

.on:
        bsr.w   MapSh2WantsFm
        bne.w   .done                           ; still drawing
        andi.w  #$7FFF,(MARS_ADAPTER).l         ; FM = 0: palette and mode are ours
        bsr.w   MapMirrorPalette
        move.w  #MARS_MODE_PACKED,(MARS_VDP_BITMAP).l   ; PRI = 0
        bra.s   .force_h40

.want_off:
        btst    #MAP_STATE_ON_BIT,d1
        beq.w   .done
        bsr.w   MapLine1Faded
        ble.s   .switch_off                     ; black, or not the world palette
        move.w  d1,d0
        andi.w  #MAP_STATE_LINGER,d0
        cmpi.w  #MAP_LINGER_MAX*MAP_STATE_LINGER_STEP,d0
        bhs.s   .switch_off                     ; outstayed: go regardless
        addi.w  #MAP_STATE_LINGER_STEP,(MARS_MAP_STATE).l
        bra.s   .on                             ; still fading: keep following it

.switch_off:
        andi.w  #($FFFF-MAP_STATE_ON-MAP_STATE_LINGER),(MARS_MAP_STATE).l
        andi.w  #$7FFF,(MARS_ADAPTER).l         ; FM = 0: the register is ours
        move.w  #MARS_MODE_BLANK,(MARS_VDP_BITMAP).l
        moveq   #0,d0
        move.b  (GAME_VDP_REG12).l,d0           ; the game's own mode again
        bra.s   .write12

.hold:
        btst    #MAP_STATE_ON_BIT,d1
        beq.w   .done
        bsr.w   MapSh2WantsFm
        bne.w   .done                           ; not shown yet: leave H32
.force_h40:
        moveq   #0,d0
        move.b  (GAME_VDP_REG12).l,d0
        ori.b   #$81,d0                         ; RS1 | RS0: H40
.write12:
        ori.w   #$8C00,d0                       ; register 12 write
        move.w  d0,(VDP_CTRL).l
.done:
        movem.l (sp)+,d0-d4/a0-a2
        rts

; ---------------------------------------------------------------------------
; Does the SH2 need FM now?  Yes -- Z clear -- while the map is on and the SH2
; has not yet reported drawing this generation.  No -- Z set -- otherwise,
; including while the map is off.  Shared with the LZ thunk, which has to
; decide the same thing when it gives FM back.  Preserves every register.
; ---------------------------------------------------------------------------
MapSh2WantsFm:
        movem.l d0-d1,-(sp)
        move.w  (MARS_MAP_STATE).l,d0
        btst    #MAP_STATE_ON_BIT,d0
        beq.s   .out                            ; off: Z set
        andi.w  #MAP_STATE_GEN,d0
        ori.w   #SH2_STATUS_DRAWN,d0
        move.w  (MARS_SH2_STATUS).l,d1
        andi.w  #(SH2_STATUS_DRAWN|MAP_STATE_GEN),d1
        cmp.w   d0,d1                           ; drawn for this generation: Z set
.out:
        movem.l (sp)+,d0-d1                     ; movem leaves the flags alone
        rts

; ---------------------------------------------------------------------------
; Is CRAM line 1 still the world palette, faded?  d0.w > 0 if so, 0 if it has
; faded to black, < 0 if it is something else.  Flags follow d0.
;
; "Faded" means no channel of any entry is brighter than the ROM palette's.
; Genesis colour keeps a zero bit above each 3-bit channel, so with those bits
; set in the base, base - shadow borrows out of a guard bit exactly where a
; shadow channel is the brighter one.  Preserves every register but d0.
; ---------------------------------------------------------------------------
MAP_GUARD_BITS      equ $1110

MapLine1Faded:
        movem.l d1-d2/a0-a1,-(sp)
        lea     (GAME_CRAM_LINE1).l,a0
        lea     (GAME_MAP_PALETTE).l,a1
        moveq   #0,d0                           ; OR of the shadow
        moveq   #16-1,d2
.entry:
        move.w  (a1)+,d1
        ori.w   #MAP_GUARD_BITS,d1
        or.w    (a0),d0
        sub.w   (a0)+,d1
        andi.w  #MAP_GUARD_BITS,d1
        cmpi.w  #MAP_GUARD_BITS,d1
        bne.s   .other
        dbra    d2,.entry
        tst.w   d0
        beq.s   .out                            ; black
        moveq   #1,d0
        bra.s   .out
.other:
        moveq   #-1,d0
.out:
        movem.l (sp)+,d1-d2/a0-a1               ; movem leaves the flags alone
        tst.w   d0
        rts

; ---------------------------------------------------------------------------
; WriteCharUIDisplay's GameCommand call, then the same colours on the layer.
;
; GameCommand 8, sub 2, writes CRAM.  If that write touches line 1 while the
; map is shown, bring the shadow up to date now -- WriteCharUIDisplay is about
; to copy the same words there itself -- and mirror it.  Interrupts are held
; off across both, so a V-Blank cannot land between them and copy a shadow that
; is still stale back over the colours just written.
;
; On entry the caller's seven longword arguments are above the return address:
; command, sub, source, index * 2, count, and two more.  GameCommand's d0 is
; returned; everything else is preserved.
;
; GameCommand reads its arguments from the stack, and calling it from here puts
; this routine's return address between it and them.  So the seven arguments
; are pushed again first -- each `move.l 7*4(sp),-(sp)` reads its source before
; the predecrement, so seven of them copy the frame in order -- and dropped
; afterwards.  Calling it straight through reads everything four bytes off; the
; first build of this hook did exactly that, and the game faded to black and
; stayed there.
; ---------------------------------------------------------------------------
MPW_ARG_COUNT       equ 7
MPW_ARGS            equ 8*4+2+4         ; saved registers, saved sr, return
MPW_SOURCE          equ MPW_ARGS+2*4
MPW_INDEX2          equ MPW_ARGS+3*4
MPW_COUNT           equ MPW_ARGS+4*4

MarsPaletteWrite:
        rept    MPW_ARG_COUNT
        move.l  MPW_ARG_COUNT*4(sp),-(sp)
        endr
        jsr     (GAME_COMMAND).l                ; the call this replaces
        lea     MPW_ARG_COUNT*4(sp),sp
        movem.l d0-d4/a0-a2,-(sp)
        move.w  sr,-(sp)
        ori.w   #$0700,sr
        move.w  (MARS_MAP_STATE).l,d0
        btst    #MAP_STATE_ON_BIT,d0
        beq.s   .out                            ; no map
        bsr.w   MapSh2WantsFm
        bne.s   .out                            ; still drawing: the layer is blank
        move.l  MPW_COUNT(sp),d2
        beq.s   .out
        move.l  MPW_INDEX2(sp),d0
        cmpi.l  #32*2,d0
        bhs.s   .out                            ; starts after line 1
        move.l  d2,d1
        add.l   d1,d1
        add.l   d0,d1
        cmpi.l  #16*2,d1
        bls.s   .out                            ; ends before line 1
        cmpi.l  #64*2,d1
        bhi.s   .out                            ; not a CRAM write we understand
        movea.l MPW_SOURCE(sp),a0
        lea     (GAME_CRAM_SHADOW).l,a1
        adda.l  d0,a1
        subq.l  #1,d2
.shadow:
        move.w  (a0)+,(a1)+
        dbra    d2,.shadow
        bsr.w   MapMirrorPalette
.out:
        move.w  (sp)+,sr
        movem.l (sp)+,d0-d4/a0-a2
        rts

; ---------------------------------------------------------------------------
; d0 = Genesis colour, %0000BBB0GGG0RRR0  ->  d1 = offset of its GenesisToMars
; entry, index b<<6 | g<<3 | r.  Uses d0 and d2.
; ---------------------------------------------------------------------------
MapColourIndex:
        move.w  d0,d1
        lsr.w   #1,d1
        andi.w  #$0007,d1                       ; r
        move.w  d0,d2
        lsr.w   #2,d2
        andi.w  #$0038,d2                       ; g << 3
        or.w    d2,d1
        lsr.w   #3,d0
        andi.w  #$01C0,d0                       ; b << 6
        or.w    d0,d1
        add.w   d1,d1
        rts

; ---------------------------------------------------------------------------
; Copy CRAM line 1 into 32X palette entries 16-31, converting 9-bit Genesis
; colour to BGR555 through GenesisToMars, and give the sidebar -- index 0,
; through bit set -- line 1's entry MAP_SIDEBAR_ENTRY, so it fades with the
; screen.  FM must be 0.
;
; Packed mode allows palette access only in H and V blank (manual :1066), and a
; write in the last microsecond before PEN falls is lost (:1456).  PEN is read
; before every word and the copy stops if it has closed; the next V-Blank
; writes all sixteen again, so a late interrupt costs one frame of lag and
; never a wrong colour that stays.
; ---------------------------------------------------------------------------
MapMirrorPalette:
        lea     (GenesisToMars,pc),a2
        bsr.s   .pen
        beq.s   .out
        move.w  (GAME_CRAM_LINE1+MAP_SIDEBAR_ENTRY*2).l,d0
        bsr.w   MapColourIndex
        move.w  (a2,d1.w),d0
        ori.w   #$8000,d0                       ; through bit: in front
        move.w  d0,(MARS_PALETTE).l

        lea     (GAME_CRAM_LINE1).l,a0
        lea     (MARS_PALETTE+16*2).l,a1
        moveq   #16-1,d3
.next:
        bsr.s   .pen
        beq.s   .out                            ; closed: the next V-Blank redoes it
        move.w  (a0)+,d0
        bsr.w   MapColourIndex
        move.w  (a2,d1.w),(a1)+
        dbra    d3,.next
.out:
        rts

; Z set if palette access has closed.
.pen:
        move.w  (MARS_VDP_FBCTL).l,d4
        btst    #MARS_FB_PEN,d4
        rts

; ---------------------------------------------------------------------------
; 9-bit Genesis colour to BGR555, each 3-bit channel widened as
; (v << 2) | (v >> 1) -- the expansion tools/make_map_asset.py uses for the
; asset, so a mirrored palette at full brightness is the asset's own.
; ---------------------------------------------------------------------------
GenesisToMars:
g2m_i   set     0
        rept    512
g2m_r   set     g2m_i&7
g2m_g   set     (g2m_i>>3)&7
g2m_b   set     (g2m_i>>6)&7
        dc.w    (((g2m_b<<2)|(g2m_b>>1))<<10)|(((g2m_g<<2)|(g2m_g>>1))<<5)|((g2m_r<<2)|(g2m_r>>1))
g2m_i   set     g2m_i+1
        endr
