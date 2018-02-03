NES graphics editor
===================
by Damian Yerrick

A lot of people making "[retraux]" graphics in the style of 1980s video games want a tool that will help make their graphics conform to the limitations of a particular platform.
How better to enforce NES limits than to make graphics directly on the NES?
This program lets you draw pictures with tiles on an NES or anything that can run an NES emulator.
(Sorry, iDevice owners.)
If you have an NES and a [PowerPak], it also lets you preview your graphics on the real thing and adjust your palette to account for the [artifacts] added by the NES's primitive [NTSC video] encoder.

[retraux]: https://allthetropes.org/wiki/Retraux
[PowerPak]: http://www.retrousb.com/product_info.php?products_id=34
[artifacts]: http://blargg.8bitalley.com/parodius/ntsc-presets/
[NTSC video]: https://wiki.nesdev.com/w/index.php/NTSC_video

Using the editor
----------------
The screen is 30 rows of 32 tiles, each 8 by 8 pixels.
A picture can use up to 256 different tiles.
Each 2 by 2 tile (16 by 16 pixel) area can use one of four color sets in the palette.
All color sets have three colors plus a shared background color.

Make a copy of one of the files in the `sample_savs` folder, and put it where your emulator can find it.
This will depend on where your particular emulator stores saved games.
For a PowerPak, .sav files can be kept anywhere on the CF card.
Then run the editor.
First you'll see a title screen; press Start to get to the tile picker.
If the tile picker is full of garbage, erase the whole picture by holding `B` and Left and pressing `Select`, then waiting ten seconds.

### Tile picker

This screen shows all 256 tiles.
Use the Control Pad to select a tile, press `B` to select a color set, and press `A` to start drawing.
Press `Start` to go to the tile editor, or press `Select` to show a menu that leads to the palette editor and tile optimization tools.
From most other screens, you can press `Select` to return to this screen.

NOTE: If you started with a blank .sav file, or you just erased the picture, you won't see much here until you play around in the tile editor.

### Drawing with tiles

Use the Control Pad to move the cursor.
Press `A` Button to place the selected tile, or hold `A` and move to place
the selected tile multiple times.
Press `B` to pick up the tile and color set under the cursor, and press `B` again to cycle among the four color sets with this tile.
Press `Select` to go back to the tile picker, or hold `Select` and use the Control Pad to quickly select a different tile.

A display in the corner of the screen shows where the cursor is and what tile is selected.
It slides out of the way when you try to draw in the area that it covers.

When you draw, nearby tiles may change colors.
This is because color sets are assigned on a grid twice as large as the tile grid.

Press `Start` to open the map tools menu:

* `Zoom In` opens the tile editor with tiles arranged as they are in the map.
* `Show Color Set Map` shows which color sets are assigned to which areas.
* `Copy Area` lets you copy and paste rectangular blocks of tiles. Move to one corner and press `A`. Move to the other and press `A`. Move the block and press `A` to paste. (Attributes are not copied.) Or press `B` to back up a step, `Start` to return to map tools, or `Select` to return to drawing.
*`Screen Tint` allows changing the "tint" or "emphasis" bits that cause the PPU to apply the equivalent of a [color gel] that darkens certain colors. Some TVs have trouble with tint colors other than `red`, `green`, and `blue`; if your TV loses sync while cycling through the tints, keep pressing `A` until the tint comes back to `none`. Don't try to use tint on an NES with a 2C03 or 2C05 PPU (Famicom Titler, PlayChoice, or early RGB mods) because tint on those systems is so broken that it renders the menus unreadable.

[color gel]: https://en.wikipedia.org/wiki/Color_gel

### Palette editor

Choosing `Edit Color Palette` from the tile picker's menu shows
a form for editing the backdrop color and the three colors that
make up each of the four color sets.
Select a color with the Control Pad, then press `A` to change it.
Left and Right change the hue, while Up and Down change the brightness.
To move to a different color, press `A` again, or release `A` if you
held it while changing the color.
To return to the tile picker, press `Select`.

If you change the background color, the menu color will change
along with it to stay visible.
If you change the colors of a color set used in the picture, everything using that color set changes along with it.
Drawing, changing colors, and drawing more will not allow you to break the NES's color limit.

### Tile editor

The tile editor shows a zoomed view of 30 tiles from the tile sheet or a 6 by 5 tile area of the picture.
The thin lines on the border show the edges of a single tile.
A status bar at the bottom shows where on the 128x128 pixel tile sheet (or the 256x240 pixel picture) the cursor is located, the number of the tile corresponding to this location, which color you are using, how many times this tile is used in the picture, and how many tiles are unused.

If a tile is used multiple times in a picture, your changes will affect all uses of the tile.
If you want to change only one use of a tile in the map, then zoom in on the map and press Start, and any tile you draw on that is used more than once will be copied to a new tile that replaces an unused tile. (The `U` for "unique" next to the count of unused tiles denotes this mode.)

Move the pencil cursor with the Control Pad and press `A` to draw.
Press `B` to pick up the color under the pencil, and `B` to cycle among the four colors.
To scroll the view, move the cursor near the edge.
To return to the tile picker, press `Select`.

### Tile optimization

If you have imported a .sav file from a PPU dump, it will probably have a lot of tiles that the scene doesn't use but other scenes use.
To make room for new tiles that you create, you can remove unused information.
The tile picker's menu gives you several ways to do this:

* `Blank Unused Tiles` replaces any tile that is not used in a screen with a solid pattern.
* `Move Used Tiles to Top` is like <samp>Blank Unused Tiles</samp>, except all the used tiles are moved to the top of the tile sheet.</li>
* `Remove Duplicate Tiles` finds tiles in the tile sheet that are identical, replaces each tile in the screen with the first tile, and then blanks the duplicates.

