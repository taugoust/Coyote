"""Execute production Tcl with a recording Vivado boundary; no physical claims."""
import pathlib
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1]).resolve()


def run_flow(template, regions=3, configs=1, arch="versal", nested=0):
    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        (work / "config_0").mkdir()
        (work / "config_0/shell_routed_c0.dcp").touch()
        (work / "base.tcl").write_text(f"""
array set cfg {{n_config {configs} n_reg {regions} fpga_arch {arch} en_shell_pblock {nested} fplan_path floorplan.xdc static_path static fdev v80 pcie_gen 4 en_pr 1 build_shell 1 build_app 0 app_parent_reference 0 app_regions {{{' '.join(str(r) for r in range(regions))}}}}}
set dcp_dir {{{work}}}
set hw_dir hardware
set part test_part
set bit_dir {{{work}/bitstreams}}
set clr_error red
set clr_flow blue
set clr_cmplt green
proc color {{c message}} {{return $message}}
proc version {{args}} {{return 2025.1}}
proc get_files {{args}} {{return $args}}
proc get_filesets {{args}} {{return $args}}
proc get_msg_config {{args}} {{return 0}}
foreach cmd {{create_project add_files set_property link_design write_checkpoint close_project open_checkpoint update_design lock_design pr_recombine write_device_image write_debug_probes exec}} {{
    proc $cmd {{args}} {{puts "CALL [lindex [info level 0] 0] $args"}}
}}
""")
        (work / "app_link_integrity.tcl").touch()
        script = (root / "scripts" / template).read_text().replace(
            "${CMAKE_BINARY_DIR}", str(work)
        )
        (work / "flow.tcl").write_text(script)
        result = subprocess.run(["tclsh", str(work / "flow.tcl")], text=True, capture_output=True)
        return result.returncode, result.stdout + result.stderr


for regions in (1, 3):
    code, output = run_flow("dyn/flow_dyn_link_versal.tcl.in", regions)
    assert code == 0, output
    cells = [f"inst_shell/inst_dynamic/inst_user_wrapper_{r}" for r in range(regions)]
    for r, cell in enumerate(cells):
        assert f"user_synthed_c0_{r}.dcp" in output, output
        assert f"CALL set_property SCOPED_TO_CELLS {cell} " in output, output
    link = next(line for line in output.splitlines() if line.startswith("CALL link_design"))
    assert all(cell in link for cell in cells), output
    assert f"inst_user_wrapper_{regions}" not in output, output

    code, output = run_flow("dyn/flow_dyn_finalize.tcl.in", regions)
    assert code == 0, output
    blackboxes = [line for line in output.splitlines() if line.startswith("CALL update_design")]
    assert blackboxes == [f"CALL update_design -black_box -cell {cell}" for cell in cells], output
    assert output.index(blackboxes[-1]) < output.index("CALL lock_design -level routing") < output.index("shell_routed_locked.dcp"), output
    assert "pr_recombine" not in output, output

    code, output = run_flow("impl/bitgen.tcl.in", regions)
    assert code == 0, output
    partials = [line for line in output.splitlines() if line.startswith("CALL write_device_image -force -cell")]
    assert len(partials) == regions, output
    for r, line in enumerate(partials):
        assert f"-cell {cells[r]} " in line and line.endswith(f"/config_0/vfpga_c0_{r}.pdi"), output
    assert "shell_top.pdi" not in output, output
    assert "CALL write_device_image -force -no_partial_pdifile" in output, output

for template in ("dyn/flow_dyn_link_versal.tcl.in", "dyn/flow_dyn_finalize.tcl.in"):
    for overrides in ({"configs": 2}, {"regions": 0}, {"regions": 16}, {"nested": 1}):
        code, output = run_flow(template, **overrides)
        assert code != 0 and "CALL " not in output, output
code, output = run_flow("dyn/flow_dyn_finalize.tcl.in", arch="ultrascale_plus")
assert code != 0 and "CALL " not in output, output
code, output = run_flow("dyn/flow_app_link.tcl.in")
assert code != 0 and "requires one configuration and one region" in output, output
assert "CALL " not in output, output

# Exercise CMake's actual public artifact inventory macro, not a copied loop.
for regions in (1, 3):
    with tempfile.TemporaryDirectory() as tmp:
        work = pathlib.Path(tmp)
        floorplan = work / "floorplan.xdc"
        floorplan.touch()
        (work / "FindVivado.cmake").write_text("set(VIVADO_FOUND TRUE)\n")
        script = work / "inventory.cmake"
        script.write_text(f"""
set(CMAKE_MODULE_PATH "{work}")
include("{root}/cmake/FindCoyoteHW.cmake")
set(CYT_DIR "{root}")
set(CMAKE_BINARY_DIR "{work}")
set(N_CONFIG 1)
set(N_REGIONS {regions})
set(FPGA_ARCH versal)
set(FDEV_NAME v80)
set(BUILD_SHELL 1)
set(EN_PR 1)
set(FPLAN_PATH "{floorplan}")
set(IMPLEMENTATION_PHASE link)
gen_dep_lists()
configure_file("{root}/scripts/export.cmake.in" "{work}/export.cmake")
file(WRITE "{work}/inventory.txt" "${{DEP_DCP_LIST_SYNTH_USER}}\n${{DEP_DCP_LIST_BGEN}}\n${{DEP_DCP_LIST_DYN}}")
""")
        result = subprocess.run(["cmake", "-P", str(script)], cwd=work, text=True, capture_output=True)
        assert result.returncode == 0, result.stdout + result.stderr
        lines = (work / "inventory.txt").read_text().splitlines()
        synth, images, dynamic = [set(pathlib.Path(p).relative_to(work).as_posix() for p in line.split(";")) for line in lines]
        assert synth == {f"checkpoints/config_0/user_synthed_c0_{r}.dcp" for r in range(regions)}, synth
        assert images == {"bitstreams/cyt_top.pdi", "bitstreams/cyt_top.ltx"} | {
            f"bitstreams/config_0/vfpga_c0_{r}.{ext}" for r in range(regions) for ext in ("pdi", "ltx")
        }, images
        assert "checkpoints/shell_routed_locked.dcp" in dynamic, dynamic
        exported = (work / "export.cmake").read_text()
        assert f"set(N_CONFIG 1)" in exported and f"set(N_REGIONS {regions})" in exported, exported
print("PASS: one/three-region shell flows, exported topology, and artifact inventories; invalid inputs reject")
