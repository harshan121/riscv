if {![info exists ::env(LIBERTY_FILE)] || ![info exists ::env(NETLIST_FILE)] || ![info exists ::env(TOP_MODULE)]} {
    puts stderr "LIBERTY_FILE, NETLIST_FILE, and TOP_MODULE must be set"
    exit 1
}

read_liberty $::env(LIBERTY_FILE)
read_verilog $::env(NETLIST_FILE)
link_design $::env(TOP_MODULE)
read_sdc comparator_benchmark/scripts/constraints.sdc
report_checks -path_delay max -from [all_inputs] -to [all_outputs] -format full_clock_expanded -digits 4
exit
