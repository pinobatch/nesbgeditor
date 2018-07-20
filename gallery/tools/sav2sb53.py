#!/usr/bin/env python3
import sys
import os

# Find common tools
commontoolspath = os.path.normpath(os.path.join(
    os.path.dirname(sys.argv[0]), "..", "..", "common", "tools"
))
sys.path.append(commontoolspath)
import pb53

def main(argv=None):
    argv = argv or sys.argv

    if len(argv) > 1 and argv[1] == '--help':
        print("usage: sav2sb53.py infile.sav outfile.pb53\n"
              "Packs a savtool background: tile count, PB53 tile data, PB53 nametable,\n"
              "16-entry palette")
        return
    if len(argv) != 3:
        print("sav2sb53.py: wrong number of arguments; try sav2sb53.py --help",
              file=sys.stderr)
        sys.exit(1)
    _, infilename, outfilename = argv
    with open(infilename, 'rb') as infp:
        data = infp.read(8192)
    namdata = data[6144:7168]
    num_tiles = 1 + max(namdata[:960])
    chrdata = data[0:16 * num_tiles]
    paldata = data[-256:-240]

    outdata = [
        bytearray([num_tiles & 0xFF]),
        pb53.pb53(chrdata)[0], pb53.pb53(namdata)[0],
        paldata
    ]
    with open(outfilename, 'wb') as outfp:
        outfp.writelines(outdata)

if __name__=='__main__':
    main()
