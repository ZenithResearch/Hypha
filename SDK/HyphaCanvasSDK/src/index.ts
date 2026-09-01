export type HyphaRepository = {
  id: string;
  name: string;
  requested_ref: string;
  resolved_commit: string | null;
  primary: boolean;
};

export type HyphaAsset = {
  id: string;
  repository_id: string;
  repository_name: string;
  path: string;
  title: string;
  format: string;
  viewer: string;
  source: "remote" | "cached" | "localFallback" | "rebuiltLocal";
  stale: boolean;
};

type Bridge = { postMessage(value: unknown): void };
type Pending = { resolve(value: unknown): void; reject(reason: unknown): void };
const pending = new Map<string, Pending>();

export class HyphaCanvasError extends Error {
  constructor(public readonly code: string, message: string) {
    super(message);
    this.name = "HyphaCanvasError";
  }
}

export class HyphaCanvasClient {
  private readonly bridge: Bridge;

  constructor(bridge = (globalThis as any).webkit?.messageHandlers?.hyphaBridge as Bridge) {
    if (!bridge?.postMessage) throw new HyphaCanvasError("bridge_unavailable", "Hypha canvas bridge is unavailable.");
    this.bridge = bridge;
    (globalThis as any).__hyphaBridgeReceive = (response: any) => {
      const operation = pending.get(response?.id);
      if (!operation) return;
      pending.delete(response.id);
      if (response.ok) operation.resolve(response.result);
      else operation.reject(new HyphaCanvasError(response.error?.code ?? "bridge_error", response.error?.message ?? "Canvas request failed."));
    };
  }

  request<T>(method: string, params: Record<string, unknown> = {}): Promise<T> {
    const id = crypto.randomUUID();
    return new Promise<T>((resolve, reject) => {
      pending.set(id, { resolve: resolve as (value: unknown) => void, reject });
      this.bridge.postMessage({ v: 1, id, method, params });
    });
  }

  roomMetadata() { return this.request<{ name: string; topic: string | null; repository_count: number; asset_count: number }>("room.get_metadata"); }
  repositories() { return this.request<HyphaRepository[]>("repositories.list"); }
  assets(repositoryId?: string, prefix = "") {
    return this.request<HyphaAsset[]>("assets.list", { ...(repositoryId ? { repository_id: repositoryId } : {}), ...(prefix ? { prefix } : {}) });
  }
  assetMetadata(assetId: string) { return this.request<HyphaAsset>("assets.get_metadata", { asset_id: assetId }); }
  assetURL(assetId: string) { return this.request<{ url: string; expires_in_seconds: number }>("assets.get_url", { asset_id: assetId }); }
  layoutState<T = Record<string, unknown>>() { return this.request<T>("layout_state.get"); }
  saveLayoutState(value: unknown) { return this.request<{ saved: true }>("layout_state.set", { value }); }
}

export function viewerURL(assetId: string): string {
  return `hypha-viewer://open/?asset_id=${encodeURIComponent(assetId)}`;
}
