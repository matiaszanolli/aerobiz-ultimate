# ============================================================================
# Aerobiz Ultimate -- dual-target build
#
#   make genesis   byte-identical original Genesis ROM (the regression oracle)
#   make 32x       the Sega 32X port
#   make all       both
#
# The Genesis target must keep matching the original ROM's MD5.  It is the
# project's primary correctness check on every change to shared game sources.
# See PORT_ARCHITECTURE.md section 3.
# ============================================================================

ASM         = tools/vasmm68k_mot
SH2_AS      = sh-elf-as
SH2_CC      = sh-elf-gcc
SH2_LD      = sh-elf-ld
SH2_OBJCOPY = sh-elf-objcopy
SH2_NM      = sh-elf-nm
PYTHON      = python3

BUILD_DIR   = build
DISASM_DIR  = disasm
TOOLS_DIR   = tools

# Original Genesis ROM, for `make verify`
ORIGINAL_ROM   = Aerobiz Supersonic (USA).gen
GENESIS_ROM    = $(BUILD_DIR)/aerobiz.bin

# Any retail 32X cartridge image, used only to lift the Sega initial program.
# Override on the command line: make 32x MARS_DONOR="My Game.32x"
MARS_DONOR     = reference/Virtua Racing Deluxe (USA).32x

ULTIMATE_ROM   = $(BUILD_DIR)/aerobiz-ultimate.32x
BOOT_HALF      = $(BUILD_DIR)/32x_boot.bin
BOOT_HALF_M1   = $(BUILD_DIR)/32x_boot_m1.bin
BOOT_HALF_PROBE= $(BUILD_DIR)/32x_boot_rvprobe.bin
GAME_HALF      = $(BUILD_DIR)/32x_game.bin
MARS_INIT_BIN  = $(BUILD_DIR)/mars_init.bin
MARS_INIT_INC  = $(BUILD_DIR)/mars_init.inc
SH2_IMAGE_BIN  = $(BUILD_DIR)/sh2_image.bin
SH2_IMAGE_INC  = $(BUILD_DIR)/sh2_image.inc
SH2_ELF        = $(BUILD_DIR)/sh2/sh2.elf

# -no-opt keeps vasm from shortening abs.l to abs.w, which would change the
# encoding and break the byte-identical guarantee.  See KNOWN_ISSUES.md.
ASMFLAGS    = -Fbin -m68000 -no-opt -spaces -quiet
SH2_ASFLAGS = --big -isa=sh2

# SH2 C.  -m2 -mb is the big-endian SH2 multilib; freestanding because there is
# no libc and no startup beyond master_start.  The division helpers the game
# offload needs (__udivsi3) live in libgcc, so the link has to name it.
SH2_CFLAGS  = -m2 -mb -O2 -ffreestanding -fno-builtin -fomit-frame-pointer \
              -Wall -Wextra -Werror -std=c99
SH2_LIBGCC := $(shell $(SH2_CC) -m2 -mb -print-libgcc-file-name)

