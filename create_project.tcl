# create_project.tcl - builds the whole Vivado project in one step.
#
# In Vivado's Tcl Console:
#     cd C:/path/to/audio_dsp_fpga
#     source create_project.tcl
# (or:  vivado -source create_project.tcl  from a terminal where Vivado is on the PATH)

# ---- settings ----
set part     xc7a100tcsg324-1   ;# Nexys A7-100T. For the A7-50T use xc7a50tcsg324-1
set run_flow 0                  ;# 1 = also run synthesis + implementation + bitstream
# ------------------

set script_dir [file dirname [file normalize [info script]]]
set proj_name  audio_dsp_spectrum
set proj_dir   [file join $script_dir vivado_project]

create_project $proj_name $proj_dir -part $part -force
set_property target_language Verilog [current_project]

# design sources: all RTL + ROM files (twiddles, Hann window, FIR coefficients)
add_files -norecurse -fileset sources_1 [glob [file join $script_dir rtl *.v]]
add_files -norecurse -fileset sources_1 [glob [file join $script_dir mem *.mem]]
set_property top audio_spectrum_top [get_filesets sources_1]

# constraints
add_files -norecurse -fileset constrs_1 [file join $script_dir constraints nexys_a7_100t.xdc]

# simulation: all testbenches + ROM files (so xsim finds them); default top = FFT unit test
add_files -norecurse -fileset sim_1 [glob [file join $script_dir tb *.v]]
foreach m [glob [file join $script_dir mem *.mem]] { catch { add_files -norecurse -fileset sim_1 $m } }
set_property top tb_fft [get_filesets sim_1]
set_property -name {xsim.simulate.runtime} -value {-all} -objects [get_filesets sim_1]

update_compile_order -fileset sources_1
update_compile_order -fileset sim_1

puts "------------------------------------------------------------"
puts "Project created: [file join $proj_dir ${proj_name}.xpr]"
puts "  Simulate : set a testbench as top (tb_fft, tb_chain, tb_vga),"
puts "             then Run Simulation > Run Behavioral Simulation"
puts "             (tb_chain = full mic->FFT chain, takes a few minutes)"
puts "  Build    : Run Synthesis > Run Implementation > Generate Bitstream"
puts "  Switches : SW1:0 filter mode, SW2 freeze, SW3 zoom, SW5:4 gain"
puts "------------------------------------------------------------"

if {$run_flow} {
    launch_runs synth_1 -jobs 4
    wait_on_run synth_1
    launch_runs impl_1 -to_step write_bitstream -jobs 4
    wait_on_run impl_1
    puts "Bitstream: [file join $proj_dir ${proj_name}.runs impl_1 audio_spectrum_top.bit]"
}
