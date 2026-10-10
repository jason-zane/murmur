// The Mac app is published as a disk image on GitHub Releases — the same place
// `UpdateCheck` in the app asks about newer versions. Resolving the asset here means the
// download button never needs editing when a release is cut.
const repository = "jason-zane/murmur";

export const releasesPage = `https://github.com/${repository}/releases/latest`;

export type MacRelease = {
  // null when GitHub couldn't be reached — the page then sends people to the release
  // listing rather than claiming a version it hasn't confirmed.
  version: string | null;
  // The .dmg, or the release listing as a fallback. Always safe to link.
  download: string;
  size: number | null;
};

// Cached for fifteen minutes. Unauthenticated GitHub allows 60 requests an hour per IP and
// Vercel's egress addresses are shared, so an uncached fetch per visit would rate-limit.
export async function latestMac(): Promise<MacRelease> {
  const unknown: MacRelease = {
    version: null,
    download: releasesPage,
    size: null,
  };
  try {
    const response = await fetch(
      `https://api.github.com/repos/${repository}/releases/latest`,
      {
        headers: { Accept: "application/vnd.github+json" },
        next: { revalidate: 900 },
      },
    );
    if (!response.ok) return unknown;
    const release = await response.json();
    const asset = (release?.assets ?? []).find(
      (candidate: { name?: string }) =>
        typeof candidate?.name === "string" && candidate.name.endsWith(".dmg"),
    );
    if (typeof asset?.browser_download_url !== "string") return unknown;
    return {
      version: String(release.tag_name ?? "").replace(/^v/, "") || null,
      download: asset.browser_download_url,
      size: typeof asset.size === "number" ? asset.size : null,
    };
  } catch {
    return unknown;
  }
}

export const megabytes = (size: number | null) =>
  size ? `${Math.round(size / 1_000_000)} MB` : null;
