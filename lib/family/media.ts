import { BlobNotFoundError, del, head, issueSignedToken, parseStoreIdFromDelegationToken, presignUrl } from "@vercel/blob";
import { FamilyError } from "./household.ts";

// Message audio/video lives in a private Vercel Blob store. Devices never hold a store
// credential: the server signs one short-lived URL for each upload or download.
export type UploadTarget = { url: string; method: "PUT"; headers: Record<string, string>; expiresAt: number };
export interface MediaStore {
  uploadTarget(pathname: string, contentType: string, maximumSizeInBytes: number, validUntil: number): Promise<UploadTarget>;
  downloadURL(pathname: string, validUntil: number): Promise<string>;
  stat(pathname: string): Promise<{ size: number; contentType: string } | null>;
  remove(pathnames: string[]): Promise<void>;
}

// The Blob SDK sends these headers with a presigned PUT (API version 12 in @vercel/blob 2.8);
// the apps copy them verbatim, so a protocol change only needs a server update.
const blobAPIVersion = "12";

export function blobMediaStore(): MediaStore {
  const token = process.env.BLOB_READ_WRITE_TOKEN;
  if (!token) throw new FamilyError("Messages aren't set up on this server yet.", 503);
  return {
    async uploadTarget(pathname, contentType, maximumSizeInBytes, validUntil) {
      const signed = await issueSignedToken({ token, pathname, operations: ["put"], validUntil: validUntil * 1000, allowedContentTypes: [contentType], maximumSizeInBytes });
      const { presignedUrl } = await presignUrl(signed, { operation: "put", pathname, access: "private", validUntil: validUntil * 1000, allowedContentTypes: [contentType], maximumSizeInBytes, allowOverwrite: false, addRandomSuffix: false });
      return { url: presignedUrl, method: "PUT", expiresAt: validUntil, headers: {
        "Content-Type": contentType, "x-content-type": contentType, "x-vercel-blob-access": "private",
        "x-api-version": blobAPIVersion, "x-vercel-blob-store-id": parseStoreIdFromDelegationToken(signed.delegationToken),
      } };
    },
    async downloadURL(pathname, validUntil) {
      const signed = await issueSignedToken({ token, pathname, operations: ["get"], validUntil: validUntil * 1000 });
      return (await presignUrl(signed, { operation: "get", pathname, access: "private", validUntil: validUntil * 1000 })).presignedUrl;
    },
    async stat(pathname) {
      try { const blob = await head(pathname, { token }); return { size: blob.size, contentType: blob.contentType }; }
      catch (error) { if (error instanceof BlobNotFoundError) return null; throw error; }
    },
    async remove(pathnames) { if (pathnames.length) await del(pathnames, { token }); },
  };
}
