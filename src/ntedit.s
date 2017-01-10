;
; Core of nametable editor
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;

.include "src/nes.h"
.include "src/ram.h"

ntupdate_dstlo = $0110
ntupdate_dsthi = $0111
ntupdate_dstattr = $0112
ntupdate_data = $0113
ntupdate_attrdata = $0114
tileupd_dstlo = $0115
tileupd_dsthi = $0116
tileupd_data = $0100

DIRTY_TILE6F = $01  ; when set, need to generate tileupd_data
DIRTY_NTTILE = $02  ; when set, need to generate ntupdate_data

NTEDIT_HEX_BASE = $70 

.segment "ZEROPAGE"
select_state: .res 1  ; to distinguish Select+direction from Select
eyedropper_state: .res 1
nt_x: .res 1
nt_y: .res 1
status_y: .res 1
dirty: .res 1
selected_tint: .res 1

.segment "CODE"
.proc ntedit
  lda #VBLANK_NMI
  sta PPUCTRL
  sta tileedit_map_mode
  lda #$E8
  sta status_y
  lda #$FF
  sta tileupd_dsthi
  sta ntupdate_dsthi
  lda #0
  sta PPUMASK
  sta select_state
  sta eyedropper_state
  jsr load_bg_palette
  lda #1
  jsr unpb53_block
  
  lda #DIRTY_TILE6F
  sta dirty

  ; load sprite palettes 0 and 2
  ldy #$3F
  sty PPUADDR
  lda #$11
  sta PPUADDR
  lda #$0F
  sta PPUDATA
  lda #$00
  sta PPUDATA
  lda #$20
  sta PPUDATA
  sty PPUADDR
  lda #$19
  sta PPUADDR
  lda $7F00
  sta PPUDATA

  jsr copy_bg_from_sram
  
  lda #0
  sta select_state

forever:

  ; Movement logic
  jsr read_pads
  ldx #0
  jsr autorepeat
  ; allow only directions to autorepeat
  lda das_keys
  and #KEY_UP|KEY_DOWN|KEY_LEFT|KEY_RIGHT
  sta das_keys
  lda cur_keys
  and #KEY_SELECT
  beq notSelect

  ; Hold Select+Control Pad: change selected tile
  and new_keys
  beq notSelectPress
  lda #$FF
  sta select_state
notSelectPress:
  lda new_keys
  jsr move_selected_tile_by_dpad
  bcc cursor_not_moved
  lda #DIRTY_TILE6F
  ora dirty
  sta dirty
  lda #0
  sta select_state
  beq controller_done
notSelect:

  lda new_keys
  jsr move_nt_xy_by_dpad
  bcc cursor_not_moved
  ; When cursor has moved, autorepeat A and B
  lda cur_keys
  and #KEY_A|KEY_B
  ora new_keys
  sta new_keys
  lsr eyedropper_state
cursor_not_moved:

  bit new_keys
  bpl notA
  jsr place_tile
  jmp controller_done
notA:
  bvc notB
  bit eyedropper_state
  bpl not_cycle
  
  ; Multiple presses of B: Increment selected color set.
  inc selected_color
  lda selected_color
  and #$03
  sta selected_color
  lda #DIRTY_TILE6F
  ora dirty
  sta dirty
  jmp controller_done  
not_cycle:
  jsr pickup_tile
  sec
  ror eyedropper_state
  jmp controller_done
notB:
controller_done:

  ; TO DO: move the status bar out of the way

  ; Draw sprites
  jsr move_status_y
  jsr ntedit_draw_status_bar
  ldx nt_x
  ldy nt_y
  jsr ntedit_draw_cursor
  ldx oam_used
  jsr ppu_clear_oam

  jsr do_dirty

  ; Wait for a vertical blank, update VRAM, and set scroll
  lda nmis
vw3:
  cmp nmis
  beq vw3
  
  lda ntupdate_dsthi
  bmi :+
  jmp do_ntupdate
:
  lda tileupd_dsthi
  bmi :+
  jmp do_tileupdate
