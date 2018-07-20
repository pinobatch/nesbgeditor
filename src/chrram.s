;
; CHR RAM loader for NES graphics editor
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;
.include "nes.inc"
.include "global.inc"
.include "mmc1.inc"

.segment "BANK00"
menuchr_pb53:
  .incbin "obj/nes/menuchr.pb53"
bgedit_pb53:
  .incbin "obj/nes/bgedit.pb53"
tileedit_pb53:
  .incbin "obj/nes/tileedit.pb53"

unpb53_table:
  .addr menuchr_pb53, $0000
  .addr bgedit_pb53, $0600
  .addr tileedit_pb53, $0600

;;
; Loads 8192 bytes of uncompressed data into CHR RAM.
.proc load_chr_ram

  lda #0
  sta PPUMASK
  jsr unpb53_block

  ldy #$10
  sty PPUADDR  ; set starting location in CHR RAM to $0000
  ldy #$00
  sty PPUADDR
  lda #>SRAM_BGCHR
  ldx #>(SRAM_BGCHR_END-SRAM_BGCHR)
  ; fall through
.endproc

.proc load_x_rows_from_ay
srclo = 0
srchi = 1

  sta srchi
  sty srclo
  ldy #0
loop:
  lda (srclo),y
  sta PPUDATA
  iny
  bne loop
  ; after every 256th byte we end up here
  inc srchi  ; move on to the next set of 256 bytes of CHR
  dex
  bne loop
  rts
.endproc

.proc unpb53_block
ciBlocksLeft = 2
  asl a
  asl a
  tay
  lda unpb53_table+0,y
  sta ciSrc+0
  lda unpb53_table+1,y
  sta ciSrc+1
  lda unpb53_table+3,y
  sta PPUADDR
  lda unpb53_table+2,y
  sta PPUADDR
  ldy #1
  lda (ciSrc),y
  lsr a
  lsr a
  lsr a
  sta ciBlocksLeft  ; doing 8 tiles (128 bytes) at a time
  lda #2
  clc
  adc ciSrc
  sta ciSrc
  bcc rowloop
  inc ciSrc+1

rowloop:
  lda #$80
  sta ciBufEnd
  asl a
  sta ciBufStart
  jsr unpb53_some
  ldx #0
byteloop:
  lda PB53_outbuf,x
  sta PPUDATA
  inx
  bpl byteloop
  dec ciBlocksLeft
  bne rowloop
  rts
.endproc


