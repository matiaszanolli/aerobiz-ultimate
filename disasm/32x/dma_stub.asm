; ===========================================================================
; 32X DMA thunk -- U-020
;
; The Genesis VDP's DMA source register reaches the whole 24-bit space (seven
; source bits in register 23; see PORT_ARCHITECTURE.md section 2.1), but the
; adapter does not serve $880000-$9FFFFF to a VDP-mastered cycle.  The `RV` bit
; at $A15106 -- named "ROM to VRAM DMA" in docs/32x-hardware-manual.md:432 --
; maps the cartridge at $000100-$3FFFFF for the duration, so a source in the
; bank window is re-pointed at the same bytes' own cartridge offset and fetched
; there.
;
; Reached from ConfigVDPDMA in place of its `jsr $FFF000`, a size-neutral swap
; of six bytes.  By this point ConfigVDPDMA has already:
;   - masked interrupts (`ori.w #$700,sr`), which
;     docs/32x-technical-info.md:103 requires for the whole of RV = 1
;   - programmed VDP registers $93/$94 with the transfer length
;   - programmed $95/$96/$97 with the untranslated source, which we redo
;   - staged the command word that starts the transfer in $42(a5)/$44(a5)
; a4 = VDP control port, a5 = work RAM base.  d0-d2/a0-a1 are dead afterwards.
;
; Why the windowed part runs from the stack
; -----------------------------------------
; The Mega Drive requires the control-port write that starts a ROM DMA to be
; executed from RAM, and docs/32x-hardware-manual.md:238 leaves it open whether
; the cartridge windows survive RV = 1 at all.  So that sequence must be
; RAM-resident.  There is nowhere permanent to put it: painting $FFFC80-$FFFFFF
; and $FFE000-$FFEFFF and running the game overwrote every byte of both, so the
; earlier "896 bytes free at the top of work RAM" figure was wrong -- it came
; from scanning literal displacements and missed runtime-indexed writes.
;
; The stack is the one region guaranteed free below the pointer, so the window
; body is copied there per transfer.  About 25 word moves against a DMA that
; costs thousands of cycles.  If §5.3 is ever settled on real hardware and the
; windows do survive, this can collapse to running in place from the boot half.
; ===========================================================================

MarsDmaThunk:
        move.l  $20(a5),d0                      ; DMA source, as the game sees it
        move.l  d0,d1
        andi.l  #$00F00000,d1
        cmpi.l  #MARS_GAME_WINDOW,d1
        bne.s   .stock_path

; --- Re-point registers 21-23 at the same bytes, addressed as cartridge -----
; Mirrors ConfigVDPDMA's own sequence, with the translated address.
        subi.l  #MARS_DMA_BIAS,d0               ; $9Xxxxx -> $1Xxxxx
        lsr.l   #$1,d0                          ; the VDP wants a word address
        move.l  d0,d2
        andi.l  #$ff,d0
        ori.w   #$9500,d0
        move.w  d0,(a4)
        move.l  d2,d0
        lsr.w   #$8,d0
        andi.l  #$ff,d0
        ori.w   #$9600,d0
        move.w  d0,(a4)
        move.l  d2,d0
        swap    d0
        andi.w  #$7f,d0
        ori.w   #$9700,d0
        move.w  d0,(a4)

; --- Copy the windowed sequence below the stack pointer and run it there ----
        lea     -MarsDmaWindowSize(sp),sp
        movea.l sp,a1
        lea     (MarsDmaWindow).l,a0
        move.w  #(MarsDmaWindowSize/2)-1,d0
.copy:
        move.w  (a0)+,(a1)+
        dbra    d0,.copy
        movea.l sp,a0
        jsr     (a0)                            ; pushes below the body, not over it
        lea     MarsDmaWindowSize(sp),sp
        rts

; --- A work-RAM source needs no window and no translation -------------------
; Hand off to the game's own trigger stub, which is exactly what the unpatched
; instruction did.
.stock_path:
        jmp     (MARS_STOCK_TRIGGER).l

; ---------------------------------------------------------------------------
; Copied to the stack and executed there.  Every operand is absolute or
; A4/A5-relative and the only branch is PC-relative, so it runs wherever it
; lands.  Must stay an even number of bytes.
; ---------------------------------------------------------------------------
MarsDmaWindow:
        move.w  (MARS_DREQCTL).l,d1
        bset    #MARS_RV,d1
        move.w  d1,(MARS_DREQCTL).l             ; RV = 1: cartridge at its offsets

        move.w  $42(a5),(a4)                    ; start the transfer, from RAM
        move.w  $44(a5),(a4)
.busy:
        move.w  (a4),d1                         ; drain it inside the window
        btst    #$1,d1
        bne.s   .busy

        move.w  (MARS_DREQCTL).l,d1
        bclr    #MARS_RV,d1
        move.w  d1,(MARS_DREQCTL).l             ; RV = 0: release the SH2
        rts
MarsDmaWindowEnd:

MarsDmaWindowSize   equ MarsDmaWindowEnd-MarsDmaWindow
