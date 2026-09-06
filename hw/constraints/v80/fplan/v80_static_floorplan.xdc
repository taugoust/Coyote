create_pblock pblock_inst_shell
add_cells_to_pblock [get_pblocks pblock_inst_shell] [get_cells -quiet [list inst_shell]]
resize_pblock [get_pblocks pblock_inst_shell] -add {SLICE_X164Y188:SLICE_X203Y331 SLICE_X144Y0:SLICE_X163Y331 SLICE_X0Y428:SLICE_X27Y903}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_A_GRP0_X84Y0:BLI_A_GRP0_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_A_GRP1_X84Y0:BLI_A_GRP1_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_A_GRP2_X84Y0:BLI_A_GRP2_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_B_GRP0_X84Y0:BLI_B_GRP0_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_B_GRP1_X84Y0:BLI_B_GRP1_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_B_GRP2_X84Y0:BLI_B_GRP2_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_C_GRP0_X84Y0:BLI_C_GRP0_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_C_GRP1_X84Y0:BLI_C_GRP1_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_C_GRP2_X84Y0:BLI_C_GRP2_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_D_GRP4_X84Y0:BLI_D_GRP4_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_D_GRP5_X84Y0:BLI_D_GRP5_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_D_GRP6_X84Y0:BLI_D_GRP6_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BLI_D_GRP7_X84Y0:BLI_D_GRP7_X97Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {BUFG_FABRIC_X2Y48:BUFG_FABRIC_X2Y95}
resize_pblock [get_pblocks pblock_inst_shell] -add {BUFG_GT_X0Y120:BUFG_GT_X0Y239}
resize_pblock [get_pblocks pblock_inst_shell] -add {BUFG_GT_SYNC_X0Y205:BUFG_GT_SYNC_X0Y409}
resize_pblock [get_pblocks pblock_inst_shell] -add {DCMAC_X0Y2:DCMAC_X0Y2}
resize_pblock [get_pblocks pblock_inst_shell] -add {DPLL_X0Y10:DPLL_X0Y19}
resize_pblock [get_pblocks pblock_inst_shell] -add {DSP58_CPLX_X3Y94:DSP58_CPLX_X5Y165 DSP58_CPLX_X3Y0:DSP58_CPLX_X3Y93}
resize_pblock [get_pblocks pblock_inst_shell] -add {DSP_X6Y94:DSP_X11Y165 DSP_X6Y0:DSP_X7Y93}
resize_pblock [get_pblocks pblock_inst_shell] -add {GTM_QUAD_X0Y9:GTM_QUAD_X0Y10}
resize_pblock [get_pblocks pblock_inst_shell] -add {GTM_REFCLK_X0Y18:GTM_REFCLK_X0Y21}
resize_pblock [get_pblocks pblock_inst_shell] -add {HBM_MC_X15Y0:HBM_MC_X15Y0 HBM_MC_X0Y0:HBM_MC_X1Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {HBM_PHY_CHNL_X15Y0:HBM_PHY_CHNL_X15Y0 HBM_PHY_CHNL_X0Y0:HBM_PHY_CHNL_X1Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {IRI_QUAD_X0Y3660:IRI_QUAD_X17Y3671 IRI_QUAD_X1Y3648:IRI_QUAD_X16Y3659 IRI_QUAD_X0Y2892:IRI_QUAD_X17Y3647 IRI_QUAD_X0Y1740:IRI_QUAD_X3Y2507 IRI_QUAD_X92Y780:IRI_QUAD_X134Y1355 IRI_QUAD_X92Y16:IRI_QUAD_X106Y779 IRI_QUAD_X94Y4:IRI_QUAD_X105Y15 IRI_QUAD_X92Y0:IRI_QUAD_X106Y3}
resize_pblock [get_pblocks pblock_inst_shell] -add {MRMAC_X0Y2:MRMAC_X0Y4}
resize_pblock [get_pblocks pblock_inst_shell] -add {NOC_NMU512_X1Y4:NOC_NMU512_X1Y6}
resize_pblock [get_pblocks pblock_inst_shell] -add {NOC_NMU_HBM2E_X61Y0:NOC_NMU_HBM2E_X63Y0 NOC_NMU_HBM2E_X0Y0:NOC_NMU_HBM2E_X5Y0}
resize_pblock [get_pblocks pblock_inst_shell] -add {NOC_NPS_VNOC_X1Y8:NOC_NPS_VNOC_X1Y13}
resize_pblock [get_pblocks pblock_inst_shell] -add {NOC_NSU512_X1Y4:NOC_NSU512_X1Y6}
resize_pblock [get_pblocks pblock_inst_shell] -add {RAMB18_X6Y96:RAMB18_X7Y167 RAMB18_X5Y2:RAMB18_X5Y167 RAMB18_X0Y216:RAMB18_X0Y455}
resize_pblock [get_pblocks pblock_inst_shell] -add {RAMB36_X6Y48:RAMB36_X7Y83 RAMB36_X5Y1:RAMB36_X5Y83 RAMB36_X0Y108:RAMB36_X0Y227}
resize_pblock [get_pblocks pblock_inst_shell] -add {URAM288_X3Y48:URAM288_X4Y83 URAM288_X3Y1:URAM288_X3Y47}
resize_pblock [get_pblocks pblock_inst_shell] -add {URAM_CAS_DLY_X3Y2:URAM_CAS_DLY_X4Y3 URAM_CAS_DLY_X3Y0:URAM_CAS_DLY_X3Y1}
resize_pblock [get_pblocks pblock_inst_shell] -add {CLOCKREGION_X1Y11:CLOCKREGION_X7Y11 CLOCKREGION_X1Y7:CLOCKREGION_X8Y10 CLOCKREGION_X1Y5:CLOCKREGION_X9Y6 CLOCKREGION_X5Y3:CLOCKREGION_X9Y4 CLOCKREGION_X4Y1:CLOCKREGION_X8Y2 CLOCKREGION_X5Y0:CLOCKREGION_X10Y0}
set_property SNAPPING_MODE ON [get_pblocks pblock_inst_shell]
set_property IS_SOFT FALSE [get_pblocks pblock_inst_shell]

# Keep the first static AXI register stage beside the static SmartConnect.
# Otherwise the exclusionary shell partition can split this register slice
# across the shell and turn its local payload-enable paths into device-wide
# routes.
set static_axi_first_stage [get_cells -quiet -hierarchical -filter \
    {IS_PRIMITIVE && NAME =~ "inst_static/inst_cnvrt_static/inst_s0_axi_main/genblk1[0].inst_reg/*"}]
if {[llength $static_axi_first_stage] == 0} {
    error "V80 static AXI first-stage primitive cells were not found"
}
create_pblock pblock_static_axi_first_stage
add_cells_to_pblock [get_pblocks pblock_static_axi_first_stage] \
    $static_axi_first_stage
resize_pblock [get_pblocks pblock_static_axi_first_stage] -add \
    {CLOCKREGION_X2Y2:CLOCKREGION_X3Y3}
set_property IS_SOFT FALSE [get_pblocks pblock_static_axi_first_stage]

# Keep the small QDMA H2C metadata address/control set local to its EOP FIFO.
# This avoids marginal control paths between replicated sink-FIFO addressing
# and distributed metadata storage without constraining the complete QDMA.
set qdma_h2c_critical_metadata [get_cells -quiet -hierarchical -filter {
    IS_PRIMITIVE && (
        NAME =~ "inst_static/inst_int_static/versal_cips_0/inst/cpm_0/inst/qdma_1_wrapper_i/AXIST.u_demux/mdma_axis_h2c_tl_slv/ch_sink_fifo[0].u_ch_fifo/sram_radr_reg*" ||
        NAME =~ "inst_static/inst_int_static/versal_cips_0/inst/cpm_0/inst/qdma_1_wrapper_i/AXIST.u_demux/u_h2c_axis_desegmenter/u_eop_info_fifo/RAM_INST[0].u_ram/sram_reg[5]*"
    )
}]
if {[llength $qdma_h2c_critical_metadata] == 0} {
    error "V80 QDMA H2C critical metadata primitive cells were not found"
}
create_pblock pblock_qdma_h2c_critical_metadata
add_cells_to_pblock [get_pblocks pblock_qdma_h2c_critical_metadata] \
    $qdma_h2c_critical_metadata
resize_pblock [get_pblocks pblock_qdma_h2c_critical_metadata] -add \
    {SLICE_X68Y238:SLICE_X80Y260}
set_property IS_SOFT FALSE [get_pblocks pblock_qdma_h2c_critical_metadata]
