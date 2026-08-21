#pragma once

#include <cstdint>
#include <functional>
#include <optional>
#include <string>
#include <vector>

namespace wesi_aero {

enum class TunnelStatus {
  kDisconnected,
  kConnecting,
  kConnected,
  kDisconnecting,
  kError,
};

struct RoutingRule {
  std::string kind;
  std::string value;
};

struct TunnelRequest {
  std::string node_id;
  std::string protocol;
  std::string split_mode;
  bool kill_switch = true;
  std::vector<RoutingRule> rules;
};

struct TunnelEvent {
  TunnelStatus status = TunnelStatus::kDisconnected;
  std::string protocol;
  std::string node_id;
  std::uint64_t download_bps = 0;
  std::uint64_t upload_bps = 0;
  std::uint64_t downloaded_bytes = 0;
  std::uint64_t uploaded_bytes = 0;
  std::optional<std::uint32_t> ping_ms;
  std::string connected_at_iso8601;
  std::string error_code;
};

// Implement this interface inside an elevated Windows service. The Flutter
// process remains unprivileged and communicates through a mutually
// authenticated local IPC channel. The service owns Wintun/WFP lifecycle and
// restores filters after crashes before allowing normal traffic.
class GatewayHost {
 public:
  using Completion = std::function<void(std::optional<std::string> error)>;
  using EventSink = std::function<void(const TunnelEvent&)>;

  virtual ~GatewayHost() = default;
  virtual void Connect(const TunnelRequest& request, Completion completion) = 0;
  virtual void Disconnect(Completion completion) = 0;
  virtual void SetEventSink(EventSink sink) = 0;
};

}  // namespace wesi_aero
