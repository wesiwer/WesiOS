import '../../../core/sync/sync_endpoint.dart';
import '../models/chat_message.dart';
import '../models/chat_policy.dart';
import '../models/chat_thread.dart';

/// Уедет ли написанное куда-нибудь вообще — и что честно показать человеку.
class ChatDelivery {
  static bool willTravel(ChatThread chat) =>
      ChatEnvelopePolicy.travels(chat.kind) && SyncEndpoint.isConfigured;

  static DeliveryState initialFor(ChatThread chat) =>
      willTravel(chat) ? DeliveryState.pending : DeliveryState.local;

  static String? whyLocal(ChatThread chat, {bool russian = true}) {
    if (!ChatEnvelopePolicy.travels(chat.kind)) {
      return russian
          ? 'Личная переписка не уходит с устройства'
          : 'Personal chats stay on this device';
    }
    if (!SyncEndpoint.isConfigured) {
      return russian
          ? 'Войдите в WesiOS — до этого переписка остаётся на устройстве'
          : 'Sign in to WesiOS — until then this chat stays on this device';
    }
    return null;
  }
}
