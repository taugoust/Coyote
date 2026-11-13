"""Exercise optional shell configuration export/import and generated HDL."""
import pathlib
import re
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1]).resolve()
fixture = root / "tests/shared_configuration/fixture"
flags = {
    "EN_P2P": "0",
    "EN_HOST_NOC": "0",
    "EN_NET_RAW": "0",
    "NET_RAW_VFPGA_ID": "0",
    "EN_AURORA_1": "0",
    "N_AURORA_AXI": "1",
    "EN_AMC": "0",
    "EN_APU": "0",
}


def config(**changes):
    result = dict(flags)
    result.update(changes)
    return result


def run_cmake(build, board, values, *, app=False, shell_path=None, local=None, iprepo=""):
    static = values.get("BUILD_STATIC", 0)
    args = [
        "cmake", "-S", str(fixture), "-B", str(build),
        f"-DCYT_DIR={root}", f"-DFDEV_NAME={board}",
        f"-DBUILD_SHELL={0 if app or static else 1}", f"-DBUILD_APP={1 if app else 0}",
        f"-DBUILD_STATIC={static}", f"-DSHELL_PATH={shell_path or 0}",
        f"-DTEST_N_REGIONS={values.get('N_REGIONS', 1)}",
        f"-DTEST_EN_PR={values.get('EN_PR', 1)}",
        f"-DTEST_EN_SHELL_PBLOCK={values.get('EN_SHELL_PBLOCK', 0)}",
        f"-DTEST_EN_NET_0={values.get('EN_NET_0', 0)}",
        f"-DTEST_EN_NET_1={values.get('EN_NET_1', 0)}",
        f"-DTEST_EN_STATS={values.get('EN_STATS', 0)}",
        f"-DTEST_AVED_IPREPO_PATH={iprepo}",
    ]
    selected = dict(values)
    if local:
        selected.update(local)
    args.extend(f"-DTEST_{key}={value}" for key, value in selected.items()
                if key in flags or key == "EN_V80_R5_PROVIDER")
    args.extend(f"-D{key}={selected[key]}" for key in (
        "PCIE_GEN", "ACLK_F", "SCLK_F", "V80_R5_PROVIDER_QUEUE_DEPTH",
        "V80_R5_PROVIDER_MAX_PACKET_BEATS", "PMTU_HOST", "PMTU_CARD",
        "PMTU_RDMA", "PMTU_TCP", "PMTU_BYTES") if key in selected)
    result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
    return result


