#include <cstdio>
#include <stdlib.h>
#include <limits.h>
#include <string.h>

#include "Vnanospc_top.h"
#include "Vnanospc_top_nanospc_top.h"
#include "Vnanospc_top_DSP.h"
#include "verilated.h"
#include <verilated_vcd_c.h>

#define TRACE_ON

void usage() {
	printf("Usage: sim [-t] [-c T]\n");
	printf("  -t     output trace file waveform.vcd\n");
	printf("  -c T   limit simulate lenght to T time steps. T=0 means infinite.\n");
}

long long max_sim_time = 1000000LL;
vluint64_t sim_time;
bool trace;

int main(int argc, char** argv, char** env) {
	Verilated::commandArgs(argc, argv);
	Vnanospc_top* top = new Vnanospc_top;

	// parse options
	for (int i = 1; i < argc; i++) {
		char *eptr;
		if (strcmp(argv[i], "-t") == 0) {
			trace = true;
			printf("Tracing ON\n");
		} else if (strcmp(argv[i], "-c") == 0 && i+1 < argc) {
			max_sim_time = strtoll(argv[++i], &eptr, 10); 
			if (max_sim_time == 0)
				printf("Simulating forever.\n");
			else
				printf("Simulating %lld steps\n", max_sim_time);
		} else {
			printf("Unrecognized option: %s\n", argv[i]);
			usage();
			exit(1);
		}
	}

	VerilatedVcdC *m_trace;
	if (trace) {
		m_trace = new VerilatedVcdC;
		Verilated::traceEverOn(true);
		top->trace(m_trace, 5);
		m_trace->open("waveform.vcd");
	} 

	int sys_clk_r = 0;
	FILE *f = fopen("snes.aud", "w");
	long long samples = 0;
	int env_r = 0;

	while (max_sim_time == 0 || sim_time < max_sim_time) {
		top->sys_clk ^= 1;
		top->eval(); 

		// collect audio sample
		if (~sys_clk_r && top->sys_clk && top->nanospc_top->snd_rdy) {
			short ar, al;
			ar = top->nanospc_top->audio_r;
			al = top->nanospc_top->audio_l;			
			fwrite(&ar, sizeof(ar), 1, f);
			fwrite(&al, sizeof(al), 1, f);
			samples ++;
			if (samples % 1000 == 0)
				printf("%lld samples\n", samples);
			// printf("%hd %hd\n", top->spcplayer_top->audio_l, top->spcplayer_top->audio_r);
		}

		if (trace)
			m_trace->dump(sim_time);

		int env = top->nanospc_top->dsp->TENVX;		// envelope value
		if (env != 0 && env != env_r) {
			// printf("T=%lu, ENV=%d\n", sim_time, env);
			env_r = env;
		}

		sim_time++;
		sys_clk_r = top->sys_clk;
	}	

	fclose(f);
	printf("Audio output to snes.aud done.\n");

	if (trace)
		m_trace->close();
	delete top;

	return 0;
}
