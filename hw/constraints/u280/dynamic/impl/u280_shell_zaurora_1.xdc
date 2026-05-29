###
### Aurora 64B/66B on QSFP1 — overrides QSFP1 reference clock pins to 161 MHz
###
### This file MUST sort alphabetically AFTER u280_shell_net_1.xdc (hence the
### `zaurora` prefix) so its PACKAGE_PIN assignments override net_1's 156 MHz
### settings. Vivado emits a warning on PACKAGE_PIN override but the last
### assignment wins.
###
### Active when EN_AURORA_1=1 in CMake. Verified mutually exclusive with
### EN_NET_1=1 by validation_checks_hw() in cmake/FindCoyoteHW.cmake.
###

# QSFP1 reference clock — 161.1328125 MHz (Aurora's required ref clock)
set_property PACKAGE_PIN M43 [get_ports gt1_refclk_n]
set_property PACKAGE_PIN M42 [get_ports gt1_refclk_p]

# Note: the Aurora IP defines its own create_clock on the MGTREFCLK input via
# its packaged XDC (period 6.206 ns = 1/161.1328125 MHz). We do NOT redefine
# it here — doing so would conflict with the IP's internal constraint.