:
done_vblank:  
  ; Turn the screen on
  ldx #0
  ldy #0
  sty OAMADDR
  lda #>OAM
  sta OAM_DMA
  lda #VBLANK_NMI|BG_1000|OBJ_0000
  sec
  jsr ppu_screen_on
  
  lda new_keys
  and #KEY_START
  beq noStart
  ldx #SCREEN_NTTOOLS
  rts
noStart:
  ; select_state nonzero + KEY_SELECT not held = want to quit
  lda select_state
  beq no_quit
  lda cur_keys
  and #KEY_SELECT
  beq quit  
no_quit:
  jmp forever
quit:
  ldx #0
  stx PPUMASK
  rts

do_tileupdate:
  lda tileupd_dsthi
  sta PPUADDR
  lda tileupd_dstlo
  sta PPUADDR
  ldx #0
tileupd_loop:
  lda tileupd_data,x
  sta PPUDATA
  inx
  cpx #16
  bcc tileupd_loop

  ; copy the palette
  lda #$3F
  sta PPUADDR
  lda #$15
  sta PPUADDR
  lda selected_color
  asl a
  asl a
  tax
  .repeat 3, I
  lda $7F01+I,x
  sta PPUDATA
  .endrepeat

  lda #$FF
  sta tileupd_dsthi
  jmp done_vblank

do_ntupdate:
  lda ntupdate_dsthi
  sta PPUADDR
  ora #$03
  tay
  lda ntupdate_dstlo
  sta PPUADDR
  lda ntupdate_data
  sta PPUDATA
  sty PPUADDR
  lda ntupdate_dstattr
  sta PPUADDR
  lda ntupdate_attrdata
  sta PPUDATA
  lda #$FF
  sta ntupdate_dsthi
  jmp done_vblank
.endproc

.proc load_bg_palette
  ; seek to the start of palette memory ($3F00-$3F1F)
  ldx #$3F
  stx PPUADDR
  ldx #$01
  stx PPUADDR
copypalloop:
  lda $7F00,x
  sta PPUDATA
  inx
  cpx #32
  bcc copypalloop
  lda $7F00
  sta PPUDATA
  rts
.endproc

.proc draw_status_sprites
srclo = 0
srchi = 1

  sty srclo
  sta srchi
  ldy #0

copyloop:
  lda (srclo),y
  clc
  adc status_y
  sta OAM,y
  iny
  .repeat 3
    lda (srclo),y
    sta OAM,y
    iny
  .endrepeat
  dex
  bne copyloop
  sty oam_used
  rts
.endproc

; OAM in ntedit-type is statically allocated.
; 0-12: "BG Edt"
; 16: High digit
; 20: Low digit
; 24-44: "$xx %%"
; 48-52: two copies of blank tile ($6F)
.proc ntedit_draw_status_bar
rowtiles = 0

  lda #>ntedit_status_bar_data
  ldy #<ntedit_status_bar_data
  ldx #(ntedit_status_bar_end-ntedit_status_bar_data)/4
  jsr draw_status_sprites

  ; Draw tile number
  lda selected_tile
  lsr a
  lsr a
  lsr a
  lsr a
  ora #NTEDIT_HEX_BASE
  sta OAM+29
  lda selected_tile
  and #$0F
  ora #NTEDIT_HEX_BASE
  sta OAM+33

  ; Draw coordinates
  lda nt_x
  ldx #56
  jsr oam_bcd_stuff
  lda nt_y
  ldx #68
  ; fall through
.endproc
.proc oam_bcd_stuff
  jsr bcd8bit
  ora #$70
  sta OAM+5,x
  lda 0
  beq no_tens
  ora #$70
  sta OAM+1,x
no_tens:
  rts
.endproc

