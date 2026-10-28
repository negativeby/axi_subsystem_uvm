# ==============================================================================
# Makefile for AXI Subsystem UVM Verification Platform
# ==============================================================================

VCS      = vcs
VERDI    = verdi

# 加入 -error=noZMMCM 和 -error=noIRIPS，放行适配器不可达分支的语法告警
VCS_FLAGS = -sverilog -full64 -timescale=1ns/1ps \
            -ntb_opts uvm-1.2 \
            -debug_access+all -kdb -lca \
            +v2k \
            -error=noZMMCM \
            -error=noIRIPS \
            -LDFLAGS -Wl,--no-as-needed

INCDIR    = +incdir+../rtl +incdir+../vip +incdir+../tb +incdir+../tests

FILE_LIST = ../vip/axi_if.sv ../vip/axi_transfer.sv ../rtl/*.v ../tb/tb_top.sv ./vcs_fix.c

TESTNAME ?= base_test

all: comp run

comp:
	$(VCS) $(VCS_FLAGS) $(INCDIR) $(FILE_LIST) -l compile.log

run:
	./simv +UVM_TESTNAME=$(TESTNAME) +UVM_VERBOSITY=UVM_MEDIUM -l sim.log

verdi:
	$(VERDI) -ssf tb_top.fsdb $(INCDIR) $(FILE_LIST) &

clean:
	rm -rf simv* csrc* *.log *.key *.fsdb verdiLog novas.* ucli.key DVEfiles vcs_fix.o
