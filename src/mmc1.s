;
; MMC1 driver for NES graphics editor
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;

.include "src/mmc1.h"
.import nmi, reset, irq
MULTIPLE_PRG_BANKS = 0

; Each bank has 16384 bytes: 16368 for you to use as you wish and
; 16 for a piece of code that puts the mapper in a predictable state.
; This code needs to be repeated in all the banks because we don't
; necessarily know which bank is switched in at power-on or reset.
;
; Writing a value with bit 7 true (that is, $80-$FF) to any MMC1
; port causes the PRG bank mode to be set to fixed $C000 and
; switchable $8000, which causes 'reset' to show up in $C000-$FFFF.
; And on most discrete logic mappers (AOROM 7, BNROM 34, GNROM 66),
; and Crazy Climber UNROM (180), writing a value with bits 5-0 true
; (that is, $3F, $7F, $BF, $FF) switches in the last PRG bank, but
; it has to be written to a ROM address that has the same value.
.macro resetstub_in segname
.segment segname
.scope
resetstub_entry:
  sei
  ldx #$FF
  txs
  stx $FFF2  ; Writing $80-$FF anywhere in $8000-$FFFF resets MMC1
  jmp reset
  .addr nmi, resetstub_entry, irq
.endscope
.endmacro

.segment "CODE"
.import nmi, reset, irq
resetstub_in "STUB00"
resetstub_in "STUB15"

.segment "INESHDR"
  .byt "NES",$1A  ; magic signature
  .byt 2          ; size of PRG ROM in 16384 byte units
  .byt 0          ; size of CHR ROM in 8192 byte units
  .byt $12        ; lower mapper nibble, enable battery RAM
  .byt $00        ; upper mapper nibble
  
.segment "CODE"
; To write to one of the four registers on MMC1, write bits 0 through
; 3 to D0 of any mapper port address ($8000-$FFFF), then write bit 4
; to D0 at the correct address (e.g. $E000-$FFFF).
; The typical sequence is sta lsr sta lsr sta lsr sta lsr sta.

.if MULTIPLE_PRG_BANKS
.segment "ZEROPAGE"
lastPRGBank: .res 1
.segment "CODE"
.proc setPRGBank
  sta lastPRGBank
  .repeat 4
    sta $E000
    lsr a
  .endrepeat
  sta $E000
  rts
.endproc
.else
lastPRGBank = $FF
.proc setPRGBank
  rts
.endproc
.endif

.segment "ZEROPAGE"
lastBankMode: .res 1
.segment "CODE"
.proc setMMC1BankMode
  sta lastBankMode
  .repeat 4
    sta $8000
    lsr a
  .endrepeat
  sta $8000
  rts
.endproc

