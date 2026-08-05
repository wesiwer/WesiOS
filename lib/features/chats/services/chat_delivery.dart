import '../../../core/sync/sync_endpoint.dart';
import '../models/chat_message.dart';
import '../models/chat_policy.dart';
import '../models/chat_thread.dart';

/// Уедет ли написанное куда-нибудь вообще — и что честно показать человеку.
///
/// **Зачем это отдельный файл.** Значок под своим сообщением — обещание.
/// «Часики» означают «отправляется», две галочки — «дошло». Пока настоящей
/// передачи нет, любое из них было бы враньём, а самое вредное враньё —
/// то, которое выглядит как обычная работа: человек видит вечные часики и
/// решает, что мессенджер сломан, хотя всё идёт по плану.
///
/// Поэтому состояние выбирается один раз, при отправке, и из двух настоящих
/// обстоятельств: есть ли вход на сервер и уезжает ли этот вид чата вообще.
///
/// Спрашиваем именно про вход. Адрес сервера зашит в сборку и есть всегда,
/// так что «адрес указан» перестало быть условием чего бы то ни было.
class ChatDelivery {
  /// Уедет ли переписка этого чата с устройства при нынешних настройках.
  static bool willTravel(ChatThread chat) =>
      ChatEnvelopePolicy.travels(chat.kind) && SyncEndpoint.isConnected;

  /// С каким состоянием рождается новое сообщение.
  static DeliveryState initialFor(ChatThread chat) =>
      willTravel(chat) ? DeliveryState.pending : DeliveryState.local;

  /// Почему переписка остаётся здесь. null — она уедет.
  ///
  /// Показывается в шапке чата, рядом с тем, кто его читает: человек должен
  /// узнавать об этом, когда пишет, а не когда ищет пропавшее сообщение на
  /// втором устройстве.
  static String? whyLocal(ChatThread chat, {bool russian = true}) {
    if (!ChatEnvelopePolicy.travels(chat.kind)) {
      return russian
          ? 'Личная переписка не уходит с устройства'
          : 'Personal chats stay on this device';
    }
    if (!SyncEndpoint.isConnected) {
      return russian
          ? 'Войдите в WesiOS — до этого переписка остаётся на устройстве'
          : 'Sign in to WesiOS — until then this chat stays on this device';
    }
    return null;
  }
}
