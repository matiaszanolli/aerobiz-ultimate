; ===========================================================================
; Sega 32X (MARS) hardware definitions
;
; Every value below is cited to docs/32x-hardware-manual.md.
; Do not add an equate here without a section citation.
; ===========================================================================

; ---------------------------------------------------------------------------
; 68000-side system registers -- manual 3.2.1
; ---------------------------------------------------------------------------
MARS_ADAPTER        equ $00A15100   ; Adapter control: FM / REN / RES / ADEN
MARS_INTCTL         equ $00A15102   ; Interrupt control: INTS / INTM
MARS_BANKSET        equ $00A15104   ; Bank set: BK1 / BK0 -> window at $900000
MARS_DREQCTL        equ $00A15106   ; DREQ control: FULL / 68S / RV
MARS_DREQ_SRC_H     equ $00A15108   ; 68K->SH DREQ source address, high word
MARS_DREQ_SRC_L     equ $00A1510A   ; 68K->SH DREQ source address, low word
MARS_DREQ_DST_H     equ $00A1510C   ; 68K->SH DREQ destination address, high word
MARS_DREQ_DST_L     equ $00A1510E   ; 68K->SH DREQ destination address, low word
MARS_DREQ_LEN       equ $00A15110   ; 68K->SH DREQ length, in words, 4-word units
MARS_FIFO           equ $00A15112   ; DREQ FIFO write port
MARS_SEGATV         equ $00A1511A   ; SEGA TV register (CM) -- reserved, do not use

; 8-word bidirectional communication port -- manual 3.2.1 / 3.3
MARS_COMM0          equ $00A15120
MARS_COMM1          equ $00A15122
MARS_COMM2          equ $00A15124
MARS_COMM3          equ $00A15126
MARS_COMM4          equ $00A15128
MARS_COMM5          equ $00A1512A
MARS_COMM6          equ $00A1512C
MARS_COMM7          equ $00A1512E

; Boot handshake slots -- manual 5.1.
;
; The boot-ROM flow chart's "comm 0, 4, 8" are BYTE offsets into the comm area,
; not comm-register indices.  The boot ROM writes the master's 'M_OK' as a
; longword at $A15120 and the slave's 'S_OK' as a longword at $A15124 -- i.e.
; over COMM0/COMM1 and COMM2/COMM3.  Confirmed against a running 32X BIOS
; (U-001); reading "comm4" as MARS_COMM4 ($A15128) hangs the 68000 forever.
MARS_COMM_MOK       equ $00A15120   ; master ready, longword 'M_OK'
MARS_COMM_SOK       equ $00A15124   ; slave ready,  longword 'S_OK'

; PWM -- manual 3.4
MARS_PWM_CTL        equ $00A15130   ; TM3-0 / RTP / RMD1-0 / LMD1-0
MARS_PWM_CYCLE      equ $00A15132   ; sample cycle (NTSC base 23.01 MHz)
MARS_PWM_LCH        equ $00A15134   ; L pulse width (FULL / EMPTY readable)
MARS_PWM_RCH        equ $00A15136   ; R pulse width
MARS_PWM_MONO       equ $00A15138   ; writes both L and R

; ---------------------------------------------------------------------------
; Adapter control bits -- manual 3.2.1
; ---------------------------------------------------------------------------
MARS_ADEN           equ 0           ; adapter enable   (set by initial program)
MARS_RES            equ 1           ; SH2 reset cancel (set by initial program)
MARS_REN            equ 7           ; SH2 reset enable
MARS_FM             equ 15          ; VDP access authority: 0 = MD, 1 = SH2

; DREQ control bits -- manual 3.2.1
MARS_RV             equ 0           ; ROM-to-VRAM DMA window; blocks SH2 ROM access
MARS_68S            equ 2           ; CPU-write DREQ start
MARS_FULL           equ 7           ; DREQ FIFO full (read only)

; Bank select values for MARS_BANKSET -- manual 3.2.1
MARS_BANK0          equ 0           ; $900000 -> cart $000000-$0FFFFF
MARS_BANK1          equ 1           ; $900000 -> cart $100000-$1FFFFF
MARS_BANK2          equ 2           ; $900000 -> cart $200000-$2FFFFF
MARS_BANK3          equ 3           ; $900000 -> cart $300000-$3FFFFF

