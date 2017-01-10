; Declarations of memory areas and functions
; for NES graphics editor
; Copyright 2012 Damian Yerrick
;
; Copying and distribution of this file, with or without
; modification, are permitted in any medium without royalty provided
; the copyright notice and this notice are preserved in all source
; code copies.  This file is offered as-is, without any warranty.
;

.ifndef RAM_H
.define RAM_H

.macro DEBUG_CHECKPOINT
  sta $FF
.endmacro

OAM = $0200
SRAM_BGCHR = $6000
SRAM_BGCHR_END = $7000
SRAM_OBJCHR = $7000
SRAM_OBJCHR_END = $7800
SRAM_NT = $7800
SRAM_NT_END = $7C00
SRAM_PALETTE = $7F00

; play_game::screens

; main.s
SCREEN_CHRPICKER = 0
SCREEN_NTEDIT = 2
SCREEN_TILEEDIT = 4
SCREEN_NTTOOLS = 6

SCREEN_CHRMENUBASE = 8
NUM_CHRMENU_ITEMS = 6
SCREEN_CHRMENUEND = SCREEN_CHRMENUBASE + 2 * NUM_CHRMENU_ITEMS

SCREEN_DRAWINGHELP = SCREEN_CHRMENUBASE + 0
SCREEN_PALEDIT = SCREEN_CHRMENUBASE + 2
SCREEN_BLANKUNUSED = SCREEN_CHRMENUBASE + 4
SCREEN_RMDUPES = SCREEN_CHRMENUBASE + 6
SCREEN_DEFRAG = SCREEN_CHRMENUBASE + 8
SCREEN_SOON1 = SCREEN_CHRMENUEND - 2

SCREEN_NTMENUBASE = SCREEN_CHRMENUEND
NUM_NTMENU_ITEMS = 3
SCREEN_TILEEDITMAPMODE = SCREEN_NTMENUBASE + 0
SCREEN_ATTRVIEWER = SCREEN_NTMENUBASE + 2
SCREEN_COPIPE = SCREEN_NTMENUBASE + 4
SCREEN_NTMENUEND = SCREEN_NTMENUBASE + 2 * NUM_NTMENU_ITEMS

; when testing a new screen, set appropriately
; but in release builds, always set to SCREEN_CHRPICKER
FIRST_SCREEN = SCREEN_CHRPICKER

.globalzp oam_used, nmis, tvSystem
.global draw_box

; paldetect.s
.global getTVSystem

; ppuclear.s
.global ppu_clear_nt, ppu_clear_oam, ppu_screen_on

; mmc1.s
.global setPRGBank, setMMC1BankMode

; pads.s
.global read_pads, autorepeat
.globalzp new_keys, cur_keys, das_keys

; chrram.s
.global load_chr_ram, load_x_rows_from_ay, unpb53_block

; menus.s
.global title_screen, drawing_help_screen, comingsoon1_screen
.global nttools_menu
.global clear_puts_multiline, puts_multiline, load_colorset_0
.global press_any_key

; chrpicker.s
.global chrpicker, draw_arrow, move_selected_tile_by_dpad, puthex
.global chrpicker_s0wait
.globalzp selected_tile, selected_color, dirty

; ntedit.s
.global ntedit, attribute_viewer
.globalzp nt_x, nt_y, selected_tint, status_y, dirty
.globalzp select_state  ; to distinguish Select+direction from Select
.globalzp eyedropper_state  ; to distinguish move+B from B+B
; shared with copipe.s
.global move_nt_xy_by_dpad, move_status_y, draw_status_sprites
.global load_bg_palette, copy_bg_from_sram, oam_bcd_stuff

; chrutils.s
.global calculate_bg_tile_usage
.global count_unused_tiles, find_next_unused_tile
.global blank_unused_tiles, remap_all_dupes, defrag_tiles
.global erase_picture
.global tilelist_A, tilelist_B
histo = tilelist_A

; paledit.s
.global paledit

; unpkb.s
.global unpb53_some, PB53_outbuf
.globalzp ciSrc, ciDst, ciBufStart, ciBufEnd

; tileedit.s
.globalzp pixel_x, pixel_y, redraw_y, tileedit_map_mode
.global tileedit

; bcd.s
.global bcd8bit

; copipe.s
.global nt_copipe

.endif
