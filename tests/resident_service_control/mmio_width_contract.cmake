# The PCIe DMA bridge presents shell MMIO on a 512-bit AXI4 interface. Host
# readl/readq operations arrive as 32- and 64-bit narrow transfers before the
# shell control interconnect converts them to 64-bit AXI4-Lite transactions.
# Both supported board implementations must advertise those transfers at the
# interconnect boundary; otherwise upper-dword reads can terminate with an AXI
# error before reaching a resident-service target.
foreach(architecture IN ITEMS ultrascale_plus versal)
    set(control_bd "${CYT_DIR}/hw/bd/${architecture}/cr_ctrl.tcl")
    file(READ "${control_bd}" control_bd_source)

    string(REGEX MATCHALL
        "CONFIG\\.SUPPORTS_NARROW_BURST[ \t]+\\{1\\}"
        narrow_transfer_declarations
        "${control_bd_source}"
    )
    list(LENGTH narrow_transfer_declarations narrow_transfer_count)
    if(NOT narrow_transfer_count EQUAL 1)
        message(FATAL_ERROR
            "${architecture} shell control must accept 32/64-bit host MMIO transfers on its 512-bit AXI input"
        )
    endif()
endforeach()
