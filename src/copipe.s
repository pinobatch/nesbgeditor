;
; Nametable copy and paste
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;

.include "nes.inc"
.include "global.inc"

SLICE_MAX_HT = 5

copysrcleft   = $08
copysrctop    = $09
copysrcwid    = $0A
copysrcht     = $0B
copydstleft   = $0C
copydsttop    = $0D
pastebufdstlo = $0E
pastebufdsthi = $0F
pastebuf = $0100


.segment "ZEROPAGE"
corner_x: .res 1
corner_y: .res 1
brcorner_x = pixel_x  ; borrow from tileedit
brcorner_y = pixel_y  ; 
.segment "CODE"
.proc nt_copipe
  lda #VBLANK_NMI
  sta PPUCTRL
  sta pastebufdsthi
  lda #0
  sta PPUMASK
  sta select_state
  sta redraw_y
  jsr load_bg_palette

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
  lda #1
  jsr unpb53_block
  
  ; copy attributes to page 1
  lda #$27
  sta PPUADDR
  lda #$C0
  sta PPUADDR
  ldx #$C0
attrinitloop:
  lda SRAM_NT+$300,x
  sta PPUDATA
  inx
  bne attrinitloop

forever:
  ; Movement logic
  jsr read_pads
  ldx #0
  jsr autorepeat
  ; allow only directions to autorepeat
  lda das_keys
  and #KEY_UP|KEY_DOWN|KEY_LEFT|KEY_RIGHT
  sta das_keys
  lda select_state
  cmp #2
  bcc move_one_corner  ; state 0-1: Move one corner at a time
  bne been_moved       ; state 3: Allow no movement
  lda new_keys
  jsr paste_move_nt_xy
  bcc :+
  lda #0
  sta redraw_y
:
  lda redraw_y
  cmp #30 / SLICE_MAX_HT
  bcs s2_no_redraw
  jsr get_clipped_copy_area
  lda redraw_y
  inc redraw_y
  jsr make_paste_slice
s2_no_redraw:
  jmp been_moved
  
move_one_corner:
  lda new_keys
  jsr move_nt_xy_by_dpad
been_moved:

  lda select_state
  bne no_move_corner_x
  lda nt_x
  sta corner_x
  lda nt_y
  sta corner_y
no_move_corner_x:
  jsr move_status_y

  ; In state 3, ignore all keypresses and complete the process
  ; of pasting.
  lda select_state
  cmp #3
  bcc not_pasting_state
  ; TO DO: actual pasting
  jmp notA
not_pasting_state:

  lda new_keys
  and #KEY_START
  beq notStart
  ldx #SCREEN_NTTOOLS
  rts
notStart:

  bit new_keys
  bvc notB
  dec select_state
  bmi quit_to_ntedit
  bne B_state2to1

  ; when going from select_state 1 to 0, move cursor to top left
  ldx corner_x
  ldy corner_y
  jmp B_setntxy

B_state2to1:
  ; when going from select_state 2 to 1, move cursor to bottom right
  ; and clear redraw_y (so that display is set back to page 0)
  ldx brcorner_x
  ldy brcorner_y
B_setntxy:
  stx nt_x
  sty nt_y
  lda #0
  sta redraw_y
  beq notB

notB:

  lda new_keys
  and #KEY_SELECT
  beq not_quit
quit_to_ntedit:
  ldx #SCREEN_NTEDIT
  rts
not_quit:

  bit new_keys
  bpl notA
  lda #0
  sta redraw_y
  lda select_state
  cmp #1
  beq A_state1to2
  bcs A_state2
A_state1to2:
  jsr sort_corners
A_state0to1:
  inc select_state
  bne notA
A_state2:
  jsr commit_paste
notA:

  jsr copipe_draw_status_bar

  ; BEGIN VBLANK PROCESSING ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  ldx oam_used
  jsr ppu_clear_oam
  bit PPUSTATUS
  lda nmis
vwait:
  cmp nmis
  beq vwait
  
  ; TO DO: copy paste preview buffer if appropriate Y
  lda pastebufdsthi
  bmi nowritepastebuf
  sta PPUADDR
  lda pastebufdstlo
  sta PPUADDR
  ldx #0
  clc
pasteblitloop:
  .repeat 16, I
    lda pastebuf+I,x
    sta PPUDATA
  .endrepeat
  
  txa
  adc #16
  tax
  cpx #32*SLICE_MAX_HT
  bcc pasteblitloop
  stx pastebufdsthi
nowritepastebuf:

  ; Copy sprites, set scroll, and turn rendering back on
  ldx #0
  stx OAMADDR
  lda #>OAM
  sta OAM_DMA
  lda #VBLANK_NMI|OBJ_0000|BG_1000
  ldy redraw_y
  cpy #(30 / SLICE_MAX_HT - 1)
  adc #0
  ldy #0
  sec
  jsr ppu_screen_on
  ; END VBLANK PROCESSING ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
  jmp forever
