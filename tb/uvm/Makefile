XRUN          = xrun
TOP           = tb_top
RTL_FLIST     = rtl_filelist.f
UVM_VERBOSITY ?= UVM_MEDIUM
TEST          ?= rk4_base_test

SIM_ARGS = \
    -uvm \
    -uvmhome CDNS-1.2 \
    -sv \
    -timescale 1ns/1ps \
    -access +rwc \
    -coverage all \
    -f $(RTL_FLIST) \
    rk4_if.sv \
    rk4_tb_pkg.sv \
    tb_top.sv \
    -top $(TOP) \
    +UVM_TESTNAME=$(TEST) \
    +UVM_VERBOSITY=$(UVM_VERBOSITY)

.PHONY: sim gui uvm-full uvm-full-gui clean

sim:
	$(XRUN) $(SIM_ARGS)

gui:
	$(XRUN) $(SIM_ARGS) -gui

uvm-full:
	$(MAKE) sim UVM_VERBOSITY=UVM_FULL

uvm-full-gui:
	$(MAKE) gui UVM_VERBOSITY=UVM_FULL

clean:
	rm -rf xcelium.d INCA_libs xrun.log xrun.history waves.shm
