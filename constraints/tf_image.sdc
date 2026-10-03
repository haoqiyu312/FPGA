create_clock -name sys_clk -period 20 [get_ports sys_clk]
derive_pll_clocks
