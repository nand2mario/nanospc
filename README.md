
# nanoSPC - SNES SPC music player for Tang Nano 20k

<img src="doc/nanospc.jpg" width=400>

This plays classic [Super Nintendo game music](http://snesmusic.org) from MicroSD cards on the Tang Nano 20k FPGA board. The core originally comes from srg320's [FpgaSNES](https://github.com/srg320/FpgaSnes).

* 32Khz stereo playback through HDMI (480p video).
* Up to 99 songs on one microsd card.
* LED audio level display.
* No additional hardware required other than Tang Nano 20K.

## Usage

Grab a nanoSPC [release](http://github.com/nand2mario/nanospc/releases). Use `scripts/spc2img.py` to pack spc files into an sd card image (`python spc2img.py *.spc` will do). Burn the image to a MicroSD card with balenaEtcher. Now insert the card into nano.

Then program the `nanospc.fs` file to the nano 20k. Connect HDMI to your TV or sound-capable monitor to start playing. Press S1 button on nano for next song, S2 for previous song.

If your SPC music is in `.rsn` format. Use `unrar` to extract the separate SPC files before running `spc2img.py` (.rsn is just rar archives).

## More
* The nanoSPC [User interface](doc/screenshot.jpg).
* I converted the main components ([SPC700](src/spc700/) and [DSP](src/dsp.v)) from VHDL to Verilog.
* There's a [verilator simulation](verilator) set-up. `make trace` or `make sim` to generate audio. `make audio` to convert that audio to wave file `snes.wav`. The [embedded](src/data/test_spc.spc.hex) spc data plays a 'ding' sound.
* The Gowin IDE [project file](nanospc.gprj) is included if you'd like to build your own image.
