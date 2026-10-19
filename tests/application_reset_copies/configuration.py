"""Run production CMake validation/export/import; no hardware execution claims."""
import pathlib
import re
import shutil
import subprocess
import sys
import tempfile

root = pathlib.Path(sys.argv[1]).resolve()
fixture = root / "tests/application_reset_copies/fixture"
output = pathlib.Path(sys.argv[2]).resolve()
output.mkdir(parents=True, exist_ok=True)
with tempfile.TemporaryDirectory() as tmp:
    work = pathlib.Path(tmp)
    for name, board, regions, enabled, uclk, valid in (
        ("default", "v80", 1, 0, 0, True),
        ("off-three", "v80", 3, 0, 0, True),
        ("one", "v80", 1, 1, 0, True),
        ("three", "v80", 3, 1, 0, True),
        ("user-clock", "v80", 3, 1, 1, True),
        ("maximum", "v80", 15, 1, 0, True),
        ("too-many", "v80", 16, 1, 0, False),
        ("nonversal-off", "u280", 1, 0, 0, True),
        ("nonversal-on", "u280", 1, 1, 0, False),
    ):
        build = work / name
        args = ["cmake", "-S", str(fixture), "-B", str(build),
                f"-DCYT_DIR={root}", f"-DFDEV_NAME={board}",
                "-DBUILD_SHELL=1", "-DBUILD_APP=0", "-DBUILD_STATIC=0",
                f"-DTEST_N_REGIONS={regions}",
                f"-DEN_APP_RESET_COPIES={'ON' if enabled else 'OFF'}",
                f"-DEN_UCLK={uclk}"]
        result = subprocess.run(args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        if not valid:
            assert result.returncode and (
                "Independent application resets require" in result.stdout
                or "Max 15 vFPGAs supported" in result.stdout
            ), result.stdout
            print(f"APPLICATION_RESET_CONFIG_REJECT {name}")
            continue
        assert result.returncode == 0, result.stdout
        exported = (build / "export.cmake").read_text()
        assert f"set(EN_APP_RESET_COPIES {enabled})" in exported, exported
        assert re.search(rf"set cfg\(en_app_reset_copies\)\s+{enabled}\b", (build / "base.tcl").read_text())
        generated = build / "coyote-application-reset-configuration_shell"
        (generated / "hdl").mkdir(parents=True)
        (generated / "xdc").mkdir()
        rendered = subprocess.run(
            [sys.executable, str(build / "write_hdl.py"), "1", "0", "0"],
            cwd=build, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
        )
        assert rendered.returncode == 0, rendered.stdout
        shutil.copytree(generated / "hdl", output / name / "hdl")
        shutil.copy(build / "base.tcl", output / name / "base.tcl")
        shutil.copy(build / "export.cmake", output / name / "export.cmake")
        # Exercise the actual BUILD_APP import branch, with the opposite local
        # request, so the exported shell contract must win.
        app = work / f"{name}-app"
        app_args = ["cmake", "-S", str(fixture), "-B", str(app),
                    f"-DCYT_DIR={root}", f"-DFDEV_NAME={board}",
                    "-DBUILD_SHELL=0", "-DBUILD_APP=1", "-DBUILD_STATIC=0",
                    f"-DSHELL_PATH={build}", f"-DTEST_N_REGIONS={regions}",
                    f"-DEN_APP_RESET_COPIES={1-enabled}"]
        imported = subprocess.run(app_args, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
        assert imported.returncode == 0, imported.stdout
        assert f"set(EN_APP_RESET_COPIES {enabled})" in (app / "export.cmake").read_text()
        print(f"APPLICATION_RESET_CONFIG_EXPORT_IMPORT_PASS {name}")
