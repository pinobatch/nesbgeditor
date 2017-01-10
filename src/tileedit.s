;
; Tile editor for NES graphics editor
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;

.include "src/nes.h"
.include "src/ram.h"


.segment "ZEROPAGE"
redraw_y: .res 1
pixel_x: .res 1     ; in pixels (0-127, 0-255 in map mode)
pixel_y: .res 1     ; in pixels (0-127, 0-239 in map mode)
scroll_x: .res 1    ; in rows (0-10, 0-26 in map mode)
scroll_y: .res 1    ; in rows (0-11, 0-25 in map mode)
pen_color: .res 1     ; 0-3
prepared_row: .res 1  ; row that has been prepared

; Bit 7 off means edit tiles in the same order as the tile sheet.
; Bit 7 on means edit tiles in the same order as the map.
tileedit_map_mode: .res 1

use_unused: .res 1  ; if nonzero, then map mode duplicates tiles
num_unused: .res 1

; Color sets used map
; 00-03: UI
; 05-07: Color set under current tile
; 09-0F: Unused
; 11-13: Pencil cursor


.segment "CODE"

.proc tileedit
  jsr tileedit_load_frame
  jsr calculate_bg_tile_usage  ; for "TILE $xx USED" at bottom
  ldy #0
  sty use_unused
  sty eyedropper_state
  sty redraw_y
  jsr count_unused_tiles
  stx num_unused
  ldy #1
  sty pen_color
  jsr tileedit_init_scroll_pos

loop:
  jsr read_pads
  ldx #0
  jsr autorepeat
  lda das_keys
  and #KEY_UP|KEY_DOWN|KEY_LEFT|KEY_RIGHT
  sta das_keys
  lda #KEY_SELECT
  and new_keys
  beq not_done
  jsr load_chr_ram
  ldx #SCREEN_CHRPICKER
  bit tileedit_map_mode
  bpl :+
  ldx #SCREEN_NTEDIT
:
  rts
not_done:

  lda new_keys
  jsr move_pixel_xy_by_dpad
  bcc not_moved
  bit cur_keys
  bmi pressedA
  lsr eyedropper_state
not_moved:
  bit new_keys
  bvc notB
  
  ; First B press: set the pen color to the color under the cursor
  ; Subsequent B presses: cycle the pen color
  bit eyedropper_state
  bmi subsequent_B
  jsr getPixel
  sta pen_color
  sec
  ror eyedropper_state
  bmi notA
subsequent_B:
  inc pen_color
  lda pen_color
  and #$03
  sta pen_color
notB:
  bpl notA
pressedA:
  lda tileedit_map_mode
  and use_unused
  bpl notMakeUnique
  jsr make_tile_unique
notMakeUnique:
  jsr plotPixel
  bit tileedit_map_mode
  bpl drawnTileUsedOnce
  ldy selected_tile
  lda histo,y
  cmp #2
  bcc drawnTileUsedOnce
  lda #0
  sta redraw_y
drawnTileUsedOnce:
  lda pixel_y
  lsr a
  lsr a
  lsr a
  sec
  sbc scroll_y
  cmp #5
  bcc have_redraw_row
notA:

  ; Start: toggle drawing to unused tiles
  lda new_keys
  and #KEY_START
  beq notStart
  bit tileedit_map_mode
  bpl notStart
  lda num_unused
  beq notStart
  lda #$80
  eor use_unused
  sta use_unused
notStart:

  lda redraw_y
have_redraw_row:
  jsr tileedit_prepare_row_A
  
  jsr chrpicker_s0wait
  ldx #4
  stx oam_used
  jsr tileedit_draw_pencil
  ldx oam_used
  jsr ppu_clear_oam

  ; Draw pixel x, y
  lda pixel_x
  ldx #$60
  jsr bcd_stuff
  lda pixel_y
  ldx #$63
  jsr bcd_stuff

  ; compue the tile number
  ldy selected_tile
  tya
  and #$0F
  cmp #10
  bcc :+
  adc #'A'-'9'-2
:
  adc #'0'
  sta $167
  tya
  lsr a
  lsr a
  lsr a
  lsr a
  cmp #10
  bcc :+
  adc #'A'-'9'-2
