;
; Palette editor for NES graphics editor
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;
.include "nes.inc"
.include "global.inc"
.importzp das_timer

HOLD_A_THRESHOLD = 30  ; frames

.segment "CODE"

; paledit does not jsr autorepeat, so it can use das_timer the way
; it wants: to count how long A has been held.

.proc paledit
  asl selected_color
  sec
  rol selected_color

  jsr paledit_draw_bg

  ; Set up OAM to show color set 7 in the color set 0 space
  ldx #23
oaminitloop:
  lda oam_for_colorset_7,x
  sta OAM,x
  dex
  bpl oaminitloop

forever:
  ldx #24
  stx oam_used
  jsr paledit_draw_cursor
  ldx oam_used
  jsr ppu_clear_oam

  lda #VBLANK_NMI
  sta PPUCTRL
  lda nmis
:
  cmp nmis
  beq :-

  ; of where is currently pointed
  ldx selected_color
  jsr paledit_draw_hexvalue
  ldx selected_color
  bne no_reload_cs0
  jsr load_colorset_0
no_reload_cs0:

  ldx #0
  ldy #0
  stx OAMADDR
  lda #>OAM
  sta OAM_DMA
  lda #VBLANK_NMI|BG_0000|OBJ_0000
  sec
  jsr ppu_screen_on
  jsr read_pads

  ; Now respond to input
  ; A toggles between selecting a palette entry and changing it
  lda new_keys
  and #KEY_A
  eor select_state
  sta select_state

  ; If A is being held, increase das_timer; otherwise clear it.
  
  bit cur_keys
  bpl clearDASTimer
  inc das_timer
  bpl doneA
  dec das_timer
  jmp doneA
clearDASTimer:
  lda das_timer
  cmp #HOLD_A_THRESHOLD
  bcc notReleaseA
  lda #0
  sta select_state
notReleaseA:
  lda #0
  sta das_timer
doneA:

  lda new_keys
  and #KEY_B
  beq notB
  lda #0
  sta select_state
notB:

  lda select_state
  bne drag_motion
  jsr paledit_cursor_movement
  jmp dpad_done
drag_motion:
  jsr paledit_change_selected_color
  
  ; If a color was changed, and A is being held, set the hold time
  ; to the threshold time so that releasing A leaves change mode.
  bcc dpad_done
  bit cur_keys
  bpl dpad_done
  lda #HOLD_A_THRESHOLD
  sta das_timer
dpad_done:

  lda new_keys
  and #KEY_START|KEY_SELECT
  bne done
  jmp forever
done:
  lsr selected_color
  lsr selected_color
  ldx #SCREEN_CHRPICKER
  rts
.endproc

.proc paledit_cursor_movement
  lda new_keys
  lsr a
  bcc notRight
  lda selected_color
  and #%00000011
  beq notUp
  lda selected_color
  ora #%00000100
  sta selected_color
  rts
notRight:

  lsr a
  bcc notLeft
  lda selected_color
  and #%00011011
  sta selected_color
  rts
notLeft:

  lsr a
  bcc notDown
  lda selected_color
  and #$0B
  cmp #$0B
  beq notUp
  cmp #3
  bne down_not3
  lda selected_color
  clc
  adc #5
  sta selected_color
down_not3:
  inc selected_color
  rts
notDown:

  lsr a
  bcc notUp
  lda selected_color
  and #$0B
  beq notUp
  cmp #1
  bne up_not1
  lda selected_color
  and #$10
  sta selected_color
  rts
up_not1:
  cmp #9
  bne up_not5
  lda selected_color
  sec
  sbc #5
  sta selected_color
up_not5:
  dec selected_color
notUp:
  rts
.endproc

.proc paledit_change_selected_color
  ldx selected_color
  txa
  and #$0F
  beq :+
  tax
:
  lda new_keys
  
  ; Right:
  ; If $xD-$xF, set to $00.
  ; If $xC, set to $x0.
  ; Otherwise, increment.
  lsr a
  bcc notRight
  lda SRAM_PALETTE,x
  and #$0F
  cmp #$0C
  bne not_xC_to_x0
  lda SRAM_PALETTE,x
  and #$30
  sta SRAM_PALETTE,x
  rts
not_xC_to_x0:
  bcs setToDarkGray
  inc SRAM_PALETTE,x
  sec
  rts
setToDarkGray:
  lda #$00
  sta SRAM_PALETTE,x
  rts
notRight:

  ; Left:
  ; If $xD-$xF, set to $00.
  ; If $x0, set to $x0.
  ; Otherwise, decrement.
  lsr a
  bcc notLeft
  lda SRAM_PALETTE,x
  and #$0F
  bne not_x0_to_xC
  lda SRAM_PALETTE,x
  ora #$0C
  sta SRAM_PALETTE,x
  rts
not_x0_to_xC:
  cmp #$0D
  bcs setToDarkGray
  dec SRAM_PALETTE,x
  sec
  rts
notLeft:

  ; Down:
  ; If $0x, set to $0F.
  ; Otherwise, subtract $10.
  lsr a
  bcc notDown
  lda SRAM_PALETTE,x
  sec
  sbc #$10
  bcs :+
  lda #$0F
  sec
:
  sta SRAM_PALETTE,x
  rts
notDown:

  ; Up:
  ; If $xD-$xF, set to $00.
  ; If $3x, set to $30.
  ; Otherwise, add $10.
  lsr a
  bcc notUp
  lda SRAM_PALETTE,x
  and #$0F
  cmp #$0D
  bcs setToDarkGray
