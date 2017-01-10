;
; CHR optimization for NES graphics editor
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;
.include "src/ram.h"

.segment "BSS"
.align 256
tilelist_A: .res 256
tilelist_B: .res 256
.segment "CODE"

; about 32760 cycles
.proc calculate_bg_tile_usage
  ldx #$00
  txa
clear_histo:
  sta histo,x
  inx
  bne clear_histo

srcLo = 0
srcHi = 1
leftLo = 2
leftHi = 3

  stx srcLo
  lda #>SRAM_NT
  ldy #<SRAM_NT
  sta srcHi
  lda #<-960
  sta leftLo
  lda #>-960
  sta leftHi

loop:
  lda (srcLo),y
  tax
  inc histo,x
  bne :+
  dec histo,x  ; clip histo value at 255
:
  iny
  bne :+
  inc srcHi
:
  inc leftLo
  bne loop
  inc leftHi
  bne loop
  rts
.endproc

;;
; Counts the tiles marked unused in a histogram.
; @return X=unused tile count; Y=0
.proc count_unused_tiles
  ldy #0
  ldx #0
loop:
  lda histo,y
  bne is_used
  inx
is_used:
  iny
  bne loop
  rts
.endproc

;;
; Finds the next unused tile in a histogram.
; @param Y starting tile number for search
; @return C=true iff found;
;         Y=next unused tile, valid only if C is true
.proc find_next_unused_tile
  ldx #0
loop:
  lda histo,y
  beq found
  iny
  inx
  bne loop
  clc
  rts
found:
  sec
  rts
.endproc

.proc blank_unused_tiles
  jsr calculate_bg_tile_usage
.endproc
.proc blank_if_zero_A
tileaddr = 0
  lda #<SRAM_BGCHR
  sta tileaddr+0
  lda #>SRAM_BGCHR
  sta tileaddr+1
  ldx #0
tileloop:
  lda histo,x
  bne tile_is_used
  ldy #15
  lda #$AA
byteloop:
  sta (tileaddr),y
  eor #$FF
  dey
  bpl byteloop
tile_is_used:

  lda tileaddr
  clc
  adc #16
  sta tileaddr
  bcc :+
  inc tileaddr+1
:
  inx
  bne tileloop
back_to_chrpicker:
  jsr load_chr_ram
  ldx #SCREEN_CHRPICKER
  rts
.endproc

;;
; Calculates an 8-bit hash value for each tile.  Useful as a first
; stage of finding duplicates.
; The hash of tiles $43 and $BB in SMB1's BG page is $C3.
.proc calculate_tile_hashes

srcLo = 0
srcHi = 1
tileno = 2
crclo = 4
crchi = 5

  lda #>SRAM_BGCHR
  sta srcHi
  lda #<SRAM_BGCHR
  sta srcLo
  lda #0
  sta tileno

tileloop:
  ldy #$FF   ; Hash of no bytes is $FF.
  sty crclo
  sty crchi
  iny
byteloop:
  lda (srcLo),y

  ; This part is based on a routine by Greg Cook that implements
  ; a CRC-16 cycle in constant time, without tables.
  ; 39 bytes, 66 cycles, AXP clobbered, Y preserved.
  ; http://www.6502.org/source/integers/crc-more.html

        EOR crchi       ; A contained the data
        STA crchi       ; XOR it into high byte
        LSR             ; right shift A 4 bits
        LSR             ; to make top of x^12 term
        LSR             ; ($1...)
        LSR
        TAX             ; save it
        ASL             ; then make top of x^5 term
        EOR crclo       ; and XOR that with low byte
        STA crclo       ; and save
        TXA             ; restore partial term
        EOR crchi       ; and update high byte
        STA crchi       ; and save
        ASL             ; left shift three
        ASL             ; the rest of the terms
        ASL             ; have feedback from x^12
        TAX             ; save bottom of x^12
        ASL             ; left shift two more
        ASL             ; watch the carry flag
        EOR crchi       ; bottom of x^5 ($..2.)
        STA crchi       ; save high byte
        TXA             ; fetch temp value
        ROL             ; bottom of x^12, middle of x^5!
        EOR crclo       ; finally update low byte
        LDX crchi       ; then swap high and low bytes
        STA crchi
        STX crclo
  
  iny
  cpy #16
  bcc byteloop
  ldy tileno
  lda crclo
  eor crchi
  sta tilelist_A,y
  ; sec by previous cpy
  lda srcLo
  adc #15
  sta srcLo
  bcc :+
  inc srcHi
