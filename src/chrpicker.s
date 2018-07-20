;
; Tile picker for NES graphics editor
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;

.include "nes.inc"
.include "global.inc"

CHRBORDER_TILE = $6F
CHRBORDER_PATTERN = $FF  ; use $AA for testing

.segment "ZEROPAGE"
selected_tile: .res 1
selected_color: .res 1
.segment "CODE"

.proc chrpicker
  jsr draw_chrpicker
  lda #$22
  sta 3
  lda #$82
  sta 2
  lda #>menudata
  ldy #<menudata
  jsr puts_multiline

loop:

  ; Draw the arrow cursor
  lda #4
  sta oam_used
  lda selected_tile
  lsr a
  lsr a
  lsr a
  lsr a
  clc
  adc #3
  tay
  lda selected_tile
  and #$0F
  adc #8
  tax
  jsr draw_arrow
  jsr chrpicker_draw_6f
  ldx oam_used
  jsr ppu_clear_oam

  lda nmis
:
  cmp nmis
  beq :-

  ; Set colors
  lda selected_color
  asl a
  asl a
  tax
  ldy #$05
  jsr color_x_to_y
  ldy #$15
  jsr color_x_to_y
  bit PPUDATA
  lda SRAM_PALETTE+0
  sta PPUDATA

  ; Draw tile number and color  
  lda #$22
  sta PPUADDR
  lda #$8E
  sta PPUADDR
  lda selected_tile
  jsr puthex
  lda #$22
  sta PPUADDR
  lda #$97
  sta PPUADDR
  lda selected_color
  ora #'0'
  sta PPUDATA

  ldx #0
  ldy #0
  stx OAMADDR
  lda #>OAM
  sta OAM_DMA
  lda #VBLANK_NMI|BG_1000|OBJ_0000
  sec
  jsr ppu_screen_on
  jsr read_pads
  ldx #0
  jsr autorepeat

  ; handle Control Pad
  lda new_keys
  jsr move_selected_tile_by_dpad
  
  lda new_keys
  and #KEY_B
  beq notB
  inc selected_color
  lda selected_color
  and #$03
  sta selected_color
notB:
  jsr chrpicker_s0wait
  ; Start: hide the title screen and go onto the next phase
  lda new_keys
  and #KEY_A|KEY_SELECT|KEY_START
  bne done
  jmp loop
done:

  ; Which screen to show next?
  lda new_keys
  bpl notA
  ldx #SCREEN_NTEDIT
  jmp have_final_x
notA:
  and #KEY_SELECT
  beq notSelect
  jmp chrpicker_secondary_menu
notSelect:
  ldx #0
  stx tileedit_map_mode
  ldx #SCREEN_TILEEDIT
have_final_x:
  lda #$10 | >(CHRBORDER_TILE << 4)
  ; fall through
.endproc
.proc chrpicker_move_6F
  ldy #$00
  sty PPUMASK
  sta PPUADDR
  lda #<(CHRBORDER_TILE << 4)
  sta PPUADDR
loop:
  lda SRAM_BGCHR+(CHRBORDER_TILE << 4),y
  sta PPUDATA
  iny
  cpy #16
  bcc loop
  rts
.endproc


.proc color_x_to_y
  lda #$3F
  sta PPUADDR
  sty PPUADDR
  lda $7F01,x
  sta PPUDATA
  lda $7F02,x
  sta PPUDATA
  lda $7F03,x
  sta PPUDATA
  rts
.endproc


;
; Switches back to the main tile after sprite 0 hit.
;
.proc chrpicker_s0wait
s0wait0:
  bit PPUSTATUS
  bvs s0wait0
s0wait1:
  bit PPUSTATUS
  bmi skip_raster
  bvc s0wait1
  lda #VBLANK_NMI|BG_0000|OBJ_0000
  sta PPUCTRL
skip_raster:
  rts
.endproc

.proc chrpicker_secondary_menu
  ldx #$00
  stx select_state
  stx PPUMASK
  lda #$22
  sta PPUADDR
  lda #$80
  sta PPUADDR
  sta PPUCTRL
  txa
