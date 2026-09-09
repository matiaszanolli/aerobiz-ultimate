; ===========================================================================
; Aerobiz Ultimate -- 32X cartridge header
; Cartridge $000000-$0004D3
;
; Layout and every field are per docs/32x-hardware-manual.md sections 3.1,
; 3.5 and 5.1/5.2, cross-checked against a retail 32X cartridge header.
; ===========================================================================

; ---------------------------------------------------------------------------
; 68000 exception vectors -- cartridge $000000-$0000FF
;
; Under ADEN = 1 the cartridge is not at $000000 any more, so every vector
; points at a trampoline in the FIXED window ($880000-$8FFFFF, cartridge
; $000000-$07FFFF).  The trampolines are bank independent; they jump on into
; the game image, which lives in bank 1 at $900000.  See PORT_ARCHITECTURE.md
; section 2.
; ---------------------------------------------------------------------------
        dc.l    $00FFF000               ; $000: initial supervisor stack
        dc.l    $000003F0               ; $004: reset -> Sega initial program

        dc.l    TrapBusError            ; $008: bus error
        dc.l    TrapAddressError        ; $00C: address error
        dc.l    TrapIllegal             ; $010: illegal instruction
        dc.l    TrapZeroDivide          ; $014: zero divide
        dc.l    TrapChk                 ; $018: CHK
        dc.l    TrapTrapv               ; $01C: TRAPV
        dc.l    TrapPrivilege           ; $020: privilege violation
        dc.l    TrapTrace               ; $024: trace
        dc.l    TrapLineA               ; $028: line-A emulator
        dc.l    TrapLineF               ; $02C: line-F emulator

        dc.l    TrapReserved            ; $030
        dc.l    TrapReserved            ; $034
        dc.l    TrapReserved            ; $038
        dc.l    TrapUninitialized       ; $03C

        dcb.l   8,0                     ; $040-$05F: reserved
        dc.l    0                       ; $060: spurious interrupt

        dc.l    0                       ; $064: level 1 (unused on Genesis)
        dc.l    IntLevel2Ext            ; $068: level 2 -- EXT
        dc.l    0                       ; $06C: level 3
        dc.l    IntLevel4HBlank         ; $070: level 4 -- H-Blank
        dc.l    0                       ; $074: level 5
        dc.l    IntLevel6VBlank         ; $078: level 6 -- V-Blank
        dc.l    0                       ; $07C: level 7 -- NMI

        dcb.l   16,0                    ; $080-$0BF: TRAP #0-#15
        dcb.l   16,0                    ; $0C0-$0FF: reserved

; ---------------------------------------------------------------------------
; MEGA Drive / 32X ROM header -- cartridge $000100-$0001FF
; The console name must read "SEGA 32X" for the adapter to be recognised.
; ---------------------------------------------------------------------------
        dc.b    'SEGA 32X U      '                              ; $100 console
        dc.b    '(C)T-76 2026.SEP'                              ; $110 copyright
        dc.b    'AEROBIZ ULTIMATE                                ' ; $120 domestic
        dc.b    'AEROBIZ ULTIMATE                                ' ; $150 overseas
        dc.b    'GM T-76136 -00'                                 ; $180 serial
        dc.w    $0000                                           ; $18E checksum
        dc.b    'J6              '                              ; $190 I/O support
        dc.l    $00000000                                       ; $1A0 ROM start
        dc.l    $001FFFFF                                       ; $1A4 ROM end
        dc.l    $00FF0000                                       ; $1A8 RAM start
        dc.l    $00FFFFFF                                       ; $1AC RAM end
        dc.b    'RA',$F8,$20                                    ; $1B0 SRAM present
        dc.l    $00200001                                       ; $1B4 SRAM start
        dc.l    $00203FFF                                       ; $1B8 SRAM end
        dcb.b   12,' '                                          ; $1BC modem
        dcb.b   40,' '                                          ; $1C8 notes
        dc.b    'U               '                              ; $1F0 region