; ---------------------------------------------------------------------------
; 68000-side 32X VDP and palette -- manual 3.1 (MD memory map, ADEN = 1)
; Accessible only while FM = 0.  Palette is word access only.
; ---------------------------------------------------------------------------
MARS_VDP_BASE       equ $00A15180
MARS_PALETTE        equ $00A15200   ; 256 words
MARS_FRAMEBUFFER    equ $00840000   ; framebuffer, MD view
MARS_OVERWRITE      equ $00860000   ; overwrite image (0 words are skipped)

; ---------------------------------------------------------------------------
; 68000 cartridge windows under ADEN = 1 -- manual 3.5
; ---------------------------------------------------------------------------
MARS_ROM_FIXED      equ $00880000   ; -> cart $000000-$07FFFF, always mapped
MARS_ROM_BANKED     equ $00900000   ; -> 1 MB selected by MARS_BANKSET

; ---------------------------------------------------------------------------
; SH2-side addresses, cache-through -- manual 3.1 / 3.2.2 / 3.4
; System and VDP registers MUST be accessed cache-through.
; ---------------------------------------------------------------------------
SH2_SYSREG          equ $20004000   ; interrupt mask: FM/ADEN/CART/HEN/V/H/CMD/PWM
SH2_HCOUNT          equ $20004004   ; H interrupt line interval
SH2_DREQCTL         equ $20004006
SH2_DREQ_SRC        equ $20004008
SH2_DREQ_DST        equ $2000400C
SH2_DREQ_LEN        equ $20004010
SH2_FIFO            equ $20004012   ; DMA source for channel 0 external request
SH2_VRES_CLR        equ $20004014
SH2_VINT_CLR        equ $20004016
SH2_HINT_CLR        equ $20004018
SH2_CMD_CLR         equ $2000401A
SH2_PWM_CLR         equ $2000401C
SH2_COMM0           equ $20004020   ; same 8 words as MARS_COMM0..7
SH2_PWM_CTL         equ $20004030
SH2_PWM_CYCLE       equ $20004032
SH2_PWM_LCH         equ $20004034
SH2_PWM_RCH         equ $20004036
SH2_PWM_MONO        equ $20004038
SH2_VDP_BASE        equ $20004100
SH2_PALETTE         equ $20004200
SH2_FRAMEBUFFER     equ $24000000
SH2_OVERWRITE       equ $24020000
SH2_SDRAM           equ $26000000   ; 256 KB; cached view is $06000000
SH2_SDRAM_CACHED    equ $06000000
SH2_ROM             equ $22000000   ; cartridge; unreadable while RV = 1

; SH2 interrupt levels -- manual 3.2.2
SH2_LEVEL_VRES      equ 14
SH2_LEVEL_VINT      equ 12
SH2_LEVEL_HINT      equ 10
SH2_LEVEL_CMD       equ 8
SH2_LEVEL_PWM       equ 6

; ---------------------------------------------------------------------------
; 32X VDP registers -- manual 3.2 / 3.3
; MD-side addresses; SH2-side equivalents are SH2_VDP_BASE + the same offset.
; MD access requires FM = 0; SH2 access requires FM = 1.
; ---------------------------------------------------------------------------
MARS_VDP_BITMAP     equ $00A15180   ; PAL / PRI / 240 / M1 / M0
MARS_VDP_SHIFT      equ $00A15182   ; SFT: 1-dot left shift, packed pixel only
MARS_VDP_FILL_LEN   equ $00A15184   ; fill word count minus 1 (0-255)
MARS_VDP_FILL_ADDR  equ $00A15186   ; fill start address; A8-A1 auto-increment
MARS_VDP_FILL_DATA  equ $00A15188   ; writing here starts the fill
MARS_VDP_FBCTL      equ $00A1518A   ; VBLK / HBLK / PEN / FEN / FS

; Bitmap mode register fields -- manual 3.2
MARS_MODE_BLANK     equ %00         ; initial value
MARS_MODE_PACKED    equ %01         ; 8 bpp through the 256-word palette
MARS_MODE_DIRECT    equ %10         ; 16 bpp, 15 bits of colour + priority bit
MARS_MODE_RUNLEN    equ %11         ; run length, palette indexed
MARS_BM_240         equ 6           ; 240-line mode (PAL only)
MARS_BM_PRI         equ 7           ; 0 = MD in front, 1 = 32X in front
MARS_BM_PAL         equ 15          ; read only: 0 = PAL, 1 = NTSC

