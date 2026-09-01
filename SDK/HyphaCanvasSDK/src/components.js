import { HyphaCanvasClient, viewerURL } from "./index.js";

const client = () => new HyphaCanvasClient();

class HyphaRoomHeader extends HTMLElement {
  async connectedCallback() {
    this.setAttribute("role", "banner");
    try {
      const room = await client().roomMetadata();
      this.replaceChildren(Object.assign(document.createElement("h1"), { textContent: room.name }));
      if (room.topic) this.append(Object.assign(document.createElement("p"), { textContent: room.topic }));
    } catch { this.textContent = "Room unavailable"; }
  }
}

class HyphaRepositoryStatus extends HTMLElement {
  connectedCallback() {
    this.setAttribute("role", "status");
    const name = this.getAttribute("name") ?? "Repository";
    const state = this.getAttribute("state") ?? "available";
    this.textContent = `${name} — ${state}`;
  }
}

class HyphaAssetCard extends HTMLElement {
  set asset(value) { this._asset = value; this.render(); }
  get asset() { return this._asset; }
  connectedCallback() { this.render(); }
  render() {
    if (!this._asset) return;
    const link = document.createElement("a");
    link.href = viewerURL(this._asset.id);
    link.className = "hypha-asset-card__link";
    link.append(
      Object.assign(document.createElement("strong"), { textContent: this._asset.title }),
      Object.assign(document.createElement("code"), { textContent: this._asset.path }),
      Object.assign(document.createElement("span"), { textContent: `${this._asset.format.toUpperCase()} · ${this._asset.source}` })
    );
    this.replaceChildren(link);
  }
}

class HyphaAssetGallery extends HTMLElement {
  set assets(value) { this._assets = Array.isArray(value) ? value : []; this.render(); }
  get assets() { return this._assets ?? []; }
  connectedCallback() {
    this.setAttribute("role", "list");
    if (this.hasAttribute("repository-id")) this.load();
    else this.render();
  }
  async load() {
    try { this.assets = await client().assets(this.getAttribute("repository-id") ?? undefined, this.getAttribute("prefix") ?? ""); }
    catch { this.textContent = "Assets unavailable"; }
  }
  render() {
    const fragment = document.createDocumentFragment();
    for (const asset of this.assets) {
      const card = document.createElement("hypha-asset-card");
      card.setAttribute("role", "listitem");
      card.asset = asset;
      fragment.append(card);
    }
    this.replaceChildren(fragment);
  }
}

class HyphaViewerLink extends HTMLElement {
  connectedCallback() {
    const id = this.getAttribute("asset-id");
    if (!id) return;
    const link = document.createElement("a");
    link.href = viewerURL(id);
    link.textContent = this.textContent?.trim() || "Open Asset";
    this.replaceChildren(link);
  }
}

for (const [name, constructor] of [
  ["hypha-room-header", HyphaRoomHeader],
  ["hypha-repository-status", HyphaRepositoryStatus],
  ["hypha-asset-gallery", HyphaAssetGallery],
  ["hypha-asset-card", HyphaAssetCard],
  ["hypha-viewer-link", HyphaViewerLink]
]) {
  if (!customElements.get(name)) customElements.define(name, constructor);
}

export { HyphaRoomHeader, HyphaRepositoryStatus, HyphaAssetGallery, HyphaAssetCard, HyphaViewerLink };
