import { GetObjectCommand, HeadObjectCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

import type { Config } from "../config.js";

/**
 * Where proof-of-payment photos live. The bucket is private: the API stores
 * photos the app sends it (server to server, so no browser rules apply), and
 * members view them through short-lived signed links.
 */
export interface ProofStorage {
  put(key: string, body: Buffer, contentType: string): Promise<void>;
  /** A link to view the photo, for a few minutes. */
  viewUrl(key: string): Promise<string>;
  exists(key: string): Promise<boolean>;
}

const VIEW_TTL_SECONDS = 300;

export class S3ProofStorage implements ProofStorage {
  private readonly s3: S3Client;

  constructor(
    private readonly bucket: string,
    options: { endpoint: string; region: string; accessKeyId: string; secretAccessKey: string },
  ) {
    this.s3 = new S3Client({
      endpoint: options.endpoint,
      region: options.region,
      credentials: { accessKeyId: options.accessKeyId, secretAccessKey: options.secretAccessKey },
      forcePathStyle: true,
    });
  }

  async put(key: string, body: Buffer, contentType: string) {
    await this.s3.send(new PutObjectCommand({ Bucket: this.bucket, Key: key, Body: body, ContentType: contentType }));
  }

  viewUrl(key: string) {
    return getSignedUrl(this.s3, new GetObjectCommand({ Bucket: this.bucket, Key: key }), { expiresIn: VIEW_TTL_SECONDS });
  }

  async exists(key: string) {
    try {
      await this.s3.send(new HeadObjectCommand({ Bucket: this.bucket, Key: key }));
      return true;
    } catch {
      return false;
    }
  }
}

/** The configured bucket, or null when uploads aren't set up. */
export function createProofStorage(config: Config): ProofStorage | null {
  const { S3_ENDPOINT, S3_REGION, S3_BUCKET, S3_ACCESS_KEY_ID, S3_SECRET_ACCESS_KEY } = config;
  if (!S3_ENDPOINT || !S3_BUCKET || !S3_ACCESS_KEY_ID || !S3_SECRET_ACCESS_KEY) return null;
  return new S3ProofStorage(S3_BUCKET, {
    endpoint: S3_ENDPOINT,
    region: S3_REGION,
    accessKeyId: S3_ACCESS_KEY_ID,
    secretAccessKey: S3_SECRET_ACCESS_KEY,
  });
}

/** The image type from the file's first bytes, or null if it isn't a JPEG, PNG or WebP. */
export function sniffImage(bytes: Buffer): "image/jpeg" | "image/png" | "image/webp" | null {
  if (bytes.length >= 3 && bytes[0] === 0xff && bytes[1] === 0xd8 && bytes[2] === 0xff) return "image/jpeg";
  if (bytes.length >= 8 && bytes.subarray(0, 8).equals(Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]))) {
    return "image/png";
  }
  if (bytes.length >= 12 && bytes.toString("ascii", 0, 4) === "RIFF" && bytes.toString("ascii", 8, 12) === "WEBP") {
    return "image/webp";
  }
  return null;
}