.endproc

.proc sort_corners
  lda corner_x
  cmp nt_x
  bcs corner_x_is_higher
  lda nt_x
corner_x_is_higher:
  sta brcorner_x
  eor nt_x
  eor corner_x
  sta corner_x
  sta nt_x

  lda corner_y
  cmp nt_y
  bcs corner_y_is_higher
  lda nt_y
corner_y_is_higher:
  sta brcorner_y
  eor nt_y
  eor corner_y
  sta corner_y
  sta nt_y
  rts
.endproc

.proc paste_move_nt_xy
  lsr a
  bcc notRight
  lda nt_x
  bmi okLeft
  cmp #31
  bcs notMove
okLeft:
  inc nt_x
  sec
  rts
notRight:

  lsr a
  bcc notLeft
  lda nt_x
  clc
  adc brcorner_x
  sec
  sbc corner_x
  ; A is x + w - 1
  bcc notMove
  beq notMove
  dec nt_x
  rts
notLeft:

  lsr a
  bcc notDown
  lda nt_y
  bmi okDown
  cmp #29
  bcs notMove
okDown:
  inc nt_y
  sec
  rts
notDown:

  lsr a
  bcc notUp
  lda nt_y
  clc
  adc brcorner_y
  sec
  sbc corner_y
  ; A is y + h - 1
  bcc notMove
  beq notMove
  dec nt_y
  rts
notUp:

notMove:
  clc
  rts
.endproc

.proc copipe_draw_status_bar
  ldx #10
  lda select_state
  beq :+
  cmp #2
  bcc not_state_2
  jmp paste_draw_status_bar
not_state_2:
  ldx #15
:
  lda #>copipe_status_bar_data
  ldy #<copipe_status_bar_data
  jsr draw_status_sprites

  ; draw coordinates
  lda corner_x
  ldx #20
  jsr oam_bcd_stuff
  lda corner_y
  ldx #32
  jsr oam_bcd_stuff
  lda select_state
  bne do_second_coord

  ; draw cursor for single coord
  ldy corner_y
  ldx corner_x
  jsr corner_shift
  sty OAM+40
  stx OAM+43
  lda #$68
  sta OAM+41
  lda #0
  sta OAM+42
  lda #44
  sta oam_used
  rts

do_second_coord:
  lda nt_x
  ldx #40
  jsr oam_bcd_stuff
  lda nt_y
  ldx #52
  jsr oam_bcd_stuff
  ; TODO: draw cursor

  ; Draw rectangle cursor
flips = 0
  lda #0
  sta flips
  ldx corner_x
  cpx nt_x
  ror flips
  ldy corner_y
  cpy nt_y
  ror flips
  ; 60: CXCY
  ; 64: NXCY
  ; 68: CXNY
  ; 72: NXNY
  jsr corner_shift
  stx OAM+63
  stx OAM+71
  sty OAM+60
  sty OAM+64
  ldx nt_x
  ldy nt_y
  jsr corner_shift
  stx OAM+67
  stx OAM+75
  sty OAM+68
  sty OAM+72
  lda #$68
  sta OAM+61
  sta OAM+65
  sta OAM+69
  sta OAM+73
  lda flips
  sta OAM+62
  eor #%01000000
  sta OAM+66
  eor #%11000000
  sta OAM+70
  eor #%01000000
  sta OAM+74
  lda #76
  sta oam_used
  rts
  
corner_shift:
  tya
  asl a
  asl a
  asl a
  tay
  beq :+
  dey
:
  txa
  asl a
  asl a
  asl a
  tax
  rts

paste_draw_status_bar:
  lda #>paste_status_bar_data
  ldy #<paste_status_bar_data
  ldx #12
  jsr draw_status_sprites

  ldx #$00
  lda nt_x
  sec
  sbc corner_x
  bpl paste_isRight
  clc
  eor #$FF
  adc #1
  ldx #$40
paste_isRight:
  stx OAM+26
  ldx #28
  jsr oam_bcd_stuff

  ldx #$00
  lda nt_y
  sec
  sbc corner_y
  bpl paste_isUp
  clc
  eor #$FF
  adc #1
  ldx #$80
paste_isUp:
  stx OAM+38
  ldx #40
  jsr oam_bcd_stuff

  rts

.endproc