clrloop:
  sta PPUDATA
  dex
  bne clrloop

  lda #$22
  sta 3
  lda #$84
  sta 2
  lda #>menumore
  ldy #<menumore
  jsr puts_multiline
  
  ; sprite 0 was set up by draw_chrpicker so clear all others
  ; except for sprite 1 that has the cursor
  ldx #7
  stx OAM+5
  ldx #0
  stx OAM+6
  ldx #16
  stx OAM+7

  ldx #8
  stx oam_used
  jsr chrpicker_draw_6f
  ldx oam_used
  jsr ppu_clear_oam

runloop:
  lda select_state
  asl a
  asl a
  asl a
  adc #159
  sta OAM+4

  lda nmis
:
  cmp nmis
  beq :-
  ldx #0
  ldy #0
  stx OAMADDR
  lda #>OAM
  sta OAM_DMA
  lda #VBLANK_NMI|BG_1000|OBJ_0000
  sec
  jsr ppu_screen_on
  jsr read_pads
  jsr chrpicker_s0wait

  lda new_keys
  and #KEY_UP
  beq notUp
  lda select_state
  beq notUp
  dec select_state
notUp:
  lda new_keys
  and #KEY_DOWN
  beq notDown
  lda select_state
  cmp #NUM_CHRMENU_ITEMS-1
  bcs notDown
  inc select_state
notDown:

  lda new_keys
  and #KEY_B|KEY_A|KEY_SELECT|KEY_START
  beq runloop

  ; calculate which screen to show next
  ; A, Start: selected
  ; B, Select: NT editor
  and #KEY_A|KEY_START
  bne pressedOK
  ldx #SCREEN_CHRPICKER
  jmp chrpicker::have_final_x

pressedOK:
  lda #0
  sta PPUMASK
  lda select_state
  asl a
  adc #SCREEN_CHRMENUBASE
  tax
  jmp chrpicker::have_final_x
.endproc

.if 0
; until 2012-07-22, the editor searched the CHR ROM for a solid tile
; to use for the border.  Now it just forces one into $6F, making
; this subroutine unnecessary.
.proc choose_chrborder_tile
  ; Priority 1: Find an existing solid-color tile
  jsr find_first_solid_tile
  bcc have_border_in_A
  
  ; Priority 2: If there is no existing solid-color tile,
  ; find an unused tile and turn it solid
  ; TO DO: implement this
;  jsr calculate_bg_tile_usage
;  jsr find_least_used_in_histo
;  sty selected_tile

  ; Priority 3: If all tiles are in use, find a tile whose bottom
  ; row is filled
  jsr find_first_solid7_tile
  bcc have_border_in_A
  
  ; Priority 4: If no tiles have a filled bottom row, find the
  ; least used tile and turn it solid
  ; TO DO: implement this
  lda #$FF  ; works for SMB1; may freeze for yours

have_border_in_A:
  sta chrborder_tile
  rts
.endproc
.endif

.proc draw_chrpicker
dst_lo = $02
dst_hi = $03

  ; Make tile $6F solid so that it can be used as the border tile.
  ; We'll cover it up with two sprites: one in the same color as the
  ; background color and one in the same color as the selected color.
  ldx #$00
  stx PPUMASK
  lda #>(CHRBORDER_TILE << 4)
  jsr chrpicker_move_6F
  lda #$10 | >(CHRBORDER_TILE << 4)
  sta PPUADDR
  lda #<(CHRBORDER_TILE << 4)
  sta $2006
  lda #CHRBORDER_PATTERN
  ldx #16
solid6f_loop:
  sta PPUDATA
  dex
  bne solid6f_loop

  ; Start with the blank border at the top
  lda #$80
  sta PPUCTRL
  asl a
  sta PPUMASK
  lda #$20
  sta dst_hi
  sta PPUADDR
  lda #$00
  sta PPUADDR
  ldx #$68
  stx dst_lo
  lda #CHRBORDER_TILE
topborderloop:
  sta PPUDATA
  dex
  bne topborderloop
  ; tile number in X starts at 0
tilerowloop:
  ldy #16
tileloop:
  stx PPUDATA
  inx
  dey
  bne tileloop
  ldy #16
sideborderloop:
  sta PPUDATA
  dey
  bne sideborderloop
  cpx #0
  bne tilerowloop
  
  ldx #24
bottomborderloop:
  sta PPUDATA
  dex
  bne bottomborderloop

  ; clear out bottom 10 rows
  txa  ; x = 0 = blank tile
  ldx #160
textarealoop:
  sta PPUDATA
  sta PPUDATA
  dex
  bne textarealoop

  ; set attribute
  ldx #40
  lda #$55
