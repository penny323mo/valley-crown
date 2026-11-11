"""Fixed official engine preparation only; no engine launch."""
from pathlib import Path
import sys
import diagnostic_policy as d
import official_download as download
from prepare_diagnostic_export import ENGINE_SHA
work=Path(sys.argv[1]).resolve();d.admitted()
d.need((work/'export-lock.json').is_file(),'Source preparation required')
download.download(download.ENGINE_URL,work/'engine.zip')
download.safe_extract(work/'engine.zip',{download.ENGINE_NAME:ENGINE_SHA},work/'engine',max_total=256*1024*1024,max_member=256*1024*1024)
(work/'engine'/download.ENGINE_NAME).chmod(0o755)
print('Pinned official engine prepared; not launched')