.segment "RODATA"
copipe_status_bar_data:
  .byt $00,$7C,$00,$18  ; C
  .byt $00,$70,$00,$20  ; 0
  .byt $00,$6E,$00,$28  ; P
  .byt $00,$6F,$00,$30  ; Y
  .byt $00,$01,$00,$38

  .byt $08,$01,$00,$18
  .byt $08,$01,$00,$20
  .byt $08,$65,$00,$28  ; comma
  .byt $08,$01,$00,$30
  .byt $08,$01,$00,$38

  .byt $10,$01,$00,$18
  .byt $10,$01,$00,$20
  .byt $10,$65,$00,$28  ; comma
  .byt $10,$01,$00,$30
  .byt $10,$01,$00,$38

paste_status_bar_data:
  .byt $00,$6E,$00,$18  ; P
  .byt $00,$7A,$00,$20  ; A
  .byt $00,$6B,$00,$28  ; S
  .byt $00,$6C,$00,$30  ; T
  .byt $00,$7E,$00,$38  ; E
  .byt $00,$01,$00,$40

  .byt $08,$69,$00,$18  ; right arrow
  .byt $08,$01,$00,$20
  .byt $08,$01,$00,$28
  .byt $08,$6A,$00,$30  ; down arrow
  .byt $08,$01,$00,$38
  .byt $08,$01,$00,$40

.segment "CODE"
;;
; Given a copy request whose source is (corner_x, corner_y) to
; (brcorner_x, brcorner_y) inclusive and whose top left corner of
; destination is (nt_x, nt_y), find the part of this rectangle that
; is on-screen.
.proc get_clipped_copy_area
  ; width = (-corner_x) + br_corner_x + 1
  lda corner_x
  sta copysrcleft
  sec 
  eor #$FF
  adc brcorner_x
  clc
  adc #1
  sta copysrcwid

  ; if nt_x < 0: width += nt_x; left -= nt_x
  lda nt_x
  bpl not_clipped_left
  clc
  adc copysrcwid
  bcc clip_rejected
  sta copysrcwid
  lda copysrcleft
  sbc nt_x
  sta copysrcleft
  lda #0
not_clipped_left:
  ; if off right side, no need to copy at all
  cmp #32
  bcs clip_rejected
  sta copydstleft

  ; if left + width > 32: width = 32 - left
  clc
  adc copysrcwid
  cmp #32
  bcc not_clipped_right
  lda #32
  sbc copydstleft
  sta copysrcwid
not_clipped_right:

  ; height = (-corner_y) + br_corner_y + 1
  lda corner_y
  sta copysrctop
  sec 
  eor #$FF
  adc brcorner_y
  clc
  adc #1
  sta copysrcht

  ; if nt_x < 0: height += nt_x; top -= nt_x
  lda nt_y
  bpl not_clipped_top
  clc
  adc copysrcht
  bcc clip_rejected
  sta copysrcht
  lda copysrctop
  sbc nt_y
  sta copysrctop
  lda #0
not_clipped_top:
  ; if off bottom, no need to copy at all
  cmp #30
  bcs clip_rejected
  sta copydsttop

  ; if top + height > 30: height = 30 - top
  clc
  adc copysrcht
  cmp #30
  bcc not_clipped_bottom
  lda #30
  sbc copydsttop
  sta copysrcht
not_clipped_bottom:

  sta $FF  ; debugger checkpoint
  rts
clip_rejected:
  lda #$00
  sta copysrcwid
  sta copysrcht
  sta $FF
  rts
.endproc

;;
; Calculates the base address of a row in a nametable.
; @param A 
; @return Y: bits 0-7; A: bits 8-9
.proc bascalc_ay
  lsr a
  ror a
  ror a
  pha
  ror a
  and #%11100000
  tay
  pla
  and #%00000011
  rts
.endproc

;;
; Prepares one cycle of paste preview.
;
; Paste and paste preview both work by copying to a 5-line slice.
; Upward copies (copysrctop >= copydsttop) use an increasing sequence
; of six slice origins; downward copies (copysrctop < copydsttop)
; use a decreasing sequence.
; Each cycle of paste preview works by copying the existing image
; to the slice, then vertically clipping the copy area to the slice.
; @param A step number (0-5)
.proc make_paste_slice
srclo = 0
srchi = 1
dstlo = 2
dsthi = 3
slice_top = 4

slice_srctop = 5
slice_dsttop = 6
slice_ht = 7

  ; Step 1: Load the background
  sta slice_top
  asl a
  asl a
  adc slice_top
  sta slice_top
  jsr bascalc_ay
  sty srclo
  sty pastebufdstlo
  ora #>SRAM_NT
  sta srchi
  and #$03
  ora #$24
  sta pastebufdsthi
  
  ldy #0
copy_src_loop:
  lda (srclo),y
  sta pastebuf,y
  iny
  cpy #32*SLICE_MAX_HT
  bcc copy_src_loop

  ; Trim against bottom of slice
  lda slice_top
  clc
  adc #SLICE_MAX_HT
  sec
  sbc copydsttop
  beq reject_slice
  bcs :+    ; cc: top of rect below bottom of slice
