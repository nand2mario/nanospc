#!/usr/bin/python3

# package spc files into an sd card image

import sys
import os
import argparse

parser = argparse.ArgumentParser(description='SPC file packager for spcplayer')
parser.add_argument('-o', '--output', help='output file', default='sd_spc.img', type=argparse.FileType('wb'))
parser.add_argument('file', help='spc files to package', type=argparse.FileType('rb'), nargs='+')
args = parser.parse_args()
cnt = len(args.file)

# write header
out=args.output
hdr=bytearray([0]*512)
hdr[0:4]=b'SPC '
hdr[4]=cnt % 256
hdr[5]=cnt // 256
out.write(hdr)

# write file content
for f in args.file:
    bs = f.read()
    if len(bs) < 66048:
        print('Warning expecting at least 66048 bytes for {}, actually it is only {}', f.name, len(bs))
        bs += [0] * (66048 - len(bs))
    out.write(bs[0:66048])
    
out.close()
print('done')
