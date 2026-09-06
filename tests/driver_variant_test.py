#!/usr/bin/env python3
"""Check built external identity and disjoint PCI autoload contracts, device-free."""
from pathlib import Path
import re
import os
import subprocess
import sys

aliases = {}
seen = set()
for directory in map(Path, sys.argv[1:]):
    [module] = directory.glob('*.ko')
    metadata = subprocess.check_output(
        ['readelf', '--string-dump=.modinfo', str(module)], text=True)
    name = re.search(r'\bname=(\S+)', metadata).group(1)
    assert name == module.stem, (module, name)
    ids = set(re.findall(r'alias=(pci:\S+)', metadata))
    family = 'versal' if any('d0000B03F' in a for a in ids) else 'ultrascale_plus'
    isolated = name != 'coyote_driver'
    expected = 'coyote_driver_' + family if isolated else 'coyote_driver'
    assert name == expected
    vermagic = re.search(r'\bvermagic=([^\n]+)', metadata).group(1).strip()
    if os.environ.get('EXPECTED_KERNEL'):
        assert vermagic.split()[0] == os.environ['EXPECTED_KERNEL'], vermagic
    # No exports is a cross-module compatibility boundary, not a requirement
    # to rename ordinary non-exported ELF globals.
    assert not (directory / 'Module.symvers').read_text().strip()
    symbols = subprocess.check_output(['nm', str(module)], text=True)
    assert '__ksymtab_' not in symbols
    assert ids
    if family in aliases:
        assert aliases[family] == ids, 'legacy and explicit binding tables differ'
    aliases[family] = ids
    raw = module.read_bytes()
    prefix = 'coyote_' + family if isolated else 'coyote'
    assert (prefix + '_fpga').encode() in raw
    assert (prefix + '_sysfs').encode() in raw
    seen.add((family, isolated))
    print(module, name, 'PCI aliases:', len(ids), 'exports: 0', 'vermagic:', vermagic)
assert len(seen) == 4, 'supply both families in legacy and isolated forms'
assert not aliases['versal'] & aliases['ultrascale_plus']
assert any('d0000903F' in a for a in aliases['ultrascale_plus'])
assert any('d0000B03F' in a for a in aliases['versal'])
assert not any('d000050B4' in a for ids in aliases.values() for a in ids)
print('PASS: internal/module/device/sysfs identities, legacy parity, no exports, disjoint family aliases')