up_notBlack:
  lda SRAM_PALETTE,x
  adc #$10
  cmp #$3D
  bcc up_notWhite
  lda #$30
up_notWhite:
  sec
  sta SRAM_PALETTE,x
notUp:
  rts
.endproc

.proc paledit_draw_bg
screensrc = 0
  lda #0
  sta PPUCTRL
  sta PPUMASK
  sta select_state
  tay
  ldx #$20
  jsr ppu_clear_nt
  lda #<paledit_screendata
  sta screensrc
  lda #>paledit_screendata
  sta screensrc+1
segloop:
  ldy #0
  lda (screensrc),y
  beq segdone
  and #$80
  beq not_down
  lda #VRAM_DOWN
not_down:
  sta PPUCTRL
  lda (screensrc),y
  sta PPUADDR
  iny
  lda (screensrc),y
  sta PPUADDR
  iny
byteloop:
  lda (screensrc),y
  beq bytedone
  sta PPUDATA
  iny
  bne byteloop
bytedone:
  tya
  sec  ; increment past the 0
  adc screensrc
  sta screensrc
  bcc :+
  inc screensrc+1
:
  jmp segloop
  
segdone:
  ldx #15
load_all_hexvalues:
  jsr paledit_draw_hexvalue
  dex
  bpl load_all_hexvalues

  ; arrow cursor palette (black, gray, white)
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
  jmp load_colorset_0
.endproc

.proc paledit_draw_hexvalue
  ; 2108: 0
  ; 2188: 1-3
  ; 2198: 5-7
  ; 2248: 9-11
  ; 2258: 13-15
  txa
  and #$0F
  bne not_bgmirror
  tax
not_bgmirror:
  tay   ; X: palette index; Y: palette index mod 16

  ; Set the palette value
  lda #$3F
  sta PPUADDR
  tya
  beq not_colorset0to7
  cpy #4
  bcs not_colorset0to7
  ora #$1C
not_colorset0to7:
  sta PPUADDR
  lda SRAM_PALETTE,x
  sta PPUDATA

  cpy #8
  lda #$21
  adc #$00
  sta PPUADDR
  lda hexvalue_addrlo,y
  sta PPUADDR
  bne not_x4x8xC
  rts
not_x4x8xC:
  lda SRAM_PALETTE,x
  and #$3F
.if 0
  jsr puthex
  lda #$23
  sta PPUADDR
  sta PPUADDR
  txa
.endif
  jmp puthex
.endproc

.proc paledit_draw_cursor
cursor_y = 0
cursor_x = 3
  lda selected_color
  and #%00000100
  beq not_rightcol
  lda #128
not_rightcol:
  ora #16
  .if 0
    clc
    adc das_timer
  .endif
  sta cursor_x
  lda selected_color
  and #%00001011
  cmp #8
  bcc not_8toF
  sbc #2
not_8toF:
  cmp #0
  beq in_bgspace
  adc #3-1
in_bgspace:
  asl a
  asl a
  asl a
  adc #63
  sta cursor_y
  
  ldx oam_used
  lda cursor_y
  sta OAM+0,x
  lda cursor_x
  sta OAM+3,x
  lda #0
  sta OAM+2,x
  lda select_state
  bne draw_full_arrow
  lda #7  ; outlined right-pointing arrowhead
  sta OAM+1,x
  txa
  clc
  adc #4
  sta oam_used
  rts
draw_full_arrow:
  lda #6  ; outlined right-pointing arrow stem
  sta OAM+1,x
  lda cursor_y
  sta OAM+4,x
  lda cursor_x
  ora #$06
  sta OAM+7,x
  lda #0
  sta OAM+6,x
  lda #7  ; outlined right-pointing arrowhead
  sta OAM+5,x
  txa
  clc
  adc #8
  sta oam_used
  rts
.endproc

.segment "RODATA"
paledit_screendata:
  .byt $20,$67,"EDIT COLOR PALETTE",0
  .byt $20,$E2,"BACKGROUND COLOR",0
  .byt $21,$07,"$",0
  .byt $21,$62,"COLOR SET 0",0
  .byt $A1,$87,"$$$",0
  .byt $21,$72,"COLOR SET 1",0
  .byt $21,$94,1,1," $",0
  .byt $21,$B4,2,2," $",0
  .byt $21,$D4,3,3," $",0
  .byt $22,$22,"COLOR SET 2",0
  .byt $22,$44,1,1," $",0
  .byt $22,$64,2,2," $",0
  .byt $22,$84,3,3," $",0
  .byt $22,$32,"COLOR SET 3",0
  .byt $22,$54,1,1," $",0
  .byt $22,$74,2,2," $",0
  .byt $22,$94,3,3," $",0
  .byt $23,$DD,$11,$00
  .byt $23,$E1,$20,$00
  .byt $23,$E9,$02,$00
  .byt $23,$E5,$30,$00
  .byt $23,$ED,$03,$00
  .byt $23,$03,"SELECT: EXIT",0
  .byt 0
oam_for_colorset_7:
  .byt  95,1,3,32, 95,1,3,40
  .byt 103,2,3,32,103,2,3,40
  .byt 111,3,3,32,111,3,3,40
hexvalue_addrlo:
  .byt $08,$88,$A8,$C8
  .byt $00,$98,$B8,$D8
  .byt $00,$48,$68,$88
  .byt $00,$58,$78,$98