reject_slice:
  lda #0
  sta slice_ht
  rts
:
  ; A = distance from top of dst to bottom of slice
  cmp copysrcht
  bcc not_past_bottom
  lda copysrcht
not_past_bottom:
  sta slice_ht

  ; Trim against top of slice
  lda copysrctop
  sta slice_srctop
  lda copydsttop
  sta slice_dsttop
  sec
  sbc slice_top
  bcs not_past_top
  tay  ; Y = negative of the number of rows to remove
  adc slice_ht
  bcc reject_slice  ; cc: bottom of rect above top of slice
  beq reject_slice  ; eq: bottom of rect at top of slice
  sta slice_ht
  tya
  eor #$FF
  adc slice_srctop
  sta slice_srctop
  lda slice_top
  sta slice_dsttop
not_past_top:

  ; At this point, we need to go (slice_dsttop - slice_top) rows down
  ; in the destination buffer and copy slice_ht rows starting at row
  ; slice_srctop.
  lda slice_dsttop
  sec
  sbc slice_top
  asl a
  asl a
  asl a
  asl a
  asl a
  adc copydstleft
  sta dstlo
  lda #>pastebuf
  sta dsthi
  lda slice_srctop
  jsr bascalc_ay
  ora #>SRAM_NT
  sta srchi
  tya
  ora copysrcleft
  sta srclo
  
  ; Now the starting points are in srclo and dstlo.
  ; Copy a copysrcwid by slice_ht 
rowloop:
  ldy copysrcwid
  dey
tileloop:
  lda (srclo),y
  sta (dstlo),y
  dey
  bpl tileloop
  clc
  lda dstlo
  adc #32
  sta dstlo
  lda srclo
  adc #32
  sta srclo
  bcc :+
  inc srchi
:
  dec slice_ht
  bne rowloop
  rts
.endproc

.proc commit_paste
dstlo = 0
dsthi = 1
  jsr get_clipped_copy_area
  
  ; srctop < dsttop: copy 5-0
  ; srctop > dsttop: copy 0-5
  lda copysrctop
  cmp copydsttop
  lda #0
  sta PPUMASK
  bcs :+
  lda #(30/SLICE_MAX_HT) - 1
:
sliceloop:
  sta redraw_y
  jsr make_paste_slice

  ; Copy simultaneously back to the document and to screen page 0
  lda pastebufdsthi
  and #$23
  sta PPUADDR
  ora #>SRAM_NT
  sta dsthi
  lda pastebufdstlo
  sta PPUADDR
  sta dstlo
  ldy #0
copyloop:
  lda pastebuf,y
  sta (dstlo),y
  sta PPUDATA
  iny
  cpy #32*SLICE_MAX_HT
  bcc copyloop
 
  ; Move to next slice
  lda copysrctop
  cmp copydsttop
  lda #0  ; with carry set, acts as 1
  bcs :+
  lda #<-1
:
  adc redraw_y
  cmp #(30/SLICE_MAX_HT)
  bcc sliceloop
  
  ; Detect overlap
  ; if abs(copydsttop - copysrctop) >= orig ht then no overlap
  ; if abs(copydstleft - copysrcleft) >= copysrcwid then no overlap
  ; we have to recompute the original width and height because it's
  ; possible for clipping to turn an overlap into a nonoverlap
  lda brcorner_y
  sec
  sbc corner_y
  adc #0
  sta 0
  lda copydsttop
  sec
  sbc copysrctop
  bcs :+
  eor #$FF
  adc #1
:
  cmp 0
  bcs no_overlap

  lda brcorner_x
  sec
  sbc corner_x
  adc #0
  sta 0
  lda copydstleft
  sec
  sbc copysrcleft
  bcs :+
  eor #$FF
  adc #1
:
  cmp 0
  bcs no_overlap

  ; At this point, src and dst are overlapping.  Now move the corners
  ; to the dst rectangle and bail if the corners are offscreen.
  lda brcorner_x
  sec
  sbc corner_x
  clc
  adc nt_x
  cmp #32
  bcs offscreen_overlap
  sta brcorner_x

  lda brcorner_y
  sec
  sbc corner_y
  clc
  adc nt_y
  cmp #30
  bcs offscreen_overlap
  sta brcorner_y
  lda nt_x
  bmi offscreen_overlap
  sta corner_x
  lda nt_y
  bmi offscreen_overlap
  sta corner_y
no_overlap:
  rts

offscreen_overlap:
  lda #0
  sta select_state
  sta redraw_y
  bit nt_x
  bpl :+
  sta nt_x
:
  bit nt_y
  bpl :+
  sta nt_y
:
  rts
.endproc