# Everything the two 68000 images include. Without these, editing a module or a
# section does not rebuild either ROM -- and `make verify` then checks a stale
# binary and passes for the wrong reason.
SHARED_SRCS  = $(wildcard $(DISASM_DIR)/sections/*.asm) \
               $(wildcard $(DISASM_DIR)/modules/68k/*/*.asm) \
               $(wildcard $(DISASM_DIR)/modules/shared/*.asm)

GENESIS_SRC  = $(DISASM_DIR)/aerobiz.asm
BOOT_SRC     = $(DISASM_DIR)/ultimate_boot.asm
# ultimate_boot.asm pulls these in; without listing them a change to the header
# or to MdMain would not trigger a rebuild.
BOOT_INC     = $(DISASM_DIR)/32x/mars_header.asm $(DISASM_DIR)/32x/md_main.asm \
               $(DISASM_DIR)/32x/dma_stub.asm \
               $(DISASM_DIR)/32x/rv_probe.asm \
               $(DISASM_DIR)/32x/sh2_probe.asm
GAME_SRC     = $(DISASM_DIR)/ultimate_game.asm
SH2_SRCS     = $(DISASM_DIR)/sh2/master/main.s $(DISASM_DIR)/sh2/slave/main.s
SH2_CSRCS    = $(DISASM_DIR)/sh2/master/rpc.c $(DISASM_DIR)/sh2/master/fb.c
SH2_OBJS     = $(patsubst $(DISASM_DIR)/sh2/%.s,$(BUILD_DIR)/sh2/%.o,$(SH2_SRCS)) \
               $(patsubst $(DISASM_DIR)/sh2/%.c,$(BUILD_DIR)/sh2/%.o,$(SH2_CSRCS))
SH2_LDS      = $(DISASM_DIR)/sh2/sh2.lds

.PHONY: all genesis 32x 32x-m1 32x-sh2probe 32x-fbtest 32x-layeron 32x-h40 32x-h40map verify clean help mars-init sh2

all: genesis 32x

# ============================================================================
# Genesis target -- must stay byte-identical
# ============================================================================

genesis: $(GENESIS_ROM)

$(GENESIS_ROM): $(GENESIS_SRC) $(SHARED_SRCS) | $(BUILD_DIR)
	@echo "==> Assembling Genesis ROM..."
	$(ASM) $(ASMFLAGS) -o $@ $<
	@ls -lh $@

verify: $(GENESIS_ROM)
	@if [ -f "$(ORIGINAL_ROM)" ]; then \
		ORIG=$$(md5sum "$(ORIGINAL_ROM)" | cut -d' ' -f1); \
		NEW=$$(md5sum "$(GENESIS_ROM)" | cut -d' ' -f1); \
		if [ "$$ORIG" = "$$NEW" ]; then \
			echo "==> MATCH: Genesis ROM is byte-identical ($$ORIG)"; \
		else \
			echo "==> MISMATCH -- a shared source changed the Genesis build."; \
			echo "    Original: $$ORIG"; \
			echo "    Rebuilt:  $$NEW"; \
			exit 1; \
		fi \
	else \
		echo "==> Original ROM not found: $(ORIGINAL_ROM)"; \
		echo "    Place it in the project root to enable verification."; \
	fi

# ============================================================================
# 32X target
# ============================================================================

32x: $(ULTIMATE_ROM)

# Milestone 1 test cartridge: the boot half plus filler where the game will go.
# Boots the adapter, synchronises both SH2s and idles.  Useful on its own to
# prove the header, the security block and SH2 startup before the game image is
# rebased.  See PORT_ARCHITECTURE.md section 6.
32x-m1: $(BUILD_DIR)/aerobiz-ultimate-m1.32x

$(BUILD_DIR)/aerobiz-ultimate-m1.32x: $(BOOT_HALF_M1)
	@echo "==> Assembling milestone-1 test cartridge..."
	@cp $(BOOT_HALF_M1) $@
	@dd if=/dev/zero bs=1M count=1 2>/dev/null | tr '\000' '\377' >> $@
	@echo "==> Build complete: $@"
	@ls -lh $@

# Cartridge layout, per PORT_ARCHITECTURE.md section 2:
#   $000000-$0FFFFF  boot half   (header, security, glue, SH2 image) -> $880000
#   $100000-$1FFFFF  game half   (Aerobiz, rebased)                  -> $900000
$(ULTIMATE_ROM): $(BOOT_HALF) $(GAME_HALF)
	@echo "==> Assembling 32X cartridge..."
	@cat $(BOOT_HALF) $(GAME_HALF) > $@
	@SIZE=$$(stat -c%s $@); \
	 if [ "$$SIZE" -ne 2097152 ]; then \
		echo "==> ERROR: cartridge is $$SIZE bytes, expected 2097152"; exit 1; \
	 fi
	@echo "==> Build complete: $@"
	@ls -lh $@

$(BOOT_HALF): $(BOOT_SRC) $(BOOT_INC) $(MARS_INIT_BIN) $(MARS_INIT_INC) $(SH2_IMAGE_BIN) $(SH2_IMAGE_INC) | $(BUILD_DIR)
	@echo "==> Assembling 32X boot half (\$$880000)..."
	$(ASM) $(ASMFLAGS) -o $@ $<

# U-020 experiment cartridge: MdMain runs the RV probe from work RAM and parks.
# Carries the real game half so the bank window has recognisable content.
32x-h40map: $(BUILD_DIR)/aerobiz-ultimate-h40map.32x

$(BUILD_DIR)/aerobiz-ultimate-h40map.32x: $(BUILD_DIR)/32x_boot_h40.bin $(BUILD_DIR)/32x_game_h40map.bin
	@echo "==> Assembling H40 + 64x32 plane experiment cartridge..."
	@cat $(BUILD_DIR)/32x_boot_h40.bin $(BUILD_DIR)/32x_game_h40map.bin > $@
	@echo "==> Build complete: $@"

$(BUILD_DIR)/32x_game_h40map.bin: $(GAME_SRC) $(SHARED_SRCS) | $(BUILD_DIR)
	@echo "==> Assembling 32X game half, 64x32 map plane (\$$900000)..."
	$(ASM) $(ASMFLAGS) -DH40MAP=1 -o $@ $<

32x-h40: $(BUILD_DIR)/aerobiz-ultimate-h40.32x

$(BUILD_DIR)/aerobiz-ultimate-h40.32x: $(BUILD_DIR)/32x_boot_h40.bin $(GAME_HALF)
	@echo "==> Assembling H40 + layer experiment cartridge..."
	@cat $(BUILD_DIR)/32x_boot_h40.bin $(GAME_HALF) > $@
	@echo "==> Build complete: $@"

$(BUILD_DIR)/32x_boot_h40.bin: $(BOOT_SRC) $(BOOT_INC) $(MARS_INIT_BIN) $(MARS_INIT_INC) $(SH2_IMAGE_BIN) $(SH2_IMAGE_INC) | $(BUILD_DIR)
	@echo "==> Assembling 32X boot half, forced H40 (\$$880000)..."
	$(ASM) $(ASMFLAGS) -DH40PROBE=1 -o $@ $<

32x-layeron: $(BUILD_DIR)/aerobiz-ultimate-layeron.32x

$(BUILD_DIR)/aerobiz-ultimate-layeron.32x: $(BUILD_DIR)/32x_boot_layeron.bin $(GAME_HALF)
	@echo "==> Assembling 32X layer-during-H32 experiment cartridge..."
	@cat $(BUILD_DIR)/32x_boot_layeron.bin $(GAME_HALF) > $@
	@echo "==> Build complete: $@"

$(BUILD_DIR)/32x_boot_layeron.bin: $(BOOT_SRC) $(BOOT_INC) $(MARS_INIT_BIN) $(MARS_INIT_INC) $(SH2_IMAGE_BIN) $(SH2_IMAGE_INC) | $(BUILD_DIR)
	@echo "==> Assembling 32X boot half, layer on (\$$880000)..."
	$(ASM) $(ASMFLAGS) -DLAYERON=1 -o $@ $<

32x-fbtest: $(BUILD_DIR)/aerobiz-ultimate-fbtest.32x

$(BUILD_DIR)/aerobiz-ultimate-fbtest.32x: $(BUILD_DIR)/32x_boot_fbtest.bin $(GAME_HALF)
	@echo "==> Assembling 32X layer test cartridge..."
	@cat $(BUILD_DIR)/32x_boot_fbtest.bin $(GAME_HALF) > $@
	@echo "==> Build complete: $@"

$(BUILD_DIR)/32x_boot_fbtest.bin: $(BOOT_SRC) $(BOOT_INC) $(MARS_INIT_BIN) $(MARS_INIT_INC) $(SH2_IMAGE_BIN) $(SH2_IMAGE_INC) | $(BUILD_DIR)
	@echo "==> Assembling 32X boot half, layer test (\$$880000)..."
	$(ASM) $(ASMFLAGS) -DFBTEST=1 -o $@ $<

32x-sh2probe: $(BUILD_DIR)/aerobiz-ultimate-sh2probe.32x

$(BUILD_DIR)/aerobiz-ultimate-sh2probe.32x: $(BUILD_DIR)/32x_boot_sh2probe.bin $(GAME_HALF)
	@echo "==> Assembling SH2 offload probe cartridge..."
	@cat $(BUILD_DIR)/32x_boot_sh2probe.bin $(GAME_HALF) > $@
	@echo "==> Build complete: $@"

$(BUILD_DIR)/32x_boot_sh2probe.bin: $(BOOT_SRC) $(BOOT_INC) $(MARS_INIT_BIN) $(MARS_INIT_INC) $(SH2_IMAGE_BIN) $(SH2_IMAGE_INC) | $(BUILD_DIR)
	@echo "==> Assembling 32X boot half, SH2 probe (\$$880000)..."
	$(ASM) $(ASMFLAGS) -DSH2PROBE=1 -o $@ $<

32x-rvprobe: $(BUILD_DIR)/aerobiz-ultimate-rvprobe.32x

$(BUILD_DIR)/aerobiz-ultimate-rvprobe.32x: $(BOOT_HALF_PROBE) $(GAME_HALF)
	@echo "==> Assembling RV probe cartridge..."
	@cat $(BOOT_HALF_PROBE) $(GAME_HALF) > $@
	@echo "==> Build complete: $@"

$(BOOT_HALF_PROBE): $(BOOT_SRC) $(BOOT_INC) $(MARS_INIT_BIN) $(MARS_INIT_INC) $(SH2_IMAGE_BIN) $(SH2_IMAGE_INC) | $(BUILD_DIR)
	@echo "==> Assembling 32X boot half, RV probe (\$$880000)..."
	$(ASM) $(ASMFLAGS) -DRVPROBE=1 -o $@ $<

# Milestone-1 boot half: identical to the real one except that MdMain idles
# instead of jumping to the game image, which the M1 cartridge does not carry.
$(BOOT_HALF_M1): $(BOOT_SRC) $(BOOT_INC) $(MARS_INIT_BIN) $(MARS_INIT_INC) $(SH2_IMAGE_BIN) $(SH2_IMAGE_INC) | $(BUILD_DIR)
	@echo "==> Assembling 32X boot half, milestone 1 (\$$880000)..."
	$(ASM) $(ASMFLAGS) -DMILESTONE1=1 -o $@ $<

$(GAME_HALF): $(GAME_SRC) $(SHARED_SRCS) | $(BUILD_DIR)
	@echo "==> Assembling 32X game half (\$$900000)..."
	$(ASM) $(ASMFLAGS) -o $@ $<

# ----------------------------------------------------------------------------
# Sega initial program / security block.
#
# Sega copyright, so it is not in this repository: it is lifted from a retail
# 32X cartridge image at build time.  docs/32x-hardware-manual.md section 5.2
# requires it verbatim at $3F0, so it is never patched -- the application entry
# point is placed wherever the donor block already jumps.
# ----------------------------------------------------------------------------

mars-init: $(MARS_INIT_BIN)

$(MARS_INIT_BIN) $(MARS_INIT_INC): $(TOOLS_DIR)/extract_mars_init.py | $(BUILD_DIR)
	@if [ ! -f "$(MARS_DONOR)" ]; then \
		echo "==> Missing 32X donor cartridge: $(MARS_DONOR)"; \
		echo "    The Sega initial program is not distributable, so the build"; \
		echo "    lifts it from a retail 32X ROM you supply."; \
		echo "    Override with: make 32x MARS_DONOR=\"path/to/game.32x\""; \
		exit 1; \
	fi
	@$(PYTHON) $(TOOLS_DIR)/extract_mars_init.py "$(MARS_DONOR)" $(MARS_INIT_BIN) $(MARS_INIT_INC)

# ----------------------------------------------------------------------------
# SH2 image: assembled, linked at the SDRAM base, flattened, then described to
# the 68000 side so the MARS user header can point the boot ROM at it.
# ----------------------------------------------------------------------------

sh2: $(SH2_IMAGE_BIN)

$(BUILD_DIR)/sh2/%.o: $(DISASM_DIR)/sh2/%.s | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	$(SH2_AS) $(SH2_ASFLAGS) -o $@ $<

$(BUILD_DIR)/sh2/%.o: $(DISASM_DIR)/sh2/%.c | $(BUILD_DIR)
	@mkdir -p $(dir $@)
	$(SH2_CC) $(SH2_CFLAGS) -c -o $@ $<

$(SH2_ELF): $(SH2_OBJS) $(SH2_LDS)
	$(SH2_LD) -T $(SH2_LDS) -o $@ $(SH2_OBJS) $(SH2_LIBGCC)

$(SH2_IMAGE_BIN) $(SH2_IMAGE_INC): $(SH2_ELF)
	@$(SH2_OBJCOPY) -O binary $(SH2_ELF) $(SH2_IMAGE_BIN)
	@SLAVE=$$($(SH2_NM) $(SH2_ELF) | awk '$$3=="slave_start"{print $$1}'); \
	 SIZE=$$(stat -c%s $(SH2_IMAGE_BIN)); \
	 PADDED=$$(( (SIZE + 3) / 4 * 4 )); \
	 if [ "$$SIZE" -ne "$$PADDED" ]; then \
		dd if=/dev/zero bs=1 count=$$(( PADDED - SIZE )) >> $(SH2_IMAGE_BIN) 2>/dev/null; \
	 fi; \
	 { \
	   echo "; Generated by the Makefile from $(SH2_ELF) -- do not edit."; \
	   echo "; The 32X boot ROM copies SH2_IMAGE_SIZE bytes from cartridge"; \
	   echo "; SH2_ROM_OFFSET into SDRAM. Manual 5.1 requires a multiple of 4."; \
	   echo "SH2_IMAGE_SIZE  equ $$PADDED"; \
	   echo "SH2_SLAVE_START equ \$$$$SLAVE"; \
	 } > $(SH2_IMAGE_INC)
	@echo "==> SH2 image: $$(stat -c%s $(SH2_IMAGE_BIN)) bytes"

# ============================================================================

$(BUILD_DIR):
	@mkdir -p $(BUILD_DIR)

clean:
	rm -rf $(BUILD_DIR)

help:
	@echo "Aerobiz Ultimate -- Sega 32X port of Aerobiz Supersonic"
	@echo ""
	@echo "  make genesis   Build the byte-identical Genesis ROM"
	@echo "  make verify    Check the Genesis ROM against the original MD5"
	@echo "  make sh2       Build the SH2 image only"
	@echo "  make 32x       Build the 32X cartridge"
	@echo "  make all       Both targets"
	@echo "  make clean     Remove build artifacts"
	@echo ""
	@echo "The 32X target needs a retail 32X ROM to lift the Sega initial"
	@echo "program from:  make 32x MARS_DONOR=\"path/to/game.32x\""
