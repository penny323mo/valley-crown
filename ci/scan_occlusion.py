#!/usr/bin/env python3
"""Exact new-fixture schema adapter; existing provenance/privacy scanner unchanged.

Admission retains diagnosed pixel failures. It NEVER means the pixel gate passed.
"""
from pathlib import Path
import argparse
import scan_evidence as base

FUNCTIONAL = {
    'normal visible mesh unchanged', 'only two local geometry passes added',
    'occluded authorized unit receives silhouette', 'partially visible unit fragments unchanged',
    'occluded limbs use one flat silhouette color', 'hidden ancestor silhouette is absent',
}


def capture_checks(label):
    return [label + suffix for suffix in (' framebuffer saved', ' real framebuffer', ' sidecar opened')]


base.OCCLUSION_CHECKS = (
    ['Compatibility renderer', 'fixture bound real exported rig', 'fixture rig supports exact visibility mask']
    + capture_checks(base.OCCLUSION_LABELS[0]) + capture_checks(base.OCCLUSION_LABELS[1])
    + ['normal visible mesh unchanged', 'only two local geometry passes added']
    + capture_checks(base.OCCLUSION_LABELS[2]) + capture_checks(base.OCCLUSION_LABELS[3])
    + ['occluded authorized unit receives silhouette'] + capture_checks(base.OCCLUSION_LABELS[4])
    + ['partially visible unit fragments unchanged', 'occluded limbs use one flat silhouette color']
    + capture_checks(base.OCCLUSION_LABELS[5]) + ['hidden ancestor silhouette is absent']
)
base.FUNCTIONAL_OCCLUSION_CHECKS = FUNCTIONAL


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    for name in ('directory', 'lock', 'report'):
        parser.add_argument('--' + name, type=Path, required=True)
    args = parser.parse_args()
    raise SystemExit(base.scan_to_report(args.directory, args.lock, args.report))
