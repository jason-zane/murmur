/** Shared owner-workspace transport. Every nested scheduling action receives it. */
export type SchedulingRequest = (url: string, method: string, body?: unknown) => Promise<any>;

export const schedulingRequest: SchedulingRequest = async (url, method, body) => {
  const response = await fetch(url, {
    method,
    headers: body === undefined ? undefined : { "Content-Type": "application/json" },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const result = await response.json().catch(() => ({}));
  if (!response.ok) throw new Error(result.error || "Something went wrong. Try again.");
  return result;
};

const unavailablePreviewRequest: SchedulingRequest = async () => {
  throw new Error("Synthetic booking transport is unavailable. No live request was made.");
};

/** A forgotten preview transport must never fall back to an authenticated request. */
export function selectSchedulingRequest(previewMode: boolean, request?: SchedulingRequest): SchedulingRequest {
  return request ?? (previewMode ? unavailablePreviewRequest : schedulingRequest);
}