:
  adc #'0'
  sta $166
  lda histo,y
  ldx #$68
  cmp #99
  php
  bcc :+
  lda #99
:
  jsr bcd_stuff
  plp
  bcc :+
  lda #'>'
  sta $168
:
  lda num_unused
  ldx #$6B
  jsr bcd_stuff

  lda nmis
:
  cmp nmis
  beq :-

  ldy prepared_row
  cpy #5
  bcs no_prepared_row
  cpy redraw_y
  bne prepared_row_no_match
  inc redraw_y
prepared_row_no_match:
  jsr tileedit_copy_row_y
no_prepared_row:

  ; set pencil lead color to pen color
  ldy #$3F
  sty PPUADDR
  ldy #$12
  sty PPUADDR
  ldy pen_color
  beq :+
  lda selected_color
  asl a
  asl a
  ora pen_color
  tay
:
  lda SRAM_PALETTE,y
  sta PPUDATA

  ; load background
  ldy #$23
  sty PPUADDR
  lda #$45
  sta PPUADDR
  lda $160
  sta PPUDATA
  lda $161
  sta PPUDATA
  lda $162
  sta PPUDATA
  bit PPUDATA
  lda $163
  sta PPUDATA
  lda $164
  sta PPUDATA
  lda $165
  sta PPUDATA
  sty PPUADDR
  lda #$6A
  sta PPUADDR
  lda $166
  sta PPUDATA
  lda $167
  sta PPUDATA
  sty PPUADDR
  lda #$71
  sta PPUADDR
  lda $168
  sta PPUDATA
  lda $169
  sta PPUDATA
  lda $16A
  sta PPUDATA
  
  sty PPUADDR
  lda #$89
  sta PPUADDR
  lda $16B
  sta PPUDATA
  lda $16C
  sta PPUDATA
  lda $16D
  sta PPUDATA
  lda #' '
  sta PPUDATA
  bit use_unused
  bpl :+
  lda #'U'
:
  sta PPUDATA

  sty PPUADDR
  lda #$54
  sta PPUADDR
  lda pen_color
  ora #'0'
  sta PPUDATA

  ldx #0
  stx OAMADDR
  lda #>OAM
  sta OAM_DMA
  lda #VBLANK_NMI|BG_1000|OBJ_0000|1
  ldy #8
  sec
  jsr ppu_screen_on
  jmp loop
  
bcd_stuff:
  jsr bcd8bit
  ora #'0'
  sta $102,x
  lda #' '
  sta $100,x
  sta $101,x
  lda 0
  beq bcd_no_tens
  and #$0F
  ora #'0'
  sta $101,x
  lda 0
  lsr a
  lsr a
  lsr a
  lsr a
  beq bcd_no_tens
  ora #'0'
  sta $100,x
bcd_no_tens:
  rts
.endproc

.proc tileedit_init_scroll_pos
  bit tileedit_map_mode
  bpl not_map_mode
  lda nt_x
  sec
  sbc #2
  bcs :+
  lda #0
:
  cmp #26
  bcc :+
  lda #26
:
  sta scroll_x
  lda nt_y
  sec
  sbc #2
  bcs :+
  lda #0
:
  cmp #26
  bcc :+
  lda #26
:
  sta scroll_y
  
  lda nt_x
  asl a
  asl a
  asl a
  sta pixel_x
  lda nt_y
  asl a
  asl a
  asl a
  sta pixel_y
  jmp updateSelectedTile
not_map_mode:

  lda selected_tile
  and #$0F
  asl a
  asl a
  asl a
  sta pixel_x
  lda selected_tile
  and #$F0
  lsr a
  sta pixel_y

  ; Set initial scroll position
  lda pixel_x
  sec
  sbc #16
  bcs :+
  lda #0
:
  lsr a
  lsr a
  lsr a
  cmp #10
  bcc :+
  lda #10
:
  sta scroll_x
  lda pixel_y
  sec
  sbc #16
  bcs :+
  lda #0
:
  lsr a
  lsr a
  lsr a
  cmp #10
  bcc :+
  lda #10
:
  sta scroll_y
  rts
.endproc