:
  inc tileno
  bne tileloop
  rts
.endproc

;;
; Before calling: A is the hash value of each tile.
; Afterward: B is the most recently seen tile number with a given
; hash (or $FF for none seen), and A is the immediately previous tile
; number with the same hash as a given tile (or $FF for the first).
.proc link_tiles_by_hash

  ; B = [255]*256
  ldy #0
  lda #$FF
clear_B_loop:
  sta tilelist_B,y
  iny
  bne clear_B_loop

  ; for tileno in range(256):
find_prev_loop:
  ; Find the most recently seen tile with the same hash value as
  ; this tile
  ldx tilelist_A,y  ; hashval = A[tileno]
  lda tilelist_B,x  ; prev_tile = B[hashval]
  ; and link from this tile to that one
  sta tilelist_A,y  ; A[tileno] = prev_tile
  ; Update the most recently seen tile
  tya
  sta tilelist_B,x  ; B[hashval] = tileno
  iny
  bne find_prev_loop
  rts
.endproc

.proc remap_dupe_to_first_entry
led_here = 0
prev_tile_save = 1

  ; Need breakpoint on reading $3BB

  ; B = range(256)
  ldy #0
clear_B_loop:
  tya
  sta tilelist_B,y
  iny
  bne clear_B_loop

  ; for tileno in range(256):
tileno_loop:
  tya  ; led_here = tile_no
  tax
prev_tile_loop:
  ; register values: X = led_here
  lda tilelist_A,x  ; prev_tile = A[led_here]
  cmp #$FF          ; if prev_tile >= 255: break
  bcs prev_tile_break
  stx led_here
  tax
  ; register values: X = prev_tile
  cmp tilelist_B,x  ; if prev_tile == B[prev_tile]:
  bne is_duplicate
  jsr compare_tiles_x_and_y  ; if tileset[prev_tile] == tileset[tileno]):
  bne prev_tile_loop
  txa
  sta tilelist_B,y  ; B[tileno] = prev_tile
  jmp prev_tile_break
is_duplicate:
  stx prev_tile_save
  lda tilelist_A,x
  ldx led_here
  sta tilelist_A,x
  ldx prev_tile_save
  jmp prev_tile_loop
  
prev_tile_break:
  iny
  bne tileno_loop
  rts
.endproc

.proc compare_tiles_x_and_y
x_tileaddr = 0
y_tileaddr = 2
y_save = 4

; calculate x tile's address
  stx x_tileaddr
  lda #$00
  .repeat 4
    asl x_tileaddr
    rol a
  .endrepeat
  adc #>SRAM_BGCHR
  sta x_tileaddr+1

  sty y_tileaddr
  lda #$00
  .repeat 4
    asl y_tileaddr
    rol a
  .endrepeat
  adc #>SRAM_BGCHR
  sta y_tileaddr+1

; compare the tiles
  sty y_save
  ldy #15
cmploop:
  lda (x_tileaddr),y
  cmp (y_tileaddr),y
  bne different
  dey
  bpl cmploop

same:
  ldy y_save
  lda #0
  rts

different:
  ldy y_save
  lda #1
  rts
.endproc

.proc remap_all_dupes
  jsr calculate_tile_hashes
  jsr link_tiles_by_hash
  jsr remap_dupe_to_first_entry
  jsr remap_nt_by_B

  ; Now blank the tiles that weren't mapped to themwelves.
  ldx #0
histoloop:
  txa
  eor tilelist_B,x
  beq :+
  lda #1
