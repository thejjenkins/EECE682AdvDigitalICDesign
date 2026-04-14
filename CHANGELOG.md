# Changelog

Add bullets under **[Unreleased]** as you work. When you tag a release, rename that block to a version and date (for example `## [1.0.0] - 2026-04-13`) and start a new empty **[Unreleased]** section.

Repository: https://github.com/thejjenkins/EECE682AdvDigitalICDesign

## [Unreleased]

### Added

#### rk4_top.sv
-input wire clk

### Changed

#### rk4_top.sv
-comment out input wire clk_100MHz\
-comment out input wire en\
-comment out input wire [1:0] sel\
-comment out output wire clk_1Hz\
-comment out wire clk_in\
-comment out instantiation of rk4_clk_gen\
-replaced clk_in with clk in rk4_projectile_top instance\
-comment out assign clk_1Hz = clk_in\
-comment out everything related to JTAG TAP

#### rk4_script.tcl
-removed rk4_clk_gen.sv rk4_clock_divider.sv rk4_ring_osc.sv from read_hdl\
-removed line write_do_lec because it is not necessary any longer\

#### rk4_dft_script.tcl
-removed rk4_clk_gen.sv rk4_clock_divider.sv rk4_ring_osc.sv jtag_tap.sv from read_hdl\
-comment out line 18 define_test_clock -name clk_100MHz ...\
-comment out lines 21 and 22 define_clock -name clk_div ...\
-comment out line 36 fix_dft_violations -clock -test_control SE\
-added set_db design:rk4_top .dft_mix_clock_edges_in_scan_chains true (this did nothing so I commented it out)\
-added -shift_enable SE to the line beginning with define_scan_chain\

#### constraints.sdc
-commented out current file and replaced with verbatim replica of /projects/howard/genus_scripts/constraints.sdc because we no longer need several different clocks\

#### rk4_top.do
-removed rk4_clk_gen.sv rk4_clock_divider.sv rk4_ring_osc.sv from read design\
-added inverter.sv to read design\

### Fixed

-

### Removed

-
