const assets = [{
  id: "asset:1111111111111111111111111111111111111111111111111111111111111111",
  repository_id: "investor-deck",
  repository_name: "InvestorDeck",
  path: "slides/deck.pptx",
  title: "Investor deck",
  format: "pptx",
  viewer: "slideshow",
  source: "remote",
  stale: false
}];

globalThis.webkit = {
  messageHandlers: {
    hyphaBridge: {
      postMessage(request) {
        queueMicrotask(() => {
          let result = {};
          if (request.method === "room.get_metadata") {
            result = { name: "Strategy room", topic: "A static SDK preview" };
          } else if (request.method === "repositories.list") {
            result = [{ id: "investor-deck", name: "InvestorDeck", primary: true }];
          } else if (request.method === "assets.list") {
            result = assets;
          } else if (request.method === "assets.get_metadata") {
            result = assets.find((asset) => asset.id === request.params.asset_id) ?? null;
          } else if (request.method === "assets.get_url") {
            result = { url: "hypha-asset://room/preview-only", expires_in_seconds: 300 };
          }
          globalThis.__hyphaBridgeReceive?.({ v: 1, id: request.id, ok: true, result });
        });
      }
    }
  }
};
