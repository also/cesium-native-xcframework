// macOS smoke test for CesiumNative.xcframework: links the library, streams
// the public Cesium sample tileset over NSURLSession, and reports whether a
// tile reached the loaded state. Exit status 0 only if one did.

#import <Foundation/Foundation.h>

#include <Cesium3DTilesContent/registerAllTileContentTypes.h>
#include <Cesium3DTilesSelection/IPrepareRendererResources.h>
#include <Cesium3DTilesSelection/Tile.h>
#include <Cesium3DTilesSelection/TileLoadResult.h>
#include <Cesium3DTilesSelection/Tileset.h>
#include <Cesium3DTilesSelection/TilesetExternals.h>
#include <Cesium3DTilesSelection/TilesetOptions.h>
#include <Cesium3DTilesSelection/ViewState.h>
#include <Cesium3DTilesSelection/ViewUpdateResult.h>
#include <CesiumAsync/AsyncSystem.h>
#include <CesiumAsync/IAssetAccessor.h>
#include <CesiumAsync/IAssetRequest.h>
#include <CesiumAsync/IAssetResponse.h>
#include <CesiumAsync/ITaskProcessor.h>
#include <CesiumGltf/Model.h>
#include <CesiumRasterOverlays/RasterOverlayTile.h>
#include <CesiumUtility/CreditSystem.h>

#include <glm/glm.hpp>

#include <atomic>
#include <cstdio>
#include <memory>

using namespace Cesium3DTilesSelection;
using namespace CesiumAsync;

namespace {

class GCDTaskProcessor final : public ITaskProcessor {
public:
  void startTask(std::function<void()> f) override {
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
      f();
    });
  }
};

class SessionResponse final : public IAssetResponse {
public:
  uint16_t status = 0;
  std::string type;
  HttpHeaders responseHeaders;
  std::vector<std::byte> body;

  uint16_t statusCode() const override { return status; }
  std::string contentType() const override { return type; }
  const HttpHeaders& headers() const override { return responseHeaders; }
  std::span<const std::byte> data() const override { return body; }
};

class SessionRequest final : public IAssetRequest {
public:
  SessionRequest(std::string method, std::string url, HttpHeaders headers)
      : _method(std::move(method)), _url(std::move(url)),
        _headers(std::move(headers)) {}

  const std::string& method() const override { return _method; }
  const std::string& url() const override { return _url; }
  const HttpHeaders& headers() const override { return _headers; }
  const IAssetResponse* response() const override { return _response.get(); }

  std::unique_ptr<SessionResponse> _response;

private:
  std::string _method;
  std::string _url;
  HttpHeaders _headers;
};

class URLSessionAssetAccessor final : public IAssetAccessor {
public:
  URLSessionAssetAccessor()
      : _session([NSURLSession
            sessionWithConfiguration:NSURLSessionConfiguration
                                         .defaultSessionConfiguration]) {}

  Future<std::shared_ptr<IAssetRequest>>
  get(const AsyncSystem& asyncSystem,
      const std::string& url,
      const std::vector<THeader>& headers) override {
    return request(asyncSystem, "GET", url, headers, {});
  }

  Future<std::shared_ptr<IAssetRequest>> request(
      const AsyncSystem& asyncSystem,
      const std::string& verb,
      const std::string& url,
      const std::vector<THeader>& headers,
      const std::span<const std::byte>& contentPayload) override {
    auto promise = asyncSystem.createPromise<std::shared_ptr<IAssetRequest>>();
    NSURL* nsURL = [NSURL URLWithString:@(url.c_str())];
    if (!nsURL) {
      promise.reject(std::runtime_error("Invalid URL: " + url));
      return promise.getFuture();
    }
    NSMutableURLRequest* req = [NSMutableURLRequest requestWithURL:nsURL];
    req.HTTPMethod = @(verb.c_str());
    HttpHeaders requestHeaders;
    for (const THeader& header : headers) {
      requestHeaders[header.first] = header.second;
      [req setValue:@(header.second.c_str())
          forHTTPHeaderField:@(header.first.c_str())];
    }
    if (!contentPayload.empty()) {
      req.HTTPBody = [NSData dataWithBytes:contentPayload.data()
                                    length:contentPayload.size()];
    }
    auto pRequest =
        std::make_shared<SessionRequest>(verb, url, std::move(requestHeaders));
    [[_session dataTaskWithRequest:req
                 completionHandler:^(NSData* data,
                                     NSURLResponse* response,
                                     NSError* error) {
                   if (error) {
                     promise.reject(std::runtime_error(
                         error.localizedDescription.UTF8String));
                     return;
                   }
                   auto pResponse = std::make_unique<SessionResponse>();
                   if ([response isKindOfClass:NSHTTPURLResponse.class]) {
                     NSHTTPURLResponse* http = (NSHTTPURLResponse*)response;
                     pResponse->status = static_cast<uint16_t>(http.statusCode);
                     for (id key in http.allHeaderFields) {
                       pResponse->responseHeaders[[key description].UTF8String] =
                           [http.allHeaderFields[key] description].UTF8String;
                     }
                   }
                   if (response.MIMEType) {
                     pResponse->type = response.MIMEType.UTF8String;
                   }
                   const std::byte* bytes =
                       static_cast<const std::byte*>(data.bytes);
                   pResponse->body.assign(bytes, bytes + data.length);
                   pRequest->_response = std::move(pResponse);
                   promise.resolve(pRequest);
                 }] resume];
    return promise.getFuture();
  }

