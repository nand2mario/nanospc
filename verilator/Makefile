
N=nanospc_top
D=../src
SRCS=$D/dsp.v $D/nanospc_top.v $D/smp.v $D/test_aram.v $D/spc_parser.v $D/spc700/_spc700_package.v $D/spc700/addrgen.v $D/spc700/addsub.v $D/spc700/alu.v $D/spc700/bcdadj.v $D/spc700/mcode.v $D/spc700/muldiv.v $D/spc700/spc700.v 
INCLUDES=-I$D -I$D/spc700
CFLAGS=
LIBS=

.PHONY: build sim verilate clean gtkwave audio
	
build: ./obj_dir/V$N

verilate: ./obj_dir/V$N.cpp

./obj_dir/V$N.cpp: sim_main.cpp $(SRCS)
	@echo
	@echo "### VERILATE ####"
	mkdir -p obj_dir
	verilator --top-module $N --trace -cc -O3 --exe -CFLAGS "$(CFLAGS)" -LDFLAGS "$(LIBS)" $(INCLUDES) $(SRCS) sim_main.cpp

./obj_dir/V$N: verilate
	@echo
	@echo "### BUILDING SIM ###"
	make -C obj_dir -f V$N.mk V$N
	cp -a $D/data obj_dir/

forever: ./obj_dir/V$N
	@echo
	@echo "### SIMULATION (GUI) ###"
	@cd obj_dir && ./V$N -c 0

sim: ./obj_dir/V$N
	@echo
	@echo "### SIMULATION (GUI) ###"
	#@cd obj_dir && ./V$N -c 100000000
	# 20 seconds
	@cd obj_dir && ./V$N -c 1000000000

trace: ./obj_dir/V$N
	@echo
	@echo "### SIMULATION (trace) ###"
#	@cd obj_dir && ./V$N -t -c 10000000
	@cd obj_dir && ./V$N -t -c 20000000

gtkwave:
	gtkwave obj_dir/waveform.vcd

audio:
	ffmpeg -y -f s16le -ar 32k -ac 2 -i obj_dir/snes.aud snes.wav

clean:
	rm -rf obj_dir/*
