; ===========================================================================
; Aerobiz Ultimate -- 32X boot half
;
; Assembles cartridge $000000-$0FFFFF: the 32X header, the Sega initial
; program, the 68000 bring-up glue and the SH2 program image.
;
; This half is linked at $880000, the FIXED cartridge window under ADEN = 1
; (docs/32x-hardware-manual.md section 3.5), so all of it stays addressable
; regardless of which bank is selected.
;
; The game half is a separate assembly at $900000; the Makefile concatenates
; the two.  See PORT_ARCHITECTURE.md section 2.
; ===========================================================================

CART_BASE       equ $00880000           ; cartridge $000000 via the fixed window
GAME_BASE       equ $00900000           ; cartridge $100000 via bank 1
GameEntryPoint  equ GAME_BASE+$000200   ; Aerobiz's own reset entry, rebased

; --- SH2 image placement, mirrored into the MARS user header ---------------
; Kept in step with disasm/sh2/sh2.lds by the build; the sizes come from the
; generated include below.
SH2_ROM_OFFSET  equ $00010000           ; cartridge byte offset of the image
SH2_MASTER_VBR  equ $06000000
SH2_SLAVE_VBR   equ $06000140
SH2_MASTER_START equ $06000280

    include "modules/shared/definitions.asm"
    include "modules/shared/definitions_32x.asm"

; Generated: MARS_APP_ENTRY / MARS_INIT_SIZE from the extracted Sega block,
; SH2_IMAGE_SIZE and SH2_SLAVE_START from the linked SH2 image.
    include "../build/mars_init.inc"
    include "../build/sh2_image.inc"

    org CART_BASE

    include "32x/mars_header.asm"

; ---------------------------------------------------------------------------
; SH2 program image -- cartridge $010000
; Copied to SDRAM by the 32X boot ROM per the MARS user header (manual 5.1).
; ---------------------------------------------------------------------------
    dcb.b   (CART_BASE+SH2_ROM_OFFSET)-*,$FF
    incbin  "build/sh2_image.bin"

; --- Pad the boot half out to a full megabyte ------------------------------
    dcb.b   (CART_BASE+$100000)-*,$FF
