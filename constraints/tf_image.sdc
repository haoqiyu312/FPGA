create_clock -name sys_clk -period 20 [get_ports sys_clk]
derive_clocks

# Reset requests assert asynchronously; each domain releases reset after three clocks.
# Limit exceptions to the request nets entering the reset synchronizers.
# Their shift-register data paths and all downstream reset paths remain timed.
set_false_path -through [get_nets {ready_clock}] -to [get_regs {sd_reset_pipe*}]
set_false_path -through [get_nets {ready_clock}] -to [get_regs {mem_reset_pipe*}]
set_false_path -through [get_nets {video_ready}] -to [get_regs {video_reset_pipe*}]
