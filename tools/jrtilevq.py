#!/usr/bin/env python3
# Copyright (c) 2016 Johnathan Roatch
# 
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
# 
# The above copyright notice and this permission notice shall be included
# in all copies or substantial portions of the Software.
# 
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
# IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
# CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
# TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
# SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Original thread
# https://forums.nesdev.com/viewtopic.php?f=21&t=14807
#
# Changes 2020-09-22 by Damian Yerrick
# - Help for argparse
#
# Changes 2018-04-07 by Damian Yerrick
# - Parse arguments with argparse
#
# Changes 2018-02-07 by Damian Yerrick
# - Use collections.Counter to make the histogram
# - If reduce_tiles() input is a list of tiles, so will be its output
#
# Changes 2018-02-06 by Damian Yerrick
# - Rename biased_random_byte() to biased_getrandbits(); allow
#   changing word width like random.getrandbits()
# - Structure as an importable module
# - Vary output tile count
# - Take a filelike for logging the tile count
# - Take input and output filenames on the command line

import os
import random
import functools
import sys
import collections
import argparse

@functools.lru_cache(maxsize=None, typed=False)
def number_of_changed_pixels(tile1, tile2):
    plane1 = bytes(a^b for a, b in zip(tile1[:8], tile2[:8]))
    plane2 = bytes(a^b for a, b in zip(tile1[8:], tile2[8:]))
    plane3 = bytes(a|b for a, b in zip(plane1, plane2))
    return sum(bin(i).count("1") for i in plane3)

# Was Part of an experement to remove dots. Made image worse.
def rotate_tile_180(tile):
    upsidedown_tile = bytes(reversed(tile[:8])) + bytes(reversed(tile[8:]))
    return bytes(sum(((d>>(7-i))&0b1)<<i for i in range(8)) for d in upsidedown_tile)

def biased_getrandbits(p, k=8):
    """Return an integer where bits are true with probability p.

p -- probability of each bit being set, 0 < p < 1
k -- number of bits in byte

If p == 0.5, this behaves the same as random.getrandbits().
"""
    b = 0
    for i in range(k):
        b = b | (1 << i if (random.random() < p) else 0)
    return b

def merge_tiles(tile1, tile2, p):
    mask = bytes(biased_getrandbits(p) for i in range(8)) * 2
    return bytes(((a&(m^0xff))|(b&m)) for a, b, m in zip(tile1, tile2, mask))

def reduce_tiles(chr_data, maxsize=256, logfp=None):
    list_form = isinstance(chr_data, list)
    if list_form:
        nametable = list(chr_data)
    else:
        nametable = [chr_data[i:i + 16] for i in range(0, len(chr_data), 16)]
    total_number_of_tiles = len(nametable)
    while total_number_of_tiles > maxsize:
        tile_count = collections.Counter(nametable)
        total_number_of_tiles = len(tile_count)
        if logfp:
            print(total_number_of_tiles, file=logfp)
        if total_number_of_tiles <= maxsize:
            break

        scan_list = list(tile_count.items())
        random.shuffle(scan_list)
        scan_list.sort(key=lambda i: i[1])

        d_threshold = 1
        d_max = 64*32*30
        rescan_list = False
        while not rescan_list:
            for start_i, tuple_a in enumerate(scan_list):
                for tuple_b in scan_list[start_i+1:]:
                    tile_a, count_a = tuple_a
                    tile_b, count_b = tuple_b
                    d = number_of_changed_pixels(tile_a, tile_b) * (count_a + count_b)
                    d_max = min(d_max, d)
                    if 0 < d <= d_threshold:
                        merged_tile = merge_tiles(tile_a, tile_b, count_b/(count_a+count_b))
                        for x in range(len(nametable)):
                            if nametable[x] == tile_a or nametable[x] == tile_b:
                                nametable[x] = merged_tile
                        rescan_list = True
                        break
                if rescan_list:
                    break
            if not rescan_list:
                d_threshold = d_max

    if list_form:
        return nametable
    else:
        return b''.join(nametable)

def parse_argv(argv):
    prolog="""
Merges similar 8x8-pixel tiles in a 2-bit image in NES CHR format.
"""
    epilog="""
The tool tries to preserve silhouette.  It treats a difference
between a pixel with color 0 and a pixel with color 1-3 as more
noticeable than a difference between two pixels with colors 1-3.
For best results, the input files should not already be reduced to
unique tiles with a tilemap.  If a tile appears multiple times in the
image, it should appear multiple tiles in INCHR.  This helps the tool
weigh common vs. rare tiles for merging.
"""
    parser = argparse.ArgumentParser(description=prolog, epilog=epilog)
    parser.add_argument("INCHR",
                        help="filename of input in NES CHR format")
    parser.add_argument("OUTCHR",
                        help="filename of output in NES CHR format")
    parser.add_argument("-n", "--max-tiles", type=int, default=256,
                        help="maximum distinct tiles to produce (default 256)")
    return parser.parse_args(argv[1:])

def main(argv=None):
    args = parse_argv(argv or sys.argv)
    infilename = args.INCHR
    outfilename = args.OUTCHR
    verbose = True
    maxsize = args.max_tiles
    
    with open(infilename, 'rb') as infp:
        chr_data = infp.read()
    result_chr = reduce_tiles(
        chr_data, maxsize=maxsize, logfp=sys.stderr if verbose else None
    )
    with open(outfilename, 'wb') as outfp:
        outfp.write(result_chr)

if __name__=='__main__':
    main()