def parse_hdl(directory):
    for source in directory.rglob("*.sv"):
        # Verible does not accept the production timing package's 1step
        # literals. Check generated module interfaces here; native-tool
        # package compilation remains a separate acceptance requirement.
        if re.search(r"^\s*package\b", source.read_text(), re.M):
            continue
        parsed = subprocess.run(["verible-verilog-syntax", str(source)], text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert parsed.returncode == 0, f"{source}:\n{parsed.stdout}"


def render(build, board):
    project = build / "coyote-shared-configuration_shell"
    (project / "hdl").mkdir(parents=True, exist_ok=True)
    (project / "xdc").mkdir(parents=True, exist_ok=True)
    result = subprocess.run(
        [sys.executable, str(build / "write_hdl.py"), "1", "0", "0"],
        cwd=build, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
    )
    assert result.returncode == 0, result.stdout
    shell = (project / "hdl/shell_top.sv").read_text()
    dynamic = (project / "hdl/dynamic_top.sv").read_text()
    assert shell and dynamic
    parse_hdl(project / "hdl")
    return shell, dynamic


def usr_irq_width(build):
    # The user-interrupt vector crosses the static/shell boundary, so its width
    # decides whether a shell fits an existing static checkpoint.
    (package,) = (build / "coyote-shared-configuration_shell").rglob("lynx_pkg.sv")
    match = re.search(r"localparam integer N_USR_IRQ = (\d+);", package.read_text())
    assert match, package
    return int(match.group(1))


def assert_cfg(build, expected):
    base = (build / "base.tcl").read_text()
    exported = (build / "export.cmake").read_text()
    cfg_names = {
        "N_REGIONS": "n_reg",
        "V80_R5_PROVIDER_QUEUE_DEPTH": "v80_r5_provider_depth",
        "V80_R5_PROVIDER_MAX_PACKET_BEATS": "v80_r5_provider_max_beats",
    }
    for name, value in expected.items():
        cfg_name = cfg_names.get(name, name.lower())
        assert re.search(rf"^set cfg\({cfg_name}\)\s+{re.escape(str(value))}\s*$", base, re.M), (name, value)
        assert re.search(rf"^set\({name} {re.escape(str(value))}\)$", exported, re.M), (name, value)


with tempfile.TemporaryDirectory(prefix="coyote-shared-config-") as temp:
    work = pathlib.Path(temp)
    aved = work / "aved-iprepo"
    aved.mkdir()

    # Existing/default configuration keeps optional interfaces disabled.
    default = work / "default"
    result = run_cmake(default, "v80", config())
    assert result.returncode == 0, result.stdout
    assert_cfg(default, flags)
    # Defaults must still match our existing shell/checkpoint recipes.
    assert_cfg(default, {"PCIE_GEN": 4, "ACLK_F": 250, "SCLK_F": 333})
    baseline_by_board = {"v80": render(default, "v80")}
    assert usr_irq_width(default) == 15, usr_irq_width(default)
    assert "axis_p2p_send_tdata" not in baseline_by_board["v80"][1]
    u280_default = work / "u280-default"
    result = run_cmake(u280_default, "u280", config())
    assert result.returncode == 0, result.stdout
    baseline_by_board["u280"] = render(u280_default, "u280")
    print("SHARED_CONFIGURATION_DEFAULT_PASS")

    # A flat V80 build may use 32 regions; its existing PR limit stays at 15.
    flat = config(N_REGIONS=32, EN_PR=0, EN_SHELL_PBLOCK=1, EN_P2P=1, EN_HOST_NOC=1)
    build = work / "v80-flat-32"
    result = run_cmake(build, "v80", flat)
    assert result.returncode == 0, result.stdout
    assert_cfg(build, flat)
    shell, dynamic = render(build, "v80")
    assert "axis_p2p_send_tdata" in dynamic
    assert "axis_p2p_arbiter" in dynamic
    assert usr_irq_width(build) == 32, usr_irq_width(build)
    print("SHARED_CONFIGURATION_V80_FLAT_32_PASS")

    cases = [
        ("v80-raw-dcmac", "v80", config(EN_NET_RAW=1, NET_RAW_VFPGA_ID=0)),
        ("u280-aurora", "u280", config(EN_AURORA_1=1, N_AURORA_AXI=1)),
        ("v80-amc", "v80", config(EN_AMC=1)),
        ("v80-apu", "v80", config(EN_APU=1)),
        ("v80-amc-apu", "v80", config(EN_AMC=1, EN_APU=1)),
    ]
    for name, board, values in cases:
        build = work / name
        result = run_cmake(build, board, values, iprepo=str(aved))
        assert result.returncode == 0, f"{name}:\n{result.stdout}"
        assert_cfg(build, values)
        rendered = render(build, board)
        if not (str(values.get("EN_APU")) == "1" and str(values.get("EN_AMC")) != "1"):
            assert rendered != baseline_by_board[board], f"{name}: enabled configuration did not affect rendered HDL"
        print(f"SHARED_CONFIGURATION_RENDER_PASS {name}")

        # A BUILD_APP invocation requesting the opposite must inherit the
        # exported shell's choices, not its local optional-feature switches.
        opposite = {name: "0" if str(value) == "1" else "1" for name, value in values.items() if name in flags}
        # Include all optional toggles to ensure absent shell choices override
        # application-local requests too.
        opposite.update({key: "1" for key in flags if key.startswith("EN_")})
        opposite.update({"NET_RAW_VFPGA_ID": "1", "N_AURORA_AXI": "2"})
        app = work / f"{name}-app"
        result = run_cmake(app, board, values, app=True, shell_path=build,
                           local=opposite, iprepo=str(aved))
        assert result.returncode == 0, f"{name} BUILD_APP import:\n{result.stdout}"
        assert_cfg(app, values)
        print(f"SHARED_CONFIGURATION_BUILD_APP_IMPORT_PASS {name}")

    # Exercise the shared CIPS/DDR substrate with the provider enabled, at
    # both PCIe generations and both negotiated storage shapes.
    for name, amc, apu, pcie, depth, beats in (
        ("provider", 0, 0, 4, 4, 64),
        ("amc-provider", 1, 0, 4, 4, 64),
        ("apu-provider", 0, 1, 5, 4, 64),
        ("amc-apu-provider-small", 1, 1, 5, 2, 4),
    ):
        values = config(BUILD_STATIC=1, EN_PR=0, EN_SHELL_PBLOCK=0,
                        EN_AMC=amc, EN_APU=apu, PCIE_GEN=pcie,
                        EN_V80_R5_PROVIDER=1,
                        V80_R5_PROVIDER_QUEUE_DEPTH=depth,
                        V80_R5_PROVIDER_MAX_PACKET_BEATS=beats)
        if pcie == 5:
            values.update(ACLK_F=400, SCLK_F=400)
        build = work / name
        result = run_cmake(build, "v80", values, iprepo=str(aved))
        assert result.returncode == 0, f"{name}:\n{result.stdout}"
        assert_cfg(build, {key: value for key, value in values.items()
                           if key not in {"BUILD_STATIC", "EN_PR", "EN_SHELL_PBLOCK"}})
        render(build, "v80")
        static_project = build / "coyote-shared-configuration_static/hdl/static"
        static_project.mkdir(parents=True)
        generated = subprocess.run(
            [sys.executable, str(build / "write_hdl.py"), "0", "0", "0"],
            cwd=build, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert generated.returncode == 0, generated.stdout
        parse_hdl(static_project)
        print(f"SHARED_CONFIGURATION_PROVIDER_COMBINATION_PASS {name}")

    # PMTU sizes belong to the shell and are imported unchanged by BUILD_APP.
    pmtu_values = config(PMTU_HOST=8192, PMTU_CARD=2048,
                         PMTU_RDMA=1024, PMTU_TCP=16384)
    pmtu_shell = work / "pmtu-shell"
    result = run_cmake(pmtu_shell, "v80", pmtu_values)
    assert result.returncode == 0, result.stdout
    assert_cfg(pmtu_shell, {key: value for key, value in pmtu_values.items()
                            if key.startswith("PMTU_")})
    pmtu_conflicts = {"PMTU_HOST": 4096, "PMTU_CARD": 4096,
                      "PMTU_RDMA": 2048, "PMTU_TCP": 32768}
    pmtu_app = work / "pmtu-app"
    result = run_cmake(pmtu_app, "v80", config(), app=True,
                       shell_path=pmtu_shell, local=pmtu_conflicts)
    assert result.returncode == 0, result.stdout
    assert_cfg(pmtu_app, {key: value for key, value in pmtu_values.items()
                          if key.startswith("PMTU_")})
    print("SHARED_CONFIGURATION_PMTU_BUILD_APP_IMPORT_PASS")

    # A real legacy export has no split fields and carries only PMTU_BYTES.
    old_shell = work / "old-export-shell"
    result = run_cmake(old_shell, "v80", config())
    assert result.returncode == 0, result.stdout
    old_export = old_shell.joinpath("export.cmake").read_text()
    for name in (*flags, "PMTU_HOST", "PMTU_CARD", "PMTU_RDMA", "PMTU_TCP"):
        old_export = re.sub(rf"^set\({name} .*\n", "", old_export, flags=re.M)
    legacy_shell = work / "legacy-export"
    legacy_shell.mkdir()
    (legacy_shell / "export.cmake").write_text(old_export + "\nset(PMTU_BYTES 4096)\n")
    old_app = work / "old-export-app"
    legacy_local = {"PMTU_HOST": 8192, "PMTU_CARD": 2048,
                    "PMTU_RDMA": 1024, "PMTU_TCP": 16384}
    result = run_cmake(old_app, "v80", config(), app=True, shell_path=legacy_shell,
                       local=legacy_local, iprepo=str(aved))
    assert result.returncode == 0, result.stdout
    assert_cfg(old_app, {**flags, "PMTU_HOST": 4096, "PMTU_CARD": 4096,
                         "PMTU_RDMA": 4096, "PMTU_TCP": 4096})
    print("SHARED_CONFIGURATION_OLD_PMTU_EXPORT_COMPAT_PASS")

    # Partial modern exports and mixed modern/legacy exports are ambiguous;
    # neither may fall back to app-local cache defaults.
    modern_export = pmtu_shell.joinpath("export.cmake").read_text()
    for label, export_text in (
        ("incomplete", re.sub(r"^set\(PMTU_TCP .*\n", "", modern_export, flags=re.M)),
        ("ambiguous", modern_export + "\nset(PMTU_BYTES 4096)\n"),
    ):
        bad_shell = work / f"pmtu-{label}-export"
        bad_shell.mkdir()
        (bad_shell / "export.cmake").write_text(export_text)
        bad_app = work / f"pmtu-{label}-app"
        result = run_cmake(bad_app, "v80", config(), app=True,
                           shell_path=bad_shell, local=pmtu_conflicts)
        assert result.returncode != 0 and "Shell export must provide" in result.stdout, (label, result.stdout)
        print(f"SHARED_CONFIGURATION_PMTU_EXPORT_REJECT_PASS {label}")

    rejects = [
        ("host-noc-board", "u280", config(EN_HOST_NOC=1), "EN_HOST_NOC requires V80"),
        ("raw-stack-mode", "v80", config(EN_NET_RAW=1, NET_RAW_VFPGA_ID=0, EN_STATS=1), "EN_NET_RAW bypasses the network stack"),
        ("aurora-qsfp-conflict", "u280", config(EN_AURORA_1=1, EN_NET_1=1), "EN_AURORA_1 and EN_NET_1 both enabled"),
        ("region-limit-with-pr", "v80", config(N_REGIONS=32, EN_PR=1), "Max 15 vFPGAs supported"),
        ("pmtu-nonpower", "v80", config(PMTU_HOST=1000), "PMTU_HOST=1000 must be a power of 2"),
        ("pmtu-zero", "v80", config(PMTU_CARD=0), "PMTU_CARD=0 must be a power of 2"),
        ("pmtu-host-upper-bound", "v80", config(PMTU_HOST=65536), "PMTU_HOST=65536 must be a power of 2 between 64 and 32768."),
        ("pmtu-rdma-upper-bound", "v80", config(PMTU_RDMA=8192), "PMTU_RDMA=8192 must not exceed 4096"),
    ]
    for name, board, values, reason in rejects:
        build = work / f"reject-{name}"
        result = run_cmake(build, board, values)
        assert result.returncode != 0 and reason in result.stdout, (name, result.stdout)
        print(f"SHARED_CONFIGURATION_REJECT_PASS {name}")
