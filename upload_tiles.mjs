import { S3Client, ListObjectsV2Command, PutObjectCommand } from "@aws-sdk/client-s3";
import { readdir, readFile, stat } from "fs/promises";
import { join } from "path";
import { homedir } from "os";

const TILES_DIR = join(homedir(), "EcoMap_tiles");
const BUCKET = "ecomap-tiles";
const ENDPOINT = "https://eef5e5e69a6c2c544fbc9cd3da5a73e0.r2.cloudflarestorage.com";

const s3 = new S3Client({
  endpoint: ENDPOINT,
  region: "auto",
  credentials: {
    accessKeyId: "b6ecbf4404f7e8a41ceff15eb1b4b9cc",
    secretAccessKey: "3456bc5d01369c08c18d02045a6e60022a76e134b4422c77511f8f717fbb44b9",
  },
});

// List existing keys
console.log("Lecture des fichiers existants sur R2...");
const existing = new Set();
let token;
do {
  const resp = await s3.send(new ListObjectsV2Command({ Bucket: BUCKET, ContinuationToken: token }));
  for (const obj of resp.Contents ?? []) existing.add(obj.Key);
  token = resp.NextContinuationToken;
} while (token);
console.log(`${existing.size} fichiers déjà sur R2`);

const files = (await readdir(TILES_DIR)).filter(f => f.endsWith(".gz"));
const toUpload = files.filter(f => !existing.has(f));
console.log(`${toUpload.length} fichiers à uploader sur ${files.length} total\n`);

let done = 0;
for (const fname of toUpload) {
  const path = join(TILES_DIR, fname);
  const body = await readFile(path);
  await s3.send(new PutObjectCommand({
    Bucket: BUCKET,
    Key: fname,
    Body: body,
    ContentType: "application/gzip",
  }));
  done++;
  process.stdout.write(`\r[${done}/${toUpload.length}] ${fname}    `);
}

console.log(`\n\n=== TERMINÉ — ${toUpload.length} fichiers uploadés ===`);