; ---------------------------------------------------------------------------
; 68000 jump table -- cartridge $000200-$0003BF
;
; Manual 3.1: "ROM contents are at 88 0200h, 88 0206h, 88 020Ch... (6-byte
; JUMP commands arranged into a jump table)".  Entry 0 is the application
; entry point reached from the Sega initial program; the rest are the
; exception and interrupt trampolines the vector table above points at.
; ---------------------------------------------------------------------------
JumpTable:
MarsEntry:              jmp     MdMain                  ; $200 application entry
TrapBusError:           jmp     GameBusError            ; $206
TrapAddressError:       jmp     GameAddressError        ; $20C
TrapIllegal:            jmp     GameIllegal             ; $212
TrapZeroDivide:         jmp     GameZeroDivide          ; $218
TrapChk:                jmp     GameChk                 ; $21E
TrapTrapv:              jmp     GameTrapv               ; $224
TrapPrivilege:          jmp     GamePrivilege           ; $22A
TrapTrace:              jmp     GameTrace               ; $230
TrapLineA:              jmp     GameLineA               ; $236
TrapLineF:              jmp     GameLineF               ; $23C
TrapReserved:           jmp     GameReserved            ; $242
TrapUninitialized:      jmp     GameUninitialized       ; $248
IntLevel2Ext:           jmp     GameExtInt              ; $24E
IntLevel4HBlank:        jmp     GameHBlankInt           ; $254
IntLevel6VBlank:        jmp     GameVBlankInt           ; $25A

        dcb.b   (CART_BASE+$3C0)-*,$FF                  ; pad to the user header

; ---------------------------------------------------------------------------
; MARS user header -- cartridge $0003C0-$0003EF -- manual 5.1
;
; The 32X boot ROM reads this to copy the SH2 program from cartridge into
; SDRAM before starting either SH2.  Source, destination and size must all be
; longword aligned and the size must be a multiple of four, or the boot ROM
; takes an address error.
; ---------------------------------------------------------------------------
MarsUserHeader:
        dc.b    'MARS CHECK MODE '      ; $3C0 module name
        dc.l    $00000000               ; $3D0 version
        dc.l    SH2_ROM_OFFSET          ; $3D4 source: cartridge byte offset
        dc.l    $00000000               ; $3D8 destination: SDRAM byte offset
        dc.l    SH2_IMAGE_SIZE          ; $3DC size in bytes, multiple of 4
        dc.l    SH2_MASTER_START        ; $3E0 SH2 master start address
        dc.l    SH2_SLAVE_START         ; $3E4 SH2 slave start address
        dc.l    SH2_MASTER_VBR          ; $3E8 SH2 master vector base
        dc.l    SH2_SLAVE_VBR           ; $3EC SH2 slave vector base

; ---------------------------------------------------------------------------
; Sega initial program and security -- cartridge $0003F0-$0004D3 -- manual 5.2
;
; This block is Sega copyright and is NOT stored in this repository.  It is
; extracted at build time from a retail 32X cartridge image you supply.  See
; tools/extract_mars_init.py and the `mars-init` make target.
;
; Manual 5.2: the block must start at $3F0 and the 32X boot ROM verifies it.
; If it does not match, the adapter locks out the MEGA Drive side entirely.
;
; The block is therefore included BYTE FOR BYTE, never patched.  It ends with
; a jump to a fixed cartridge offset that is baked into the donor image; the
; extractor decodes that offset and emits it as MARS_APP_ENTRY.  Rather than
; edit the block to point at us, we place our entry point exactly where the
; block already jumps.  That keeps the security block bit-identical to a
; shipped cartridge, which is the only configuration known to pass.
; ---------------------------------------------------------------------------
        incbin  "build/mars_init.bin"

        dcb.b   (CART_BASE+MARS_APP_ENTRY)-*,$FF        ; pad to the entry point
MdMain:
        include "32x/md_main.asm"
