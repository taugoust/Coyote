# Coyote Example 17: Many vFPGAs

This example fills the FPGA with as many vFPGAs as the shell supports and checks that every one
of them works. Each vFPGA runs the same small loopback, which streams data from host memory
straight back to it, and the host program sends a different pattern through every vFPGA at once
and reports any vFPGA that returns wrong data.

On the V80, the default of 32 vFPGAs uses the shared NoC hub between the vFPGAs. That hub is
built and kept in the design, but the loopback does not drive it yet, so this example shows that
a 32-vFPGA shell builds and closes timing rather than exercising vFPGA-to-vFPGA traffic.

32 vFPGAs require the V80 and a build without application reconfiguration (`EN_PR=0`). Other
boards allow up to 15, which you select with `-DN_REGIONS=<n>`:

```sh
cmake .. -DFDEV_NAME=u280 -DN_REGIONS=15
```

Run the host program with the number of vFPGAs the bitstream contains:

```sh
./test -n 32
```

Building, loading the driver and programming the FPGA work as described in the
[examples README](../README.md).