;;
; Moves the selected pixel based on the pressed direction, and
; starts a redraw if the scroll changed.
; Left: -1; Right: +1; Up: -16; Down: +16
; @param A bitmask containing one or more of
; KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT
.proc move_pixel_xy_by_dpad
  lsr a
  bcc notRight
  inc pixel_x
  ; If wrapping around to 0, fail.  But if within 0-127 or
  ; map mode is on, pass.
  beq move_back_x
  bpl moved
  bit tileedit_map_mode
  bmi moved
move_back_x:
  dec pixel_x
  clc
  rts
notRight:

  lsr a
  bcc notLeft
  lda pixel_x
  beq notMoved
  dec pixel_x
  bcs moved
notLeft:

  lsr a
  bcc notDown
  inc pixel_y
  lda #127
  bit tileedit_map_mode
  bpl :+
  lda #239
:
  cmp pixel_y
  bcs moved
  dec pixel_y
  clc
  rts

notDown:

  lsr a
  bcc notMoved
  lda pixel_y
  beq notMoved
  dec pixel_y
  bcs moved
notMoved:
  clc
  rts
moved:

  ; Now try scrolling the screen in X
  lda pixel_x
  lsr a
  lsr a
  lsr a
  sec
  sbc scroll_x
  bcc go_left
  bne not_go_left
go_left:
  lda scroll_x
  beq done_x
  dec scroll_x
  lda #0
  sta redraw_y
not_go_left:
  cmp #5
  bcc done_x
  lda #16-6-1
  bit tileedit_map_mode
  bpl :+
  lda #32-6-1
:
  cmp scroll_x
  bcc done_x
  inc scroll_x
  lda #0
  sta redraw_y
done_x:

  ; Now try scrolling the screen in Y
  lda pixel_y
  lsr a
  lsr a
  lsr a
  sec
  sbc scroll_y
  bcc go_up
  bne not_go_up
go_up:
  lda scroll_y
  beq done_y
  dec scroll_y
  lda #0
  sta redraw_y
not_go_up:
  cmp #4
  bcc done_y
  lda #16-5-1
  bit tileedit_map_mode
  bpl :+
  lda #30-5-1
:
  cmp scroll_y
  bcc done_y
  inc scroll_y
  lda #0
  sta redraw_y
done_y:
  jsr updateSelectedTile
  sec
  rts
.endproc

.proc tileedit_prepare_row_A
tileno = $0A
xpos = $0B
map_base = $0C
  cmp #5
  bcc :+
  rts
:
  sta prepared_row
  adc scroll_y
  ; A = row number
  bit tileedit_map_mode
  bpl not_map_base
  ldy #0
  sty map_base+0
  lsr a
  ror map_base+0
  lsr a
  ror map_base+0
  lsr a
  ror map_base+0
  ora #>SRAM_NT
  sta map_base+1
  lda scroll_x
  jmp have_tileno
not_map_base:
  asl a
  asl a
  asl a
  asl a
  clc
  adc scroll_x
have_tileno:

  sta tileno
  lda #0
loop:
  sta xpos
  asl a
  asl a
  asl a
  asl a
  tax
  lda xpos
  clc
  adc tileno
  bit tileedit_map_mode
  bpl not_map_lookup
  ; TODO: look up tile in map
  tay
  lda (map_base),y
  
not_map_lookup:
  jsr tileedit_prepare_tile
  inc xpos
  lda xpos
  cmp #6
  bcc loop
  rts
.endproc

.proc tileedit_load_frame

  ; Start by clearing both backgrounds to $00
  ldx #$20
  ldy #$00
  tya
  jsr ppu_clear_nt
  ldx #$24
  ldy #$00
  tya
  jsr ppu_clear_nt
  
  ; set the background color
  jsr load_colorset_0
  ldy #$3F
  sty PPUADDR
  ldy #$17
  sty PPUADDR
  sta PPUDATA
  
  ; Draw the color picker to the first bg, which is where the
  ; status bar will live
  ldy #$23
  sty PPUADDR
  ldx #$59
  stx PPUADDR
  ldx #$01
  stx PPUDATA
  inx
  stx PPUDATA
  inx
  stx PPUDATA
  sty PPUADDR
  ldx #$F6
  stx PPUADDR
  ldx #$50
  stx PPUDATA
  
  ; Draw the status bar text
  sty 3
  lda #$44
  sta 2
  lda #>tileedit_status_text
  ldy #<tileedit_status_text
  jsr puts_multiline

  ; The active background area goes to the second bg

  ; Draw the frame
  ldy #$24
  sty PPUADDR
  lda #$63
  sta PPUADDR
  lda #$44
  sta PPUDATA
  ldx #24
  lda #$CC