  void tick() noexcept override {}

private:
  NSURLSession* _session;
};

// Counts glTF models that decoded successfully; no renderer resources.
class CountingPrepareRendererResources final : public IPrepareRendererResources {
public:
  std::atomic<int> models{0};

  Future<TileLoadResultAndRenderResources> prepareInLoadThread(
      const AsyncSystem& asyncSystem,
      TileLoadResult&& tileLoadResult,
      const glm::dmat4&,
      const std::any&) override {
    if (std::holds_alternative<CesiumGltf::Model>(tileLoadResult.contentKind)) {
      ++models;
    }
    return asyncSystem.createResolvedFuture(
        TileLoadResultAndRenderResources{std::move(tileLoadResult), nullptr});
  }
  void* prepareInMainThread(Tile&, void*) override { return nullptr; }
  void free(Tile&, void*, void*) noexcept override {}
  void* prepareRasterInLoadThread(CesiumImage::ImageAsset&, const std::any&) override {
    return nullptr;
  }
  void* prepareRasterInMainThread(CesiumRasterOverlays::RasterOverlayTile&, void*) override {
    return nullptr;
  }
  void freeRaster(const CesiumRasterOverlays::RasterOverlayTile&, void*, void*) noexcept override {}
  void attachRasterInMainThread(const Tile&, int32_t, const CesiumRasterOverlays::RasterOverlayTile&, void*, const glm::dvec2&, const glm::dvec2&) override {}
  void detachRasterInMainThread(const Tile&, int32_t, const CesiumRasterOverlays::RasterOverlayTile&, void*) noexcept override {}
};

} // namespace

int main(int argc, char** argv) {
  @autoreleasepool {
    const std::string url =
        argc > 1 ? argv[1]
                 : "https://raw.githubusercontent.com/CesiumGS/3d-tiles-samples/"
                   "main/1.0/TilesetWithDiscreteLOD/tileset.json";

    Cesium3DTilesContent::registerAllTileContentTypes();

    AsyncSystem asyncSystem(std::make_shared<GCDTaskProcessor>());
    auto resources = std::make_shared<CountingPrepareRendererResources>();
    TilesetExternals externals{
        .pAssetAccessor = std::make_shared<URLSessionAssetAccessor>(),
        .pPrepareRendererResources = resources,
        .asyncSystem = asyncSystem,
        .pCreditSystem = std::make_shared<CesiumUtility::CreditSystem>(),
    };
    TilesetOptions options;
    options.loadErrorCallback = [](const TilesetLoadFailureDetails& d) {
      std::fprintf(stderr, "load error (HTTP %d): %s\n", int(d.statusCode),
                   d.message.c_str());
    };
    Tileset tileset(externals, url, options);

    int loaded = 0;
    for (int i = 0; i < 600 && loaded == 0; ++i) {
      // Aim at the root bounding sphere once it exists, from 2 radii away.
      glm::dvec3 center(6378137.0 * 2.0, 0, 0);
      double radius = 100.0;
      if (const Tile* root = tileset.getRootTile()) {
        auto sphere = Cesium3DTilesSelection::getBoundingVolumeCenter(
            root->getBoundingVolume());
        center = sphere;
        radius = 100.0;
      }
      glm::dvec3 up = glm::normalize(center);
      glm::dvec3 position = center + up * radius * 4.0;
      glm::dvec3 direction = glm::normalize(center - position);
      glm::dvec3 side = glm::normalize(glm::cross(direction, glm::dvec3(0, 0, 1)));
      glm::dvec3 camUp = glm::normalize(glm::cross(side, direction));
      ViewState view(position, direction, camUp, glm::dvec2(1024, 1024), 1.0, 1.0);
      tileset.updateViewGroup(tileset.getDefaultViewGroup(), {view}, 0.05f);
      tileset.loadTiles();
      asyncSystem.dispatchMainThreadTasks();

      if (const Tile* root = tileset.getRootTile()) {
        std::vector<const Tile*> stack{root};
        loaded = 0;
        while (!stack.empty()) {
          const Tile* t = stack.back();
          stack.pop_back();
          if (t->getState() == TileLoadState::Done && t->getContent().isRenderContent()) {
            ++loaded;
          }
          for (const Tile& c : t->getChildren()) stack.push_back(&c);
        }
      }
      [NSThread sleepForTimeInterval:0.1];
    }

    std::printf("root tile: %s\nloaded render tiles: %d (glTF models decoded: %d)\n",
                tileset.getRootTile() ? "yes" : "no", loaded, resources->models.load());
    std::printf("%s\n", loaded > 0 ? "SMOKE PASS" : "SMOKE FAIL");
    return loaded > 0 ? 0 : 1;
  }
}
