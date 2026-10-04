import { site } from "@/lib/site";

/**
 * Calls the Sova API. The API sleeps when idle and answers with a "waking"
 * page (no CORS headers, so the browser reports a network error) for a few
 * seconds; keep trying until it answers in JSON.
 */
export async function callApi(path: string, init: { method?: "GET" | "POST"; body?: object } = {}, attempts = 15) {
  for (let i = 0; ; i++) {
    try {
      const res = await fetch(`${site.apiUrl}${path}`, {
        method: init.method ?? "GET",
        headers: init.body ? { "Content-Type": "application/json" } : undefined,
        body: init.body ? JSON.stringify(init.body) : undefined,
      });
      if (res.headers.get("content-type")?.includes("json")) {
        const data = await res.json();
        if (!res.ok) throw new ApiError(data?.error?.message ?? "Something went wrong. Please try again.", res.status);
        return data;
      }
    } catch (err) {
      if (err instanceof ApiError) throw err;
      // Waking up, or offline: try again below.
    }
    if (i >= attempts) throw new ApiError("We couldn't reach Sova just now. Please check your connection and try again.", 0);
    await new Promise((r) => setTimeout(r, 2000));
  }
}

export class ApiError extends Error {
  constructor(
    message: string,
    readonly status: number,
  ) {
    super(message);
  }
}
