read_liberty $::env(LIBERTY_FILE)
read_verilog $::env(NETLIST_FILE)
link_design $::env(TOP_MODULE)
read_sdc comparator_benchmark/signed_le_experiment/scripts/constraints.sdc
report_checks -path_delay max -from [all_inputs] -to [all_outputs] -format full_clock_expanded -digits 4
exit