Importing images
----------------
The editor stores your picture in a battery-backed 64 Kbit SRAM chip, which emulators represent as a 8192 byte .sav file.
A blank .sav file and several sample pictures are included in the `sample_savs` folder.
Once you have a .sav file, put it where your emulator or PowerPak can find it, and then start the program.
The PowerPak is ideal for this because its menu lets you choose one of several .sav files before starting the editor.

Or instead of starting from a blank .sav using the tile editor, you may want to convert existing images.
A conversion tool called written in Python called `savtool.py` is included.
To run it, you'll need to install Python3 and Pillow on your computer.
On Ubuntu or another Debian-based system, installing the `python3-pil` package will get all prerequisites:

    sudo apt-get install python3-pil

If you are running Windows, you'll probably need pre-built executable versions of Python and Pillow. Get Python from python.org; install Pillow through pip3.

For information on the more obscure operations possible with `savtool.py`, run these commands from within a command prompt:

    savtool.py --help
    savtool.py --more-help

### From PPU dump

FCEUX for Windows can export a 16 KiB dump of the PPU memory, which includes two pattern tables (or tile sheets), four screens, and a palette.
To create this dump, from the Debug menu choose Hex Editor, then from the File menu choose Dump to File > PPU Memory.
`savtool.py` can convert this PPU dump to a .sav file for the editor.
Make sure to name the PPU dump with a .ppu suffix.

The PPU's displayable area is two screens tall and two screens wide, though the NES itself has only enough memory for two distinct screens:
two across by one down or one across by two down, depending on how the cartridge board is configured.
Games that scroll over a large map, such as _Contra_ and _Mega Man 2_, continuously load newly visible portions into a ["seam" area] placed just offscreen.
If the scene is not centered, you can change the scrolling.
Scrolling is specified in 16-pixel units, the same size as the area assigned to a color set, and each screen is 16 units wide and 15 units high.

The PPU actually has two tile sheets of 256 tiles each available to it, at addresses $0000 and $1000.
Usually, one is used for the background and the other for sprites.
Most later games use $0000 for backgrounds and $1000 for sprites, but some early games such as _Super Mario Bros._ use the opposite convention.
(The editor itself puts user interface graphics in $0000 and your tile sheet in $1000.)
If the image appears scrambled after conversion, you can use the `--chr` option to tell the converter to pull tiles from $1000 instead.

`savtool.py` does not support raster effects, which are commonly used in NES games to scroll the playfield while holding the status bar still.
For example, a status bar in games like <i>Super Mario Bros.</i> will usually be in the wrong place after conversion.

Example:

    ./savtool.py smb1_title.ppu smb1_title.sav --chr $1000 -x 16 -y 0

["seam" area]: http://wiki.nesdev.com/w/index.php/File:SMB1_scrolling_seam.gif

### From BMP, GIF, or PNG

`savtool` converts a picture or tile sheet in a bitmapped format (.bmp, .gif, or .png) to a .sav file.
If the file is 128x128 pixels or smaller, it loads every tile into the tile sheet and creates a blank nametable.

A larger picture is treated as a full-screen image, and duplicate tiles will be removed.
When converting a bitmap, you can specify an NES palette with `--palette` from either another .sav file or a 32-character hex palette, and `savtool` will do its best to make the colors match given the 16x16 pixel color area restriction.
If you don't provide a `--palette`, the converted .sav uses color set 0 for the whole picture, and you can change the colors of screen areas within the editor by picking up tiles (`B`), changing their color (`B` repeatedly), and putting them back down (`A`).

`savtool` can also render a .sav file to a PNG using Bisqwit's NES palette.
Or if you use `--write-chr` and give a color set number, it extracts the .sav's tile sheet in that color set.
Finally, use `--print-palette` to print the 32-character hex palette stored in a .sav, or `--show` to just view the picture without saving it.

Examples:

    ./savtool.py mysketch.png mysketch.sav
    ./savtool.py mysketch.png mysketch.sav --palette oldsketch.sav
    ./savtool.py mysketch.sav mysketch.png
    ./savtool.py mysketch.sav mysketch.png --write-chr 0
    ./savtool.py mysketch.sav --print-palette
    ./savtool.py mysketch.sav --show

### From CHR

If you have a 4096 byte .chr file and 1024 byte .nam file that you've been using with some other NES graphics editor such as [NESST], you can import those with `savtool`. If no `--palette` is specified, either as a hex code or as another .sav file, it uses the same palette that the editor uses for a blank picture.

    ./savtool.py kitty.chr --palette 0f0010300f0717270f1a2a370f001030 kitty.sav
    ./savtool.py kitty.nam --chr kitty.chr kitty.sav

Converting back to .chr and .nam is also supported:

    ./savtool.py kitty.sav kitty.chr
    ./savtool.py kitty.sav kitty.nam

If you cannot run `savtool.py`, you can convert .chr to .sav by appending 4096 bytes of junk data.

* On Linux and other UNIX-like systems:  
  `cat kitty.chr sample_savs/chr2sav.bin &gt; kitty.sav`
* On Windows:  
  `copy /b kitty.chr+sample_savs/chr2sav.bin kitty.sav`

For more information on the .sav format used by the editor, read "SAV format.txt" in the docs folder.

[NESST]: http://shiru.untergrund.net/software.shtml

Legal
----
The following applies to this manual and the associated programs:

© 2012 Damian Yerrick

Copying and distribution of this file, with or without
modification, are permitted in any medium without royalty provided
the copyright notice and this notice are preserved in all source
code copies.  This file is offered as-is, without any warranty.