attr1loop:
  sta PPUDATA
  dex
  bne attr1loop
  ldx #24
  lda #$00
attr0loop:
  sta PPUDATA
  dex
  bne attr0loop

  ; set up palette  
  jsr load_colorset_0
  lda PPUDATA
  ldx #$00
  lda $7F01,x
  sta PPUDATA
  lda $7F02,x
  sta PPUDATA
  lda $7F03,x
  sta PPUDATA
  lda #$3F
  sta PPUADDR
  lda #$11
  sta PPUADDR
  lda #$0F
  sta PPUDATA
  lda #$00
  sta PPUDATA
  lda #$20
  sta PPUDATA
  
  ; set sprite 0
  lda #(3+16)*8-1
  sta OAM+0
  lda #'_'
  sta OAM+1
  lda #%00100000
  sta OAM+2
  lda #224
  sta OAM+3
  ldx #4
  jmp ppu_clear_oam
.endproc

;;
; Draws an arrow sprite in color set 4 at tile coordinates (x, y).
.proc draw_arrow
  txa
  ldx oam_used
  asl a
  asl a
  asl a
  ora #$04
  sta OAM+3,x
  lda #0
  sta OAM+2,x
  lda #$04
  sta OAM+1,x
  tya
  asl a
  asl a
  asl a
  ora #$03
  sta OAM+0,x
  
  ; Draw the bottom half only if needed
  cmp #$E7
  bcs no_bottomhalf
  cpx #$FC
  bcs no_bottomhalf
  adc #$08
  sta OAM+4,x
  lda #$05
  sta OAM+5,x
  lda #$00
  sta OAM+6,x
  lda OAM+3,x
  sta OAM+7,x
  txa
  adc #$08
  sta oam_used
  rts

no_bottomhalf:
  ; assume sec
  txa
  adc #$03
  sta oam_used
  rts
.endproc

.proc chrpicker_draw_6f
  ldx oam_used
  ldy #0
loop:
  lda data_for_6f,y
  sta OAM,x
  iny
  inx
  cpy #8
  bcc loop
  stx oam_used
  rts
.pushseg
.segment "RODATA"
data_for_6f:
  .byt 23+(CHRBORDER_TILE>>4<<3), CHRBORDER_TILE, $01, 64+((CHRBORDER_TILE&$0F)<<3)
  .byt 23+(CHRBORDER_TILE>>4<<3), $01, $02, 64+((CHRBORDER_TILE&$0F)<<3)
.popseg
.endproc

;;
; Moves the selected tile based on the pressed direction.
; Left: -1; Right: +1; Up: -16; Down: +16
; @param A bitmask containing one or more of
; KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT
; @return carry set iff it moved
.proc move_selected_tile_by_dpad
  lsr a
  bcc notRight
  inc selected_tile
  rts
notRight:
  lsr a
  bcc notLeft
  dec selected_tile
  rts
notLeft:
  lsr a
  bcc notDown
  lda #16-1
  jmp add_a_plus_1_to_selected_tile
notDown:
  lsr a
  bcc notUp
  lda #240-1
add_a_plus_1_to_selected_tile:
  adc selected_tile
  sta selected_tile
  sec
notUp:
  rts
.endproc

.proc puthex
  pha
  lsr a
  lsr a
  lsr a
  lsr a
  jsr put1dig
  pla
  and #$0F
put1dig:
  ora #'0'
  cmp #'0'+10
  bcc :+
  adc #'A'-('0'+10)-1
:
  sta PPUDATA
  rts  
.endproc

.segment "RODATA"
menudata:
  .byt "      TILE:$   COLOR:",10,10
  .byt "A: DRAW WITH THIS TILE",10
  .byt "B: CHANGE COLOR SET",10
.if 0
  .byt "START: EDIT THIS TILE",10
.else
  .byt "START: ZOOM IN",10
.endif
  .byt "SELECT: MORE OPTIONS",0

menumore:
  ;    "MAXIMUM 26 CHARACTERS LONG",10
  .byt "EDIT COLOR PALETTE",10
  .byt "DRAWING HELP",10
  .byt "BLANK ALL UNUSED TILES",10
  .byt "REMOVE DUPLICATE TILES",10
  .byt "MOVE USED TILES TO TOP",10
.if 0
  .byt "ADD SPRITES",10
.endif
  .byt "VIEW PINO'S TO DO LIST",0


