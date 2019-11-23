;
; Title screen and menu support for NES graphics editor
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;
.include "nes.inc"
.include "global.inc"

.export puts_multiline
.import read_pads
.importzp das_timer

LF = $0A

.proc clear_puts_multiline
  pha
  tya
  pha
  lda #VBLANK_NMI
  sta PPUCTRL
  asl a
  sta PPUMASK
  jsr load_colorset_0
  lda #' '
  ldx #$20
  ldy #$00
  jsr ppu_clear_nt
  pla
  tay
  pla
.endproc
;;
; @param A high byte of string
; @param Y low byte of string
.proc puts_multiline
srcLo = $00
srcHi = $01
dstLo = $02
dstHi = $03

  sta srcHi
  ldx #0
  stx srcLo  ; keep the low byte in Y

newline:
  lda dstHi
  sta PPUADDR
  lda dstLo
  sta PPUADDR
  clc
  adc #32
  sta dstLo
  bcc :+
  inc dstHi
:
  ldx #0
charloop:
  lda (srcLo),y
  beq done
  iny
  bne :+
  inc srcHi
:
  cmp #LF
  beq newline
  sta PPUDATA
  jmp charloop
done:
  rts
.endproc

;;
; Loads a foreground color contrasting with the current background
; color into colorset 0 and leaves VRAM address at $3F04.
; Returns the contrasting color.
.proc load_colorset_0
  lda #$3F
  sta PPUADDR
  lda #$00
  sta PPUADDR

  ; get lightness in upper nibble
  lda $7F00
  and #$3F
  sta PPUDATA
  eor #$0F
  clc
  adc #$01  ; 00->10, 01-0C->0F-04

  cmp #$20  ; if C is set, we need to use black
  lda #$20  ; white
  bcc not_black
  lda #$0F
not_black:
  sta PPUDATA
  sta PPUDATA
  sta PPUDATA
  rts
.endproc

; Title screen ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.proc title_screen
  jsr load_colorset_0
  jsr load_chr_ram
  lda #$20
  sta $03
  lda #$E2
  sta $02
  lda #>title_msg
  ldy #<title_msg
  jsr clear_puts_multiline

loop:
  lda nmis
:
  cmp nmis
  beq :-
  ldx #0
  ldy #0
  lda #VBLANK_NMI
  clc
  jsr ppu_screen_on

  ; Start: hide the title screen and go onto the next phase
  jsr read_pads
  lda new_keys
  and #KEY_START
  beq not_start

  ldx #FIRST_SCREEN
  rts
not_start:

  ; Left+B+Select: Reformat SRAM
  lda cur_keys
  cmp #KEY_LEFT|KEY_B|KEY_SELECT
  bne loop
  lda new_keys
  cmp #KEY_SELECT
  bne loop

  ; Confirm reformat SRAM
  lda #$20
  sta $03
  lda #$E2
  sta $02
  lda #>reformat_confirm_msg
  ldy #<reformat_confirm_msg
  jsr clear_puts_multiline
  
seconds_left = das_timer+1
frames_left = das_timer
  lda #10
  sta seconds_left
erase_count_second:
  ldx #60
  lda tvSystem
  beq :+
  ldx #50
:
  stx frames_left
erase_count_frame:
  lda nmis
:
  cmp nmis
  beq :-
  ldx #0
  ldy #0
  lda #VBLANK_NMI
  clc
  jsr ppu_screen_on
  jsr read_pads
  lda new_keys
  bne canceled_cd
  dec frames_left
  bne erase_count_frame
  dec seconds_left
  bne erase_count_second
  lda #0
  sta PPUMASK
  jsr erase_picture
canceled_cd:
  jmp title_screen
.endproc

.segment "RODATA"
title_msg:
  .byt "GRAPHICS EDITOR FOR NES",LF
  .byt "VERSION 0.06",LF
  .byt "COPR.2012,2019 DAMIAN YERRICK",LF,LF
  .byt "PRESS START BUTTON TO DRAW!",LF,LF,LF,LF,LF
  .byt "____________________________",LF,LF
  .byt "NOTICE:",LF
  .byt "THIS GAME PAK SAVES YOUR",LF
  .byt "PICTURE WITH A BATTERY",LF
  .byt "CIRCUIT. TO AVOID SMUDGES,",LF
  .byt "ALWAYS HOLD THE RESET BUTTON",LF
  .byt "WHILE TURNING OFF THE POWER.",LF,LF
  .byt "TO ERASE THE STORED PICTURE,",LF
  .byt "HOLD LEFT+B AND PRESS SELECT",0

