# ==============================================================
# AXI4 UVM 验证平台 Makefile
# ==============================================================

PROJ_ROOT  ?= $(shell cd .. && pwd)
TEST       ?= base_test
VERB       ?= UVM_LOW
SEED       ?= 1

export VERDI_HOME ?= /home/synopsys/verdi/Verdi_O-2018.09-SP2

# 路径包含
INCDIRS    = +incdir+$(PROJ_ROOT)/tb \
             +incdir+$(PROJ_ROOT)/vip \
             +incdir+$(PROJ_ROOT)/tests \
             +incdir+$(PROJ_ROOT)/rtl

# 源码入口
# 源码入口 (按依赖先后顺序编译)
RTL_FILES  = $(wildcard $(PROJ_ROOT)/rtl/*.v)
TB_FILES   = $(PROJ_ROOT)/vip/axi_if.sv \
             $(PROJ_ROOT)/vip/axi_vip_pkg.sv \
             $(PROJ_ROOT)/tests/axi_concurrent_sequence.sv \
             $(PROJ_ROOT)/tests/base_test.sv \
             $(PROJ_ROOT)/tests/concurrent_test.sv \
             $(PROJ_ROOT)/tb/tb_top.sv 

# 兼容性目标文件
SHIM_OBJ   = $(PROJ_ROOT)/sim/pthread_yield.o

# 强制链接器禁止裁剪间接依赖库
LD_FLAGS   = -Wl,--no-as-needed

# VCS 编译选项
VCS_FLAGS  = -full64 \
             -sverilog \
             -ntb_opts uvm-1.2 \
             -timescale=1ns/1ps \
             -debug_pp \
             -fsdb \
             -LDFLAGS "$(LD_FLAGS)" \
             -cm line+cond+fsm+tgl+branch+assert \
             -cm_hier cov_hier.cfg\
             -l comp.log \
             $(INCDIRS)

# 仿真运行选项
SIM_FLAGS  = +UVM_TESTNAME=$(TEST) \
             +UVM_VERBOSITY=$(VERB) \
             +ntb_random_seed=$(SEED) \
             -cm line+cond+fsm+tgl+branch+assert \
             -cm_name $(TEST)_seed_$(SEED) \
             -l sim_$(TEST).log

.PHONY: all comp run urg clean

all: comp run urg

# 目标 1: 编译链接
comp:
	vcs $(VCS_FLAGS) $(RTL_FILES) $(TB_FILES) $(SHIM_OBJ) -o simv

# 目标 2: 动态仿真
run:
	./simv $(SIM_FLAGS)

# 目标 3: 生成 URG 覆盖率网页报表
urg:
	urg -dir simv.vdb -report urgReport
	@echo "=========================================================="
	@echo "覆盖率网页报表生成完毕: 请在终端输入 firefox urgReport/dashboard.html 查看"
	@echo "=========================================================="

# 目标 4: 清理
clean:
	rm -rf simv* csrc *.log *.key *.fsdb *.vdb urgReport ucli.key vc_hdrs.h novas.* verdiLog vdCovLog
