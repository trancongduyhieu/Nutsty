#!/usr/bin/env python3
"""
Pure three-way merge for Spotify <-> Nutsty sync (spec 5.3, 5.4). No I/O.

All lists are Spotify track ids. `base` is what both sides agreed on after the last
sync, `remote` is Spotify now, `local` is the Nutsty list now (mapped to Spotify ids).
"""
from dataclasses import dataclass, field


@dataclass
class MergeResult:
    pull_add: list = field(default_factory=list)     # add to Nutsty, remote order
    pull_remove: list = field(default_factory=list)  # remove from Nutsty
    push_add: list = field(default_factory=list)     # add to Spotify (write-back only)
    push_remove: list = field(default_factory=list)  # remove from Spotify (write-back only)
    new_base: list = field(default_factory=list)


def three_way(base, remote, local, write_back, unmatched=frozenset()):
    base_s, remote_s, local_s = set(base), set(remote), set(local)
    unmatched = set(unmatched or ())

    pull_add = [t for t in _dedupe(remote) if t not in base_s and t not in local_s]
    pull_remove = [t for t in _dedupe(base) if t not in remote_s and t in local_s]
    push_add, push_remove = [], []
    if write_back:
        push_add = [t for t in _dedupe(local) if t not in base_s and t not in remote_s]
        push_remove = [t for t in _dedupe(base) if t not in local_s and t in remote_s]

    drop = set(push_remove) | unmatched
    new_base = [t for t in _dedupe(remote) if t not in drop]
    seen = set(new_base)
    new_base += [t for t in push_add if t not in seen]
    return MergeResult(pull_add, pull_remove, push_add, push_remove, new_base)


def remote_is_valid(remote):
    """A remote list may drive deletions only when it was read in full (spec 5.4)."""
    if remote is None or not getattr(remote, "complete", False):
        return False
    return len(getattr(remote, "items", None) or []) == int(getattr(remote, "total", -1))


def mass_delete_blocked(base_len, remove_len):
    """Block a cycle that would remove more than half of a list and more than 3 tracks."""
    return remove_len > 3 and remove_len * 2 > base_len


def _dedupe(seq):
    seen, out = set(), []
    for t in seq:
        if t and t not in seen:
            seen.add(t)
            out.append(t)
    return out