.segment "RODATA"
ntedit_status_bar_data:
  .byt $00,$7B,$00,$18
  .byt $00,$60,$00,$20
  .byt $00,$01,$00,$28
  .byt $00,$7E,$00,$30
  .byt $00,$62,$00,$38
  .byt $00,$63,$00,$40

  .byt $08,$64,$00,$18
  .byt $08,'?',$00,$20
  .byt $08,'?',$00,$28
  .byt $08,$01,$00,$30
  .byt $08,$6F,$01,$38
  .byt $08,$6F,$01,$40
  .byt $08,$01,$02,$38
  .byt $08,$01,$02,$40

  .byt $10,$01,$00,$18
  .byt $10,'?',$00,$20
  .byt $10,$65,$00,$28
  .byt $10,$01,$00,$30
  .byt $10,'?',$00,$38
  .byt $10,$01,$00,$40
ntedit_status_bar_end:

.segment "CODE"

;;
; Draws the box-shaped cursor at (x*8, y*8).
.proc ntedit_draw_cursor
base_x = 3
base_y = 0
  txa
  ldx oam_used
  cpx #$F0
  bcc no_overflow
  rts
no_overflow:
  asl a
  asl a
  asl a
  sta base_x
  tya
  asl a
  asl a
  asl a
  sta base_y
;  jmp draw_arrow
  beq no_top_row
  sec
  sbc #5
  sta OAM+0,x
  sta OAM+4,x
  lda #$66
  sta OAM+1,x
  sta OAM+5,x
  lda #%11000000
  sta OAM+2,x
  asl a
  sta OAM+6,x
  lda base_x
  ora #4
  sta OAM+3,x
  sec
  sbc #8
  bcc no_top_left
  sta OAM+7,x
  inx
  inx
  inx
  inx
no_top_left:
  inx
  inx
  inx
  inx
no_top_row:
  lda base_y
  clc
  adc #3
  sta OAM+0,x
  sta OAM+4,x
  lda #$67
  sta OAM+1,x
  lda #$66
  sta OAM+5,x
  lda #%00000000
  sta OAM+2,x
  sta OAM+6,x
  lda base_x
  ora #4
  sta OAM+3,x
  sec
  sbc #8
  bcc no_bottom_left
  sta OAM+7,x
  inx
  inx
  inx
  inx
no_bottom_left:
  inx
  inx
  inx
  inx

  stx oam_used
  rts
.endproc

.proc copy_bg_from_sram_to_r
  lda #$24
  bne :+
to_l:
  lda #$20
:
  ldy #$00
  sty PPUMASK
  sta PPUADDR
  sty PPUADDR
  lda #$78
  ldx #4
  jmp load_x_rows_from_ay
.endproc
copy_bg_from_sram = copy_bg_from_sram_to_r::to_l

;;
; Moves the cursor
; Left: -1; Right: +1; Up: -16; Down: +16
; @param A bitmask containing one or more of
; KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT
; @return carry set iff it moved
.proc move_nt_xy_by_dpad
  lsr a
  bcc notRight
  inc nt_x
  bcs wrap_nt_x
notRight:
  lsr a
  bcc notLeft
  dec nt_x
wrap_nt_x:
  lda nt_x
  and #$1F
  sta nt_x
  rts
notLeft:
  lsr a
  bcc notDown
  inc nt_y
  lda nt_y
  cmp #30
  bcc no_wrap_y
  lda #0
  beq have_nt_y
notDown:
  lsr a
  bcc notUp
  dec nt_y
  bpl no_wrap_y
  lda #29
have_nt_y:
  sta nt_y
no_wrap_y:
  sec
notUp:
  rts
.endproc

.proc do_dirty
  lda dirty
  lsr a
  bcc :+
  lda selected_tile
  jmp prepare_tileupd
:
  lsr a
  bcc :+
  jmp prepare_ntupdate
:
  rts
.endproc

;;
; Copies tile A from SRAM into tileupd_data.
.proc prepare_tileupd
  asl a
  sta 0
  lda #0
  rol a
  .repeat 3
  asl 0
  rol a
  .endrepeat
  ora #>SRAM_BGCHR
  sta 1
  ldy #15
loop:
  lda (0),y
  sta tileupd_data,y
  dey
  bpl loop
  lda #$06
  sta tileupd_dsthi
  lda #$F0
  sta tileupd_dstlo
  lda #<~DIRTY_TILE6F
  and dirty
  sta dirty
  rts
.endproc