toploop:
  sta PPUDATA
  dex
  bne toploop
  lda #VBLANK_NMI|VRAM_DOWN
  sta PPUCTRL
  lda #$88
  sta PPUDATA
  ldx #20
  lda #$AA
rightloop:
  sta PPUDATA
  dex
  bne rightloop
  sty PPUADDR
  lda #$83
  sta PPUADDR
  ldx #20
  lda #$55
leftloop:
  sta PPUDATA
  dex
  bne leftloop
  lda #VBLANK_NMI
  sta PPUCTRL
  lda #$11
  sta PPUDATA
  ldx #24
  lda #$33
bottomloop:
  sta PPUDATA
  dex
  bne bottomloop
  lda #$22
  sta PPUDATA
  
  ; Draw the attributes (1 inside edit window; 0 outside)
  lda #$27
  sta PPUADDR
  lda #$C9
  sta PPUADDR
  ldy #5
  lda #$55
load_attr:
  ldx #6
l1:
  sta PPUDATA
  dex
  bne l1
  bit PPUDATA
  bit PPUDATA
  dey
  bne load_attr

  ; Set up sprite 0 that overlaps the bottom right corner
  ; of the frame, allowing raster switch to font tiles
  lda #24+32*5+2
  sta OAM+0
  lda #'_'
  sta OAM+1
  lda #%10100000  ; vertical flip, behind frame
  sta OAM+2
  lda #192
  sta OAM+3

  lda #2  ; tileedit.png to $0600-$07FF
  jsr unpb53_block
  
  ; set color of the pencil
  lda #$3F
  sta PPUADDR
  lda #$11
  sta PPUADDR
  lda SRAM_PALETTE
  and #$0F
  cmp #$0D  ; C=1: lower nibble is $0D-$0F (black)
  lda #$0F  ; black outline
  bcc background_is_black
  lda #$00  ; dark gray outline
background_is_black:
  sta PPUDATA
  sta PPUDATA
  lda #$38  ; pale yellow inside
  sta PPUDATA

  ; fall through to tileeditFillCHR
.endproc

; $1xx0-$1xxF
; 76543210
; ||||||||
; |||||||+- top right pixel plane 0
; ||||||+-- top left pixel plane 0
; |||||+--- bottom right pixel plane 0
; ||||+---- bottom left pixel plane 0
; |||+----- top right pixel plane 1
; ||+------ top left pixel plane 1
; |+------- bottom right pixel plane 1
; +-------- bottom left pixel plane 1

.proc tileeditFillCHR
top0 = 0
top1 = 1
bottom0 = 2
bottom1 = 3
byte_bits = 4
  lda #$10
  sta PPUADDR
  ldx #$00
  stx PPUADDR
tileloop:

  ; Compute bytes making up this byte
  stx byte_bits
  ldy #4
sectionloop:
  lda #0
  lsr byte_bits
  bcc :+
  ora #$0F
:
  lsr byte_bits
  bcc :+
  ora #$F0
:
  .repeat 4
    sta PPUDATA
  .endrepeat
  dey
  bne sectionloop
  inx
  bne tileloop
  rts
.endproc

.proc tileedit_draw_pencil
  lda scroll_x
  asl a
  asl a
  asl a
  eor #$FF
  sec
  adc pixel_x
  cmp #48
  bcs offscreen
  asl a
  asl a
  adc #34
  tax

  lda scroll_y
  asl a
  asl a
  asl a
  eor #$FF
  sec
  adc pixel_y
  cmp #40
  bcs offscreen
  asl a
  asl a
  adc #9
  
  ldy oam_used
  cpy #$F4
  bcs offscreen
  
  ; A = y coordinate
  ; X = x coordinate
  ; Y = OAM offset
  sta OAM+0,y
  adc #8
  sta OAM+4,y
  lda #$60
  sta OAM+1,y
  lda #$70
  sta OAM+5,y
  lda #0
  sta OAM+2,y
  sta OAM+6,y
  txa
  sta OAM+3,y
  sta OAM+7,y
  
  ; Pointer to current color
  lda #207
  sta OAM+8,y
  lda #'^'
  sta OAM+9,y
  lda #1  ; palette
  sta OAM+10,y
  lda pen_color
  asl a
  asl a
  asl a
  adc #192
  sta OAM+11,y
  
  tya
  clc
  adc #12
  sta oam_used
  cmp #$DC
  bcc showBorders