reformat_confirm_msg:
  .byt "THE SAVED PICTURE IS",LF,LF
  .byt "ABOUT TO BE ERASED.",LF,LF
  .byt "IF YOU AREN'T SURE",LF,LF
  .byt "YOU WANT TO DO THIS,",LF,LF
  .byt "PRESS THE RESET BUTTON NOW.",0

.segment "CODE"

; Drawing help ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

.proc comingsoon1_screen
  lda #>comingsoon1_msg
  ldy #<comingsoon1_msg
  jmp static_screen
.endproc

.proc drawing_help_screen
  lda #>drawing_help_msg
  ldy #<drawing_help_msg
.endproc
.proc static_screen
  ldx #$20
  stx $03
  ldx #$62
  stx $02
.endproc
.proc static_screen_23
  jsr clear_puts_multiline
.endproc
.proc press_any_key
loop:
  lda nmis
:
  cmp nmis
  beq :-
  ldx #0
  ldy #0
  lda #VBLANK_NMI
  clc
  jsr ppu_screen_on

  ; Start: hide the title screen and go onto the next phase
  jsr read_pads
  lda new_keys
  beq loop
  ldx #SCREEN_CHRPICKER
  rts
.endproc

.segment "RODATA"
drawing_help_msg:
  .incbin "src/drawing_help.txt"
  .byt 0
comingsoon1_msg:
  .incbin "src/comingsoon1.txt"
  .byt 0
.segment "CODE"

; Nametable tools ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

TINT_DST_ADDR = $2131 + NUM_NTMENU_ITEMS * 32
.proc nttools_menu
  ldx #$20
  stx $03
  ldx #$E4
  stx $02
  lda #>nttools_menu_text
  ldy #<nttools_menu_text
  jsr clear_puts_multiline

  ; load palette
  lda selected_color
  asl a
  asl a
  tax
  lda #$3F
  sta PPUADDR
  lda #$05
  sta PPUADDR
  .repeat 3, I
  lda SRAM_PALETTE+I+1,x
  sta PPUDATA
  .endrepeat

  ; hide sprite 0
  ldx #$FF
  stx OAM+0
  ; sprite 1 has the cursor
  ldx #7
  stx OAM+5
  ldx #0
  stx select_state
  stx OAM+6
  ldx #16
  stx OAM+7
  ldx #8
  jsr ppu_clear_oam

runloop:
  lda select_state
  asl a
  asl a
  asl a
  adc #71
  sta OAM+4

  lda nmis
:
  cmp nmis
  beq :-
  
  ; draw tint name
  lda #>TINT_DST_ADDR
  sta PPUADDR
  lda #<TINT_DST_ADDR
  sta PPUADDR
  lda selected_tint
  lsr a
  adc selected_tint
  ror a
  ror a
  ror a
  tax
  ldy #6
tintnameloop:
  lda tint_names,x
  sta PPUDATA
  inx
  dey
  bne tintnameloop
  
  ldx #0
  ldy #0
  stx OAMADDR
  lda #>OAM
  sta OAM_DMA
  lda #VBLANK_NMI|BG_0000|OBJ_0000
  sec
  jsr ppu_screen_on
  jsr read_pads

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
  cmp #NUM_NTMENU_ITEMS  ; last is always screen tint
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
  ldx #SCREEN_NTEDIT
  rts

pressedOK:
  lda select_state
  cmp #NUM_NTMENU_ITEMS
  beq pressedTint
  asl a
  adc #SCREEN_NTMENUBASE
  tax
  lda #0
  sta PPUMASK
  rts

pressedTint:
  lda selected_tint
  adc #$20
  and #$E0
  sta selected_tint
  jmp runloop
.endproc

.segment "RODATA"
nttools_menu_text:
  .byt "MAP TOOLS",LF,LF
  .byt "ZOOM IN",LF
  .byt "SHOW COLOR SET MAP",LF
  .byt "COPY AREA",LF
.if 0
  ; what I plan to implement
  .byt "COPY AREA AND COLORS",LF
.endif
  .byt "SCREEN TINT:",0

tint_names:
  .byt "NONE  "
  .byt "RED   "
  .byt "GREEN "
  .byt "BROWN "
  .byt "BLUE  "
  .byt "PURPLE"
  .byt "CYAN  "
  .byt "GRAY  "

.segment "CODE"
