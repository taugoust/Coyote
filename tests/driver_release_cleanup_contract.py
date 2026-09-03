#!/usr/bin/env python3
"""Regression contract for single-owner vFPGA mapping teardown.

The observed failure was a NULL page dereference when last-close cleanup raced
another teardown while mappings were still published.  This check protects the
lifetime boundary: ownership must be removed from lookup structures before any
re-entrant teardown, and all list/hash owners must be freed exactly once.
"""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
GUP = (ROOT / "driver/src/vfpga/vfpga_gup.c").read_text()
OPS = (ROOT / "driver/src/vfpga/vfpga_ops.c").read_text()


def function_body(source: str, signature: str, occurrence: int = 1) -> str:
    start = -1
    for _ in range(occurrence):
        start = source.index(signature, start + 1)
    brace = source.index("{", start)
    depth = 0
    for index in range(brace, len(source)):
        if source[index] == "{":
            depth += 1
        elif source[index] == "}":
            depth -= 1
            if depth == 0:
                return source[brace + 1 : index]
    raise AssertionError(f"unterminated function: {signature}")


def require_before(body: str, first: str, second: str) -> None:
    first_index = body.index(first)
    second_index = body.index(second)
    assert first_index < second_index, f"{first!r} must precede {second!r}"


single = function_body(GUP, "int tlb_put_user_pages(")
all_for_ctid = function_body(GUP, "int tlb_put_user_pages_ctid(")
release_entry = function_body(GUP, "static int release_user_pages_entry(")
p2p_detach = function_body(GUP, "int p2p_detach_dma_buf(")
last_close = function_body(OPS, "int vfpga_dev_release(")

assert "hash_for_each_safe(" in all_for_ctid
require_before(single, "hash_del(&tmp_entry->entry)", "release_user_pages_entry(")
require_before(all_for_ctid, "hash_del(&tmp_entry->entry)", "release_user_pages_entry(")
assert "kfree(entry);" in release_entry

assert "mutex_lock(&device->pid_lock)" in last_close
assert "mutex_lock(&device->mmu_lock)" in last_close
require_before(last_close, "mutex_lock(&device->pid_lock)", "mutex_lock(&device->mmu_lock)")
assert "hash_for_each_safe(" in last_close
assert "kfree(l_entry);" in last_close
assert "kfree(tmp_h_entry);" in last_close

# DMA-BUF detach has the same publication boundary as ordinary host mappings.
require_before(p2p_detach, "hash_del(&tmp_entry->entry)", "tlb_unmap_gup(")
assert "kfree(tmp_entry);" in p2p_detach

unregister_start = OPS.index("case IOCTL_UNREGISTER_CTID:")
unregister_end = OPS.index("case IOCTL_REGISTER_EVENTFD:", unregister_start)
unregister = OPS[unregister_start:unregister_end]
assert "mutex_lock(&device->mmu_lock)" in unregister
require_before(unregister, "mutex_lock(&device->mmu_lock)", "tlb_put_user_pages_ctid(")
assert "kfree(l_entry);" in unregister
assert "kfree(tmp_h_entry);" in unregister

print("driver release-cleanup contract passed")