:
  eor #1
  sta tilelist_A,x
  inx
  bne histoloop
  jmp blank_if_zero_A
.endproc

.proc remap_nt_by_B
srcLo = 0
srcHi = 1
leftLo = 2
leftHi = 3

  ldx #0
  stx srcLo
  lda #>SRAM_NT
  ldy #<SRAM_NT
  sta srcHi
  lda #<-960
  sta leftLo
  lda #>-960
  sta leftHi

ntloop:
  lda (srcLo),y
  tax
  lda tilelist_B,x
  sta (srcLo),y
  iny
  bne :+
  inc srcHi
:
  inc leftLo
  bne ntloop
  inc leftHi
  bne ntloop
  rts
.endproc

.proc defrag_tiles
from_tile = 0
from_ptr = 1
to_tile = 3
to_ptr = 4

  jsr calculate_bg_tile_usage
  lda #<SRAM_BGCHR
  sta from_ptr
  sta to_ptr
  lda #>SRAM_BGCHR
  sta from_ptr+1
  sta to_ptr+1
  
  ldx #0  ; x = from_tile
  stx to_tile
from_tile_loop:
  ; Map tile X to to_tile
  lda to_tile
  sta tilelist_B,x
  ; Don't advance to_tile if from_tile is unused
  lda histo,x
  beq tile_is_unused

  ; If from has advanced past to, copy one tile
  cpx to_tile
  beq no_copy_tile
  ldy #15
copy_byteloop:
  lda (from_ptr),y
  sta (to_ptr),y
  dey
  bpl copy_byteloop
no_copy_tile:

  ; Advance to_tile
  inc to_tile
  lda to_ptr
  clc
  adc #16
  sta to_ptr
  bcc :+
  inc to_ptr+1
:
tile_is_unused:
  lda from_ptr
  clc
  adc #16
  sta from_ptr
  bcc :+
  inc from_ptr+1
:
  inx
  bne from_tile_loop
  
  ; If from_tile == to_tile, all tiles are used, so skip the rest.
  cpx to_tile
  bne something_was_unused
something_was_unused:

  ; Fill to end of the pattern table
  ldy to_ptr
  lda #0
  sta to_ptr
  lda #$33
fill_to_end_loop:
  eor #$FF
  sta (to_ptr),y
  iny
  bne fill_to_end_loop
  inc to_ptr+1
  ldx to_ptr+1
  cpx #>SRAM_BGCHR_END
  bcc fill_to_end_loop

  ; Remap nametable
  jsr remap_nt_by_B
  
  ; Reload VRAM and go back to chrpicker
  jmp blank_if_zero_A::back_to_chrpicker
.endproc

;;
; Fills CHR with solid tiles, the map with solid $00, and
.proc erase_picture
dstlo = 0
dsthi = 1

; Clear most of the tile sheet to solid color 3
  lda #>SRAM_BGCHR
  sta dsthi
  lda #<SRAM_BGCHR
  sta dstlo
  lda #$FF
  ldy #$10
  ldx #$F0
erase_chr_loop:
  sta (dstlo),y
  iny
  bne erase_chr_loop
  inc dsthi
  inx
  bne erase_chr_loop

; Clear map
  txa
erase_map:
  sta SRAM_NT+$000,x
  sta SRAM_NT+$100,x
  sta SRAM_NT+$200,x
  sta SRAM_NT+$300,x
  inx
  bne erase_map

; Change tiles 0, 1, and 2 to solid color 0, 1, and 2
  ldx #$0F
erase_012_loop:
  sta SRAM_BGCHR+$000,x
  sta SRAM_BGCHR+$018,x
  dex
  bpl erase_012_loop

; Set palette
  ldx #$0F
set_palette_loop:
  lda new_picture_palette,x
  sta SRAM_PALETTE,x
  dex
  bpl set_palette_loop

  rts
.endproc

.segment "RODATA"
new_picture_palette:
  .byt $0F,$00,$10,$30
  .byt $0F,$06,$16,$26
  .byt $0F,$1A,$2A,$3A
  .byt $0F,$02,$12,$22

