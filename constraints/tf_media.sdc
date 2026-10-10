create_clock -name sys_clk -period 20 [get_ports sys_clk]
derive_clocks
# Asynchronous assertion only; reset release chains and downstream logic remain timed.
set_false_path -through [get_nets {ready_clock}] -to [get_regs {sd_reset_pipe* mem_reset_pipe*}]
set_false_path -through [get_nets {video_ready}] -to [get_regs {video_reset_pipe*}]