offscreen:
  rts

showBorders:
  tax

  ; left and right side borders
  lda pixel_y
  lsr a
  lsr a
  lsr a
  sec
  sbc scroll_y
  tay
  lda bordersx,y
  sec
  sbc #9
  sta OAM+0,x
  sta OAM+4,x
  sbc #<-24
  sta OAM+8,x
  sta OAM+12,x
  lda #'_'
  sta OAM+1,x
  sta OAM+5,x
  sta OAM+9,x
  sta OAM+13,x
  lda #%10100001
  sta OAM+2,x
  sta OAM+6,x
  lda #%00100001
  sta OAM+10,x
  sta OAM+14,x
  lda #24
  sta OAM+3,x
  sta OAM+11,x
  lda #224
  sta OAM+7,x
  sta OAM+15,x

  ; left and right side borders
  lda pixel_x
  lsr a
  lsr a
  lsr a
  sec
  sbc scroll_x
  tay
  lda bordersx,y
  sta OAM+19,x
  sta OAM+23,x
  clc
  adc #24
  sta OAM+27,x
  sta OAM+31,x
  lda #$61
  sta OAM+17,x
  sta OAM+21,x
  sta OAM+25,x
  sta OAM+29,x
  lda #%00100001
  sta OAM+18,x
  sta OAM+22,x
  lda #%01100001
  sta OAM+26,x
  sta OAM+30,x
  lda #15
  sta OAM+16,x
  sta OAM+24,x
  lda #183
  sta OAM+20,x
  sta OAM+28,x

  tax
  clc
  adc #32
  sta oam_used
  rts
.pushseg
.segment "RODATA"
bordersx: .byt 32, 64, 96, 128, 160, 192
.popseg
.endproc

; Buffer for preparing data to be copied to the screen
tileedit_buf = $0100
;;
; Loads tile A at position X (0, 16, 32, ..., 80) in the buffer.
.proc tileedit_prepare_tile
srcp0 = $00
srcp1 = $02
datap0t = $04
datap0b = $05
datap1t = $06
datap1b = $07
xbase = $08
left_in_row = $09

  stx xbase
  asl a
  rol a
  rol a
  rol a
  pha
  and #$F0
  sta srcp0
  ora #$08
  sta srcp1
  pla
  rol a
  and #$0F
  ora #>SRAM_BGCHR
  sta srcp0+1
  sta srcp1+1
  ldy #0
rowloop:
  lda (srcp0),y
  sta datap0t
  lda (srcp1),y
  sta datap1t
  iny
  lda (srcp0),y
  sta datap0b
  lda (srcp1),y
  sta datap1b
  iny
  ldx #4
  stx left_in_row
  ldx xbase
cellloop:
  asl datap1b
  rol a
  asl datap1b
  rol a
  asl datap1t
  rol a
  asl datap1t
  rol a
  asl datap0b
  rol a
  asl datap0b
  rol a
  asl datap0t
  rol a
  asl datap0t
  rol a
  ; at this point we have the byte
  sta tileedit_buf,x
  inx
  inx
  inx
  inx
  dec left_in_row
  bne cellloop
  inc xbase
  cpy #8
  bcc rowloop
  rts  
.endproc

.pushseg
.segment "RODATA"
rowDstHi: .byt $24,$25,$25,$26,$26
rowDstLo: .byt $84,$04,$84,$04,$84
.popseg

.proc tileedit_copy_row_y
dstLo = 0
  lda rowDstLo,y
  sta dstLo
  ldx #0
rowloop:
  lda rowDstHi,y
  sta PPUADDR
  lda dstLo
  sta PPUADDR
  clc
  adc #32
  sta dstLo
  
  .repeat 24,I
    lda tileedit_buf+I*4,x
    sta PPUDATA
  .endrepeat
  inx
  cpx #4
  bcs done
  jmp rowloop
