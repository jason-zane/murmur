/** Only the latest calendar request may update the guest's open times. */
export class AvailabilityRequest {
  private current?: AbortController;

  cancel() {
    this.current?.abort();
    this.current = undefined;
  }

  async load(url: string): Promise<{ slots: string[] } | { error: string } | null> {
    this.cancel();
    const request = new AbortController();
    this.current = request;
    try {
      const response = await fetch(url, { signal: request.signal });
      const body = await response.json();
      if (!response.ok) throw new Error(body.error || "Open times couldn’t be loaded. Try again.");
      if (!Array.isArray(body.slots) || !body.slots.every((slot: unknown) => typeof slot === "string" && Number.isFinite(Date.parse(slot)))) {
        throw new Error("Open times couldn’t be loaded. Try again.");
      }
      return this.current === request && !request.signal.aborted ? { slots: body.slots } : null;
    } catch (error) {
      if (this.current !== request || request.signal.aborted) return null;
      return { error: error instanceof Error ? error.message : "Open times couldn’t be loaded. Try again." };
    }
  }
}
