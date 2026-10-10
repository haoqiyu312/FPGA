create_clock -name sys_clk -period 20 [get_ports sys_clk]
derive_clocks

# ready_clock asserts asynchronously; ASYNC_REG protects the three release chains.
# Only asynchronous requests entering those chains are exempt. Chain data paths
# and the synchronized resets to all downstream logic remain timed.
set_false_path -through [get_nets {ready_clock}] -to [get_regs {sd_reset_pipe* mem_reset_pipe* video_reset_pipe*}]