done:
  rts
.endproc

.proc plotPixel
dstLo = 0
dstHi = 1
  jsr seekToPixel
  lda pen_color
  and #$01
  beq :+
  lda #$ff
:
  ldy #0
  eor (dstLo),y
  and bytemasks,x
  eor (dstLo),y
  sta (dstLo),y
  lda pen_color
  and #$02
  beq :+
  lda #$ff
:
  ldy #8
  eor (dstLo),y
  and bytemasks,x
  eor (dstLo),y
  sta (dstLo),y
  rts
.endproc

.proc getPixel
dstLo = 0
dstHi = 1
pxcolor = 2
  jsr seekToPixel
  ldy #8
  lda (dstLo),y
  and bytemasks,x
  cmp #1
  rol pxcolor
  ldy #0
  lda (dstLo),y
  and bytemasks,x
  cmp #1
  lda pxcolor
  and #$01
  rol a
  rts
.endproc

;;
; Sets selected_tile to the tile under the cursor.
.proc updateSelectedTile
  bit tileedit_map_mode
  bpl not_map_mode

mapLo = 0
mapHi = 1
  lda pixel_y
  sta $FF  ; debug breakpoint
  and #$F8
  sta mapLo
  lda #0
  asl mapLo
  rol a
  asl mapLo
  rol a
  adc #>SRAM_NT
  sta mapHi
  lda pixel_x
  lsr a
  lsr a
  lsr a
  tay
  lda (mapLo),y
  sta selected_tile
  rts

not_map_mode:
  lda pixel_x
  lsr a
  lsr a
  lsr a
  sta selected_tile
  lda pixel_y
  asl a
  eor selected_tile
  and #$F0
  eor selected_tile
  sta selected_tile
  rts
.endproc

;;
; Given selected_tile, compute the address of one sliver in $00,
; and return the pixel position (0-7) in X.
.proc seekToPixel
dstLo = 0
dstHi = 1
  lda selected_tile
have_selected_tile:
  asl a
  rol a
  rol a
  rol a
  sta dstLo
  rol a
  and #$0F
  ora #>SRAM_BGCHR
  sta dstHi
  lda dstLo
  ; At this point, dstHi is computed,
  ; and the upper 4 bits of dstLo are in A.
  and #$F0
  eor pixel_y
  and #$F8
  eor pixel_y
  sta dstLo
  lda pixel_x
  and #$07
  tax
  rts
.endproc

.proc make_tile_unique
mapLo = 0
  jsr updateSelectedTile
  tya
  clc
  adc mapLo
  sta mapLo

  ; at this point:
  ; mapLo is the address of the map cell to be made unique
  ; selected_tile is the nonunique copy
  ldx selected_tile
  lda histo,x
  cmp #2
  bcc nope
  dec histo,x
  ldy #0
  jsr find_next_unused_tile
  bcc out_of_free_tiles
  lda #1
  sta histo,y
  ldx #0
  tya
  sta (mapLo,x)

  ; TODO: copy tile selected_tile to tile y
srcLo = 0
srcHi = 1
dstLo = 2
dstHi = 3

  lda selected_tile
  lsr a
  ror a
  ror a
  ror a
  sta srcHi
  ror a
  and #$F0
  sta srcLo
  lda srcHi
  and #$0F
  ora #>SRAM_BGCHR
  sta srcHi
  sty selected_tile
  tya
  lsr a
  ror a
  ror a
  ror a
  sta dstHi
  ror a
  and #$F0
  sta dstLo
  lda dstHi
  and #$0F
  ora #>SRAM_BGCHR
  sta dstHi
  ldy #15
copyloop:
  lda (srcLo),y
  sta (dstLo),y
  dey
  bpl copyloop

  ; update tally of unused tiles
  dec num_unused
  bne nope
out_of_free_tiles:
  lda #0
  sta use_unused
nope:
  rts  
.endproc

.segment "RODATA"
bytemasks: .byt $80,$40,$20,$10,$08,$04,$02,$01
tileedit_status_text:
  .byt "(  0,  0) COLOR:",10
  .byt "TILE $$$ USED",10
  .byt "FREE:",0
