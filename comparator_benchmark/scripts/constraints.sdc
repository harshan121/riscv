# Common virtual timing environment for each combinational top-level DUT.
create_clock -name virtual_clk -period 1.000
set_input_delay 0.100 -clock virtual_clk [all_inputs]
set_output_delay 0.100 -clock virtual_clk [all_outputs]
set_load 0.010 [all_outputs]
