import type { HyphaAsset } from "./index.js";

export class HyphaRoomHeader extends HTMLElement {}
export class HyphaRepositoryStatus extends HTMLElement {}
export class HyphaAssetGallery extends HTMLElement { assets: HyphaAsset[]; }
export class HyphaAssetCard extends HTMLElement { asset?: HyphaAsset; }
export class HyphaViewerLink extends HTMLElement {}

declare global {
  interface HTMLElementTagNameMap {
    "hypha-room-header": HyphaRoomHeader;
    "hypha-repository-status": HyphaRepositoryStatus;
    "hypha-asset-gallery": HyphaAssetGallery;
    "hypha-asset-card": HyphaAssetCard;
    "hypha-viewer-link": HyphaViewerLink;
  }
}
