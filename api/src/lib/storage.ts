import { GetObjectCommand, HeadObjectCommand, PutBucketCorsCommand, PutObjectCommand, S3Client } from "@aws-sdk/client-s3";
import { getSignedUrl } from "@aws-sdk/s3-request-presigner";

import type { Config } from "../config.js";

/**
 * Where proof-of-payment photos live. The bucket is private: the app uploads
 * straight to it with a short-lived signed PUT link, and members read photos
 * through short-lived signed GET links. Photos never pass through the API.
 */
export interface ProofStorage {
  /** A link the app can PUT exactly this file to, for a few minutes. */
  uploadUrl(key: string, contentType: string, size: number): Promise<string>;
  /** A link to view the photo, for a few minutes. */
  viewUrl(key: string): Promise<string>;
  exists(key: string): Promise<boolean>;
}

const UPLOAD_TTL_SECONDS = 300;
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

  uploadUrl(key: string, contentType: string, size: number) {
    // Content type and length are part of the signature, so the link only accepts this file.
    const command = new PutObjectCommand({ Bucket: this.bucket, Key: key, ContentType: contentType, ContentLength: size });
    return getSignedUrl(this.s3, command, { expiresIn: UPLOAD_TTL_SECONDS });
  }

  viewUrl(key: string) {
    return getSignedUrl(this.s3, new GetObjectCommand({ Bucket: this.bucket, Key: key }), { expiresIn: VIEW_TTL_SECONDS });
  }

  /**
   * Lets the app upload and show photos straight from the browser: allows
   * PUT and GET from the app's own origins (the bucket stays private; links
   * are still signed).
   */
  async allowBrowserUploads(origins: string[]) {
    await this.s3.send(
      new PutBucketCorsCommand({
        Bucket: this.bucket,
        CORSConfiguration: {
          CORSRules: [
            {
              AllowedOrigins: origins,
              AllowedMethods: ["PUT", "GET"],
              AllowedHeaders: ["content-type"],
              MaxAgeSeconds: 3000,
            },
          ],
        },
      }),
    );
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