; Frame buffer control fields -- manual 3.2
MARS_FB_FS          equ 0           ; frame buffer swap select
MARS_FB_FEN         equ 1           ; read only: 1 = fill in progress, do not touch
MARS_FB_PEN         equ 13          ; read only: 1 = palette access permitted
MARS_FB_HBLK        equ 14          ; read only
MARS_FB_VBLK        equ 15          ; read only

; ---------------------------------------------------------------------------
; Display constraint -- manual 3.3
; While the 32X layer is not in blank mode, the Genesis VDP must run at a
; resolution equal to the 32X resolution: 320x224 (H40) or 320x240.
; A 256-pixel-wide (H32) Genesis mode is only legal with the 32X layer blanked.
; ---------------------------------------------------------------------------
MARS_SCREEN_W       equ 320
MARS_SCREEN_H       equ 224

; Frame buffer is in Line Table Format -- manual 3.3 "Line Table Format":
; 256 words at the head of each page; entry N holds the word address of the
; pixel data for line N.  A line is only displayed once its entry is written.
MARS_FB_LINETAB     equ 512         ; bytes: 256 words of line table at page head
MARS_FB_PAGE_SIZE   equ $20000      ; 1 Mbit = 128 KB per page

; ---------------------------------------------------------------------------
; 32X DMA stub -- PORT_ARCHITECTURE.md section 2.1
;
; The Genesis VDP cannot fetch a DMA source from $880000-$9FFFFF, which is why
; the adapter carries an "RV: ROM to VRAM DMA" bit at all.  With RV = 1 the
; cartridge is visible at its own offsets, so a source in the bank window is
; translated to the same data's cartridge offset for the duration.
; ---------------------------------------------------------------------------
MARS_GAME_WINDOW    equ $00900000   ; bank 1: where the game image is addressed
MARS_CART_OFFSET    equ $00100000   ; the same data at its own cartridge offset
MARS_DMA_BIAS       equ MARS_GAME_WINDOW-MARS_CART_OFFSET

; The DMA thunk lives in the boot half at a FIXED cartridge offset, because the
; game half is a separate assembly and cannot see the boot half's symbols.  Keep
; this in step with the pad in disasm/32x/md_main.asm.
MARS_DMA_THUNK      equ $00880900   ; cartridge $000900 via the fixed window

; SH2 math thunk -- U-039/U-044.  Same reasoning as the DMA thunk above: the
; game half is assembled separately, so it can only reach the boot half at a
; fixed address.  Keep in step with the pad in md_main.asm.
MARS_SH2_UDIV       equ $00880A00   ; cartridge $000A00 via the fixed window
MARS_SH2_LZ         equ $00880B00   ; cartridge $000B00 via the fixed window

; Scratch region of the 32X frame buffer used to hand decompressed bytes back
; to the 68000.  Past the 256-word line table plus 224 lines of 320 pixels
; ($11A40), so it cannot collide with a displayed image; 56 KB remain, and the
; largest compressed block in the game expands to 27,872 bytes.
MARS_LZ_FB_OFFSET   equ $00012000
MARS_LZ_FB_ADDR     equ MARS_FRAMEBUFFER+MARS_LZ_FB_OFFSET

; Comm-register RPC.  Slots and command numbers must match
; disasm/sh2/master/rpc.c.  COMM0/COMM2 carry the boot handshake but are free
; once the 68000 has cleared them to release the SH2s.
MARS_RPC_CMD        equ MARS_COMM0  ; word: command; 0 = idle / complete
MARS_RPC_ARG0       equ MARS_COMM2  ; long: argument 0 -> result 0
MARS_RPC_ARG1       equ MARS_COMM4  ; long: argument 1 -> result 1
MARS_RPC_COUNT      equ MARS_COMM6  ; long: dispatcher's own call counter

MARS_SH2_CMD_PING   equ $0001
MARS_SH2_CMD_UDIV32 equ $0002
MARS_SH2_CMD_FBTEST equ $0003
MARS_SH2_CMD_MAPTEST equ $0004
MARS_SH2_CMD_ZOOM   equ $0005
MARS_SH2_CMD_TIMING equ $0006
MARS_SH2_CMD_LZ     equ $0007
MARS_SH2_CMD_LZ_JOB equ $0008
MARS_SH2_CMD_AFFINE equ $0009
MARS_STOCK_TRIGGER  equ $00FFF000   ; the game's own 10-byte RAM trigger stub
