"""Explicit independent longer rendered profile; pure read-only gate."""
from pathlib import Path
import hashlib

def validate_profile(profile, bundle):
    expected={'name':'ordinary-rendered-450-ack-v2','reviewed_for_execution':True,'diagnostic_only':True,
      'capture_ack_capability':'current_monotonic_id_only_after_png_and_metadata_persistence',
      'product_source':'ce2ea3d2513bd79cf62cf5c651abe3c47aad8513','product_tree':'cadc77674b0b3184e7c3af9961f3e6ffdac507e9','product_build':'vc-79ebcaef19e3',
      'fixture_seconds':440,'scenario_seconds':450,'node_seconds':460,'service_seconds':470,'outer_seconds':475,'snapshot_read_seconds':5,'viewport':[390,844],
      'policy_donor_sha256':'7e91b3ec012c3e74be1ce1a23141d72ee0d015ed4dcb1646c59d5e4f0449e86a'}
    if any(profile.get(k)!=v for k,v in expected.items()):raise ValueError('Distinct rendered profile is not exactly reviewed')
    pins=profile.get('bound_files_sha256',{})
    if set(pins)!={'run_host_rendered.py','host_rendered.mjs','browser_rendered.mjs','rendered_profile.py','capture_handshake.mjs'}:raise ValueError('Exact rendered helper binding required')
    for n,h in pins.items():
        if hashlib.sha256((Path(bundle)/n).read_bytes()).hexdigest()!=h:raise ValueError('Rendered helper changed: '+n)
    overlay=profile.get('diagnostic_overlay',{})
    if set(overlay)!={'full_rendered_match.gd','full_rendered_match.tscn'} or any(len(x)!=64 for x in overlay.values()):raise ValueError('Named diagnostic overlay binding missing')
    return True
