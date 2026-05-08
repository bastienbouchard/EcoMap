"""Upload EcoMap tiles to R2 using boto3 with SSL verification disabled."""
import os
import boto3
from botocore.config import Config
import urllib3
urllib3.disable_warnings()

TILES_DIR = os.path.expanduser("~/EcoMap_tiles")
BUCKET = "ecomap-tiles"
ENDPOINT = "https://eef5e5e69a6c2c544fbc9cd3da5a73e0.r2.cloudflarestorage.com"

session = boto3.session.Session()
s3 = session.client(
    "s3",
    endpoint_url=ENDPOINT,
    aws_access_key_id="b6ecbf4404f7e8a41ceff15eb1b4b9cc",
    aws_secret_access_key="3456bc5d01369c08c18d02045a6e60022a76e134b4422c77511f8f717fbb44b9",
    config=Config(signature_version="s3v4"),
    verify=False,
)

# List existing keys to skip already uploaded
print("Lecture des fichiers existants sur R2...", flush=True)
existing = set()
paginator = s3.get_paginator("list_objects_v2")
for page in paginator.paginate(Bucket=BUCKET):
    for obj in page.get("Contents", []):
        existing.add(obj["Key"])
print(f"{len(existing)} fichiers déjà sur R2", flush=True)

files = [f for f in os.listdir(TILES_DIR) if f.endswith(".gz")]
to_upload = [f for f in files if f not in existing]
print(f"{len(to_upload)} fichiers à uploader sur {len(files)} total\n", flush=True)

for i, fname in enumerate(to_upload, 1):
    path = os.path.join(TILES_DIR, fname)
    s3.upload_file(
        path, BUCKET, fname,
        ExtraArgs={"ContentType": "application/gzip"},
    )
    print(f"[{i}/{len(to_upload)}] {fname}", flush=True)

print(f"\n=== TERMINÉ — {len(to_upload)} fichiers uploadés ===")
