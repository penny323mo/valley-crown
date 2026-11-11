"""Pure binding preparation; never enables execution. Run before independent review."""
import argparse,json
from pathlib import Path
import diagnostic_policy as d
from prepare_diagnostic_export import overlay_inventory,ROOT,dump
if __name__=='__main__':
    p=argparse.ArgumentParser();p.add_argument('--overlay',type=Path,required=True);a=p.parse_args()
    files=overlay_inventory(a.overlay.resolve());d.need(set(files)==d.NAMES,'Only exact two diagnostic overlay files permitted')
    dump(ROOT/'overlay-binding.json',dict(bound=True,execution_approved=False,files=files,status='Bound bytes; independent exact review and execution approval pending'))
    print(json.dumps(files,sort_keys=True))
