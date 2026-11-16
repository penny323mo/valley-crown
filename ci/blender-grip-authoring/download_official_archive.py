#!/usr/bin/env python3
"""Fixed official HTTPS download only; no extraction or executable launch."""
import argparse,hashlib,json,time,urllib.request
from pathlib import Path
from run_authoring import ARCHIVE_URL,ARCHIVE_SHA,safe_path,p
CHECKSUM_URL='https://download.blender.org/release/Blender4.3/blender-4.3.2.sha256'
class NoRedirect(urllib.request.HTTPRedirectHandler):
    def redirect_request(self,*args,**kwargs):return None

def download(url,destination,maximum,started):
    opener=urllib.request.build_opener(NoRedirect())
    with opener.open(urllib.request.Request(url,headers={'User-Agent':'valley-crown-tool-provenance'}),timeout=30) as response:
        p.require(response.status==200 and response.geturl()==url,'Official origin/response mismatch')
        if response.headers.get('Content-Length'):p.require(int(response.headers['Content-Length'])<=maximum,'Download too large')
        size=0
        with destination.open('xb') as stream:
            while True:
                p.require(time.monotonic()-started<=115,'Download time budget')
                chunk=response.read(1<<20)
                if not chunk:break
                size+=len(chunk);p.require(size<=maximum,'Download too large');stream.write(chunk)
    return size

def run(destination):
    destination=safe_path(destination);p.require(not destination.exists(),'Fresh download root required');destination.mkdir(mode=0o700)
    started=time.monotonic();checksum=destination/'blender-4.3.2.sha256'
    download(CHECKSUM_URL,checksum,64<<10,started)
    matches=[line.split() for line in checksum.read_text().splitlines() if line.split() and line.split()[-1]=='blender-4.3.2-linux-x64.tar.xz']
    p.require(matches==[[ARCHIVE_SHA,'blender-4.3.2-linux-x64.tar.xz']],'Official checksum disagreement')
    archive=destination/'blender-4.3.2-linux-x64.tar.xz';size=download(ARCHIVE_URL,archive,512<<20,started)
    p.require(p.digest(archive)==ARCHIVE_SHA,'Archive hash mismatch')
    receipt={'schema':'vc-official-blender-download-v1','archive_url':ARCHIVE_URL,'archive_sha256':ARCHIVE_SHA,'archive_bytes':size,'checksum_url':CHECKSUM_URL,'checksum_sha256':p.digest(checksum),'redirects':0,'reviewed_for_execution':False,'blender_launched':False}
    (destination/'download-receipt.json').write_text(json.dumps(receipt,indent=2)+'\n')
if __name__=='__main__':
    parser=argparse.ArgumentParser(allow_abbrev=False);parser.add_argument('--destination',required=True,type=Path);run(parser.parse_args().destination)
