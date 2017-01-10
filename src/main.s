;
; Initialization and top-level loop for NES graphics editor
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;

.include "src/nes.h"
.include "src/mmc1.h"
.include "src/ram.h"

.global OAM
.export nmi, reset, irq
.exportzp cur_keys, new_keys, das_keys, das_timer

.segment "ZEROPAGE"
nmis:          .res 1
oam_used:      .res 1  ; starts at 0
cur_keys:      .res 2
new_keys:      .res 2
das_keys:      .res 2
das_timer:     .res 2
tvSystem:      .res 1

.segment "CODE"
;;
; We're not using scroll splits with widely varying object counts,
; so we can use the simple "has NMI occurred?" vblank-detect loop.
.proc nmi
  inc nmis
  rti
.endproc

; The IRQ handler doesn't do anything because the mapper doesn't
; generate IRQs and we aren't using DPCM Split.
.proc irq
  rti
.endproc

; 
.proc reset
  ; The very first thing to do when powering on is to put all sources
  ; of interrupts into a known state.
  sei             ; Disable interrupts
  ldx #$00
  stx PPUCTRL     ; Disable NMI and set VRAM increment to 32
  stx PPUMASK     ; Disable rendering
  stx $4010       ; Disable DMC IRQ
  dex             ; Subtracting 1 from $00 gives $FF, which is a
  txs             ; quick way to set the stack pointer to $01FF
  bit PPUSTATUS   ; Acknowledge stray vblank NMI across reset
  bit SNDCHN      ; Acknowledge DMC IRQ
  lda #$40
  sta P2          ; Disable APU Frame IRQ
  lda #$0F
  sta SNDCHN      ; Disable DMC playback, initialize other channels

vwait1:
  bit PPUSTATUS   ; It takes one full frame for the PPU to become
  bpl vwait1      ; stable.  Wait for the first frame's vblank.

  ; We have about 29700 cycles to burn until the second frame's
  ; vblank.  Use this time to get most of the rest of the chipset
  ; into a known state.

  ; The NES doesn't implement the 6502's binary-coded decimal (BCD)
  ; mode, but some famiclones do.
  cld

  ; Clear OAM and the zero page here.
  ; We don't copy the cleared OAM to the PPU until later.
  ldx #0
  jsr ppu_clear_oam  ; clear out OAM from X to end and set X to 0

  ; Clear the zero page. (Keep your holy wars to yourself.)
  txa
clear_zp:
  sta $00,x
  inx
  bne clear_zp
  
  ; There are two memory-protection bits in SNROM.  One is bit 4 of
  ; the PRG bank register ($E000) in later revisions of the MMC1.
  ; The other is on the SNROM board itself, in bit 4 of the CHR bank
  ; register ($A000).
  .repeat 5
    sta $E000
  .endrepeat
  .repeat 5
    sta $A000
  .endrepeat
  
  lda #%00010
  ;        ^^ Vertical mirroring (horizontal arrangement of nametables)
  ;      ^^   32 KiB PRG switching
  ;     ^     8 KiB CHR switching
  jsr setMMC1BankMode

vwait2:
  bit PPUSTATUS  ; After the second vblank, we know the PPU has
  bpl vwait2     ; fully stabilized.
  
  lda #VBLANK_NMI
  sta PPUCTRL
  jsr getTVSystem
  sta tvSystem
  jmp play_game
.endproc


.proc play_game
  jsr title_screen
forever:
  jsr dispatch
  jmp forever
dispatch:
  lda screens+1,x
  pha
  lda screens,x
  pha
  rts

.pushseg
.segment "RODATA"
screens:
  .addr chrpicker-1, ntedit-1, tileedit-1, nttools_menu-1
  
  ; CHR data tools
  .addr paledit-1, drawing_help_screen-1, blank_unused_tiles-1
  .addr remap_all_dupes-1, defrag_tiles-1, comingsoon1_screen-1
  
  ; Nametable tools
  .addr tileedit-1  ; ntedit sets it to map mode
  .addr attribute_viewer-1
  .addr nt_copipe-1
.popseg
.endproc


BOXTILE_TOPLEFT = $10
BOXTILE_TOP = $11
BOXTILE_TOPRIGHT = $12
BOXTILE_LEFT = $13
BOXTILE_RIGHT = $14
BOXTILE_BOTTOMLEFT = $15
BOXTILE_BOTTOM = $16
BOXTILE_BOTTOMRIGHT = $17

.if 0
.proc draw_box
left    = 0
top     = 1
width   = 2
height  = 3
addr_lo = 4
addr_hi = 5

  sec
  lda top
  .repeat 3
    ror a
    ror addr_lo
  .endrepeat
  sta PPUADDR
  sta addr_hi
  lda #%11100000
  and addr_lo
  ora left
  sta PPUADDR
  sta addr_lo
  
  ; Draw top of frame
  lda #0  ; turn off VRAM_DOWN
  sta PPUCTRL
  lda #BOXTILE_TOPLEFT
  sta PPUDATA
  lda #BOXTILE_TOP
  ldy width
toploop:
  sta PPUDATA
  dey
  bne toploop
  
  ; Draw right side of frame
  lda #VRAM_DOWN
  sta PPUCTRL
  lda #BOXTILE_TOPRIGHT
  sta PPUDATA
  lda #BOXTILE_RIGHT
  ldy height
rightloop:
  sta PPUDATA
  dey
  bne rightloop
  
  ; Draw left side of frame
  lda addr_hi
  sta PPUADDR
  lda addr_lo
  sta PPUADDR
  lda PPUDATA
  lda #BOXTILE_LEFT
  ldy height
leftloop:
  sta PPUDATA
  dey
  bne leftloop
  lda #0
  sta PPUCTRL
  lda #BOXTILE_BOTTOMLEFT
  sta PPUDATA
  lda #BOXTILE_BOTTOM
  ldy width
bottomloop:
  sta PPUDATA
  dey
  bne bottomloop
  lda #BOXTILE_BOTTOMRIGHT
  sta PPUDATA
  rts
.endproc

.endif
