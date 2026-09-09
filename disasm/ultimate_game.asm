; ===========================================================================
; Aerobiz Ultimate -- 32X game half
;
; The Aerobiz Supersonic image, assembled from the same sources as the
; Genesis target but based at $900000: cartridge $100000 seen through bank 1
; of the 32X banked window (docs/32x-hardware-manual.md section 3.2.1).
;
; ROM_BASE is the single constant that rebases the game.  Shared sources must
; express ROM addresses as ROM_BASE+$xxxxxx rather than as bare literals; the
; Genesis target sets ROM_BASE to 0 so those expressions collapse back to the
; original values and the byte-identical build is preserved.
; ===========================================================================

ROM_BASE        equ $00900000

    include "modules/shared/definitions.asm"
    include "modules/shared/definitions_32x.asm"

    org ROM_BASE

; --- Vector table + ROM header ($000000-$0001FF) ---------------------------
; Inert here: the live 68000 vectors are in the boot half, at cartridge
; $000000.  Kept so every following offset matches the Genesis build exactly.
    include "sections/header.asm"

; --- Code and data sections ------------------------------------------------
    include "sections/section_000200.asm"          ; $000200-$00FFFF
    include "sections/section_010000.asm"          ; $010000-$01FFFF
    include "sections/section_020000.asm"          ; $020000-$02FFFF
    include "sections/section_030000.asm"          ; $030000-$03FFFF
    include "sections/section_040000.asm"          ; $040000-$04FFFF
    include "sections/section_050000.asm"          ; $050000-$05FFFF
    include "sections/section_060000.asm"          ; $060000-$06FFFF
    include "sections/section_070000.asm"          ; $070000-$07FFFF
    include "sections/section_080000.asm"          ; $080000-$08FFFF
    include "sections/section_090000.asm"          ; $090000-$09FFFF
    include "sections/section_0A0000.asm"          ; $0A0000-$0AFFFF
    include "sections/section_0B0000.asm"          ; $0B0000-$0BFFFF
    include "sections/section_0C0000.asm"          ; $0C0000-$0CFFFF
    include "sections/section_0D0000.asm"          ; $0D0000-$0DFFFF
    include "sections/section_0E0000.asm"          ; $0E0000-$0EFFFF
    include "sections/section_0F0000.asm"          ; $0F0000-$0FFFFF
