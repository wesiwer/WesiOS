import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import '../models/admin_models.dart';
import '../services/admin_api.dart';
import '../services/admin_secret_store.dart';

class AdminController extends ChangeNotifier {
  AdminController({AdminSecretStore? secretStore})
      : _secretStore = secretStore ?? AdminSecretStore();

  final AdminSecretStore _secretStore;
  AdminApi _api = DemoAdminApi();
  Timer? _refreshTimer;

  AdminSnapshot? snapshot;
  Map<String, dynamic> paymentSecrets = const {};
  ThemeMode themeMode = ThemeMode.light;
  int navigationIndex = 0;
  bool loading = true;
  bool busy = false;
  String? error;
  String? remoteUrl;

  bool get isDemo => _api.isDemo;

  Future<void> initialize() async {
    final (url, token) = await _secretStore.readConnection();
    if (url != null && token != null) {
      try {
        _api.close();
        _api = RemoteAdminApi(Uri.parse(url), token);
        remoteUrl = url;
      } catch (_) {
        _api = DemoAdminApi();
      }
    }
    await refresh(showLoading: true);
    _refreshTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => unawaited(refresh()),
    );
  }

  Future<void> refresh({bool showLoading = false}) async {
    if (showLoading) {
      loading = true;
      notifyListeners();
    }
    try {
      snapshot = await _api.fetchSnapshot();
      paymentSecrets = await _api.paymentSecretStatus();
      error = null;
    } catch (value) {
      error = _message(value);
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<void> connectRemote(String url, String token) async {
    busy = true;
    error = null;
    notifyListeners();
    final previous = _api;
    try {
      final next = RemoteAdminApi(Uri.parse(url.trim()), token.trim());
      final nextSnapshot = await next.fetchSnapshot();
      final secrets = await next.paymentSecretStatus();
      _api = next;
      previous.close();
      snapshot = nextSnapshot;
      paymentSecrets = secrets;
      remoteUrl = url.trim();
      await _secretStore.saveConnection(url.trim(), token.trim());
    } catch (value) {
      error = _message(value);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<void> useDemo() async {
    _api.close();
    _api = DemoAdminApi();
    remoteUrl = null;
    await _secretStore.clearConnection();
    await refresh(showLoading: true);
  }

  void selectNavigation(int value) {
    if (value == navigationIndex) return;
    navigationIndex = value;
    notifyListeners();
  }

  void toggleTheme() {
    themeMode = themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }

  Future<void> upsertServer(Map<String, dynamic> value, {String? id}) =>
      _mutate(() => _api.upsertServer(value, id: id));

  Future<void> deleteServer(String id) =>
      _mutate(() => _api.deleteServer(id));

  Future<void> upsertPlan(Map<String, dynamic> value, {String? id}) =>
      _mutate(() => _api.upsertPlan(value, id: id));

  Future<String> generateLicense({
    required String? planId,
    required String ipMode,
    required int deviceLimit,
    required int durationDays,
    required String note,
  }) async {
    return _mutateWithResult(() => _api.generateLicense(
          planId: planId,
          ipMode: ipMode,
          deviceLimit: deviceLimit,
          durationDays: durationDays,
          note: note,
        ));
  }

  Future<String> revealLicenseKey(String id) => _api.revealLicenseKey(id);

  Future<void> revokeLicense(String id) =>
      _mutate(() => _api.revokeLicense(id));

  Future<void> confirmMockPayment(String id) =>
      _mutate(() => _api.confirmMockPayment(id));

  Future<void> reconcilePayment(String id) =>
      _mutate(() => _api.reconcilePayment(id));

  Future<void> updatePaymentSetting({
    required String provider,
    required bool enabled,
    required bool testMode,
    required String label,
  }) =>
      _mutate(() => _api.updatePaymentSetting(
            provider: provider,
            enabled: enabled,
            testMode: testMode,
            label: label,
          ));

  Future<void> _mutate(Future<void> Function() action) async {
    await _mutateWithResult<void>(action);
  }

  Future<T> _mutateWithResult<T>(Future<T> Function() action) async {
    busy = true;
    error = null;
    notifyListeners();
    try {
      final result = await action();
      snapshot = await _api.fetchSnapshot();
      return result;
    } catch (value) {
      error = _message(value);
      rethrow;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  String _message(Object value) {
    if (value is AdminApiException) return value.message;
    if (value is SocketException || value is TimeoutException) {
      return 'Admin API недоступен. Проверьте адрес и TLS.';
    }
    if (value is ArgumentError) return value.message?.toString() ?? value.toString();
    return 'Не удалось выполнить операцию.';
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _api.close();
    super.dispose();
  }
}
