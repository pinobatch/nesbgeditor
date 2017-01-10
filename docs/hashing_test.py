#!/usr/bin/env python
from __future__ import with_statement
import hashlib

# crc32 does not give the same collisions as crc16, but it should
# hopefully give roughly the same number of collisions.
# I wrote this program while offline, and the search function in
# file:///usr/share/doc/python2.7/html/index.html
# is causing Firefox 14 to throw two JavaScript errors:
# ReferenceError: _ is not defined in doctools.js
# TypeError: $.getQueryParameters is not a function in searchtools.js
from zlib import crc32

def prtable(a):
    a = [a[i:i + 16] for i in range(0, len(a), 16)]
    print "\n".join(" ".join("%02x" % c for c in row) for row in a)

with open('../editor.sav', 'rb') as infp:
    tileset = infp.read(4096)
tileset = [tileset[i:i + 16] for i in range(0, len(tileset), 16)]

# Stress test: Set tiles $BC-$FF to equal $43 to test to what extent
# a bunch of existing duplicates of one tile cause a return to O(n^2)
# behavior.
tileset[0xBC:0x100] = [tileset[0x43]] * (0x100 - 0xBC)

# Comparing tiles for equality (evaluating tileset[i] == tileset[j])
# for all 32,000-odd pairs of tiles is slower than separating them
# into equivalence classes by their digest value and comparing only
# the tiles in each equivalence classes so that even though it's
# still theoretically O(n^2), we can do about a hundred times fewer
# comparisons.  So start by computing a digest value with CRC32.

A = [crc32(tile) & 0x00FF for tile in tileset]
# at this point, A is tile->hash
print "tile to hash:"
prtable(A)

# Creation of linked lists of tiles with the same hash
B = [255]*256
for tileno in range(256):
    hashval = A[tileno]
    prev_tile = B[hashval]  # Find most recnet tile with this hash
    A[tileno] = prev_tile   # Create a link to previous tile
    B[hashval] = tileno     # Mark as most recent for this hash

# Now, B is the most recently seen tile number with a given hash
# (or $FF for none seen).
# A becomes the immediately previous tile number with the same hash
# as a given tile (or $FF for the first)

print "hash to last:"
prtable(B)
print "tile to previous (terminated by $ff):"
prtable(A)

# Creation of tile remapping:
# For each tile, compare it to all previous unique tiles, and on
# finding a match, map this tile to the previous tile.
B = range(256)
num_comparisons = 0
for tileno in range(256):
    led_here = tileno
    while True:
        prev_tile = A[led_here]
        if prev_tile >= 255:
            break
        num_comparisons += 1
        print "%3d. comparing tiles %02x and %02x" % (num_comparisons, prev_tile, tileno)
    
        # If prev_tile is already remapped to something, then it
        # isn't a unique tile, so skip it.  Otherwise, if the tiles
        # are identical, remap.
        if prev_tile == B[prev_tile]:
            if tileset[prev_tile] == tileset[tileno]:
                B[tileno] = prev_tile
                break
        else:

            # Future checks of led_here can skip prev_tile.  If I
            # omit this step, tilesets with large amounts of dupes
            # become O(n^2).
            A[led_here] = A[prev_tile]
        led_here = prev_tile

# By here, A has duplicates removed from the chain, and B is a map
# from tile numbers to the lowest number of an identical tile.
# Yes, this discovers the $43=$BB duplicate in Super Mario Bros.
# At this point you can reassign nametables using this mapping.

print "modified links:"
prtable(A)
print "tile number to first identical tile number:"
prtable(B)

# Next steps:
# 
# 1. Test with artificial duplicates in tile data
# 2. 
# 3. Execute tile remapping
# 4. Tile editor