.proc prepare_ntupdate
  jsr nt_xy_to_address
  lda 0
  sta ntupdate_dstlo
  lda 1
  ora #$20
  sta ntupdate_dsthi
  eor #($78^$20)
  sta 1
  ora #$03
  sta 3
  lda 2
  sta ntupdate_dstattr
  ldy #0
  lda (0),y
  sta ntupdate_data
  lda (2),y
  sta ntupdate_attrdata
  
  lda #<~DIRTY_NTTILE
  and dirty
  sta dirty
  rts
.endproc

;;
; Calculates the nametable and attribute addresses corresponding
; to the tile whose coordinates are (nt_x, nt_y).
; @return
; 0: address low
; 1: address high
; 2: attribute address low
; 4: attribute position (shift twice for each unit)
.proc nt_xy_to_address
  lda #0
  sta 0
  lda nt_y
  lsr a
  ror 0
  lsr a
  ror 0
  lsr a
  sta 1
  lda 0
  ror a
  ora nt_x
  sta 0

  ; Calculate attribute shift
  lsr a
  and #$01  ; A bit 0 = nt_x bit 1
  eor nt_y
  and #%11111101
  eor nt_y
  sta 4

  ; Calculate attribute address  
  lda nt_y
  asl a
  sta 2
  lda nt_x
  lsr a
  lsr a
  ora #$C0
  eor 2
  and #%11000111
  eor 2
  sta 2
  rts
.endproc

.proc pickup_tile
  jsr nt_xy_to_address
  lda 1
  ora #$78
  sta 1
  ora #$03
  sta 3
  ldy #0
  lda (0),y
  sta selected_tile
  lda (2),y
  ldy 4
  beq no_shifts
shifts_loop:
  lsr a
  lsr a
  dey
  bne shifts_loop
no_shifts:
  and #$03
  sta selected_color
  lda #DIRTY_TILE6F
  ora dirty
  sta dirty
  rts
.endproc

.proc place_tile
  jsr nt_xy_to_address
  lda 1
  ora #$78
  sta 1
  ora #$03
  sta 3
  ldy #0
  lda selected_tile
  sta (0),y
  
  ; Now that the selected tile has been placed on the map,
  ; we no longer need 0-1. Reassign 0 for the mask.
  lda #$03
  sta 0
  lda selected_color
  ldy 4
  beq no_shifts
shifts_loop:
  asl a
  asl a
  asl 0
  asl 0
  dey
  bne shifts_loop
no_shifts:
  eor (2),y
  and 0
  eor (2),y
  sta (2),y

  lda #DIRTY_NTTILE
  ora dirty
  sta dirty
  rts
.endproc

.proc move_status_y
target = 0
  lda #31
  ldy nt_y
  ; 2012-09-28: use signed subtraction result (bpl) not unsigned
  ; (bcs) because nt_x is allowed to be negative in copipe
  cpy #15
  bpl :+
  lda #183
:
  sta target
  sec
  sbc status_y
  ; A: total distance that must be moved (signed)
  beq already_there
  bmi move_up

  ; At this point, the status bar has to move DOWN
  cmp #32
  bcc :+
  lda #32
:
  ora #3
  lsr a
  lsr a
have_offset:
  adc status_y
  sta status_y
already_there:
  rts

move_up:
  cmp #256-32
  bcs :+
  lda #256-32
:
  lsr a
  lsr a
  clc
  ora #$C0
  bne have_offset
.endproc

.proc attribute_viewer
  lda #VBLANK_NMI
  sta PPUCTRL
  asl a
  sta PPUMASK
  ldy #$20
  sty PPUADDR
  sta PPUADDR
  lda #$00
  ldy #30
rowloop:
  ldx #32
tileloop:
  sta PPUDATA
  eor #$01
  dex
  bne tileloop
  eor #$02
  dey
  bne rowloop

  ; copy attributes
  ldx #$C0
attrloop:
  lda SRAM_NT+768,x
  sta PPUDATA
  inx
  bne attrloop
  jsr load_bg_palette
  jsr press_any_key
  ldx #SCREEN_NTEDIT
  rts
.endproc

