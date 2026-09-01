const pending = new Map();

function uuid() {
  if (globalThis.crypto?.randomUUID) return globalThis.crypto.randomUUID();
  const bytes = new Uint8Array(16);
  globalThis.crypto.getRandomValues(bytes);
  bytes[6] = (bytes[6] & 0x0f) | 0x40;
  bytes[8] = (bytes[8] & 0x3f) | 0x80;
  return [...bytes].map((value, index) => `${index === 4 || index === 6 || index === 8 || index === 10 ? "-" : ""}${value.toString(16).padStart(2, "0")}`).join("");
}

export class HyphaCanvasError extends Error {
  constructor(code, message) {
    super(message);
    this.name = "HyphaCanvasError";
    this.code = code;
  }
}

export class HyphaCanvasClient {
  constructor(bridge = globalThis.webkit?.messageHandlers?.hyphaBridge) {
    if (!bridge?.postMessage) throw new HyphaCanvasError("bridge_unavailable", "Hypha canvas bridge is unavailable.");
    this.bridge = bridge;
    globalThis.__hyphaBridgeReceive = (response) => {
      const operation = pending.get(response?.id);
      if (!operation) return;
      pending.delete(response.id);
      if (response.ok) operation.resolve(response.result);
      else operation.reject(new HyphaCanvasError(response.error?.code ?? "bridge_error", response.error?.message ?? "Canvas request failed."));
    };
  }

  request(method, params = {}) {
    const id = uuid();
    return new Promise((resolve, reject) => {
      pending.set(id, { resolve, reject });
      try {
        this.bridge.postMessage({ v: 1, id, method, params });
      } catch (error) {
        pending.delete(id);
        reject(error);
      }
    });
  }

  roomMetadata() { return this.request("room.get_metadata"); }
  repositories() { return this.request("repositories.list"); }
  assets(repositoryId = null, prefix = "") {
    return this.request("assets.list", {
      ...(repositoryId ? { repository_id: repositoryId } : {}),
      ...(prefix ? { prefix } : {})
    });
  }
  assetMetadata(assetId) { return this.request("assets.get_metadata", { asset_id: assetId }); }
  assetURL(assetId) { return this.request("assets.get_url", { asset_id: assetId }); }
  layoutState() { return this.request("layout_state.get"); }
  saveLayoutState(value) { return this.request("layout_state.set", { value }); }
}

export function viewerURL(assetId) {
  return `hypha-viewer://open/?asset_id=${encodeURIComponent(assetId)}`;
}

export const hypha = new Proxy({}, {
  get(_target, property) {
    const client = new HyphaCanvasClient();
    const value = client[property];
    return typeof value === "function" ? value.bind(client) : value;
  }
});
