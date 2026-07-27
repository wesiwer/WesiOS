import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// Сервис для работы с финансовыми данными пользователя в Firestore.
/// 
/// Схема:
/// ```
/// users/{uid}/finance/account {
///   currentBalance: double,
///   currency: string (default: 'USD'),
///   lastUpdated: timestamp,
///   createdAt: timestamp,
/// }
/// ```
class FinanceFirestoreService {
  final FirebaseFirestore _firestore;
  final FirebaseAuth _auth;

  FinanceFirestoreService({
    FirebaseFirestore? firestore,
    FirebaseAuth? auth,
  })  : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  String? get _uid => _auth.currentUser?.uid;

  DocumentReference<Map<String, dynamic>> get _accountRef {
    final uid = _uid;
    if (uid == null) throw Exception('User not authenticated');
    return _firestore.collection('users').doc(uid).collection('finance').doc('account');
  }

  /// Получить или создать аккаунт с начальным балансом.
  /// Если документ не существует — создаёт его с currentBalance = 0.0
  Future<Map<String, dynamic>> getOrCreateAccount({double initialBalance = 0.0}) async {
    final doc = await _accountRef.get();

    if (doc.exists) {
      return doc.data()!;
    }

    final now = FieldValue.serverTimestamp();
    final data = {
      'currentBalance': initialBalance,
      'currency': 'USD',
      'lastUpdated': now,
      'createdAt': now,
    };

    await _accountRef.set(data);
    return {
      'currentBalance': initialBalance,
      'currency': 'USD',
      'lastUpdated': DateTime.now(),
      'createdAt': DateTime.now(),
    };
  }

  /// Получить текущий баланс
  Future<double> getCurrentBalance() async {
    final doc = await _accountRef.get();
    if (!doc.exists) {
      await getOrCreateAccount();
      return 0.0;
    }
    return (doc.data()?['currentBalance'] as num?)?.toDouble() ?? 0.0;
  }

  /// Обновить баланс (increment/decrement)
  Future<void> updateBalance(double delta) async {
    await _accountRef.update({
      'currentBalance': FieldValue.increment(delta),
      'lastUpdated': FieldValue.serverTimestamp(),
    });
  }

  /// Установить баланс напрямую
  Future<void> setBalance(double newBalance) async {
    await _accountRef.set({
      'currentBalance': newBalance,
      'lastUpdated': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// Stream баланса для realtime обновлений
  Stream<double> balanceStream() {
    return _accountRef.snapshots().map((doc) {
      if (!doc.exists) return 0.0;
      return (doc.data()?['currentBalance'] as num?)?.toDouble() ?? 0.0;
    });
  }

  /// Получить полные данные аккаунта
  Future<FinanceAccount> getAccount() async {
    final doc = await _accountRef.get();
    if (!doc.exists) {
      final data = await getOrCreateAccount();
      return FinanceAccount.fromMap(data);
    }
    return FinanceAccount.fromMap(doc.data()!);
  }
}

/// Модель финансового аккаунта
class FinanceAccount {
  final double currentBalance;
  final String currency;
  final DateTime? lastUpdated;
  final DateTime? createdAt;

  const FinanceAccount({
    required this.currentBalance,
    this.currency = 'USD',
    this.lastUpdated,
    this.createdAt,
  });

  factory FinanceAccount.fromMap(Map<String, dynamic> map) {
    return FinanceAccount(
      currentBalance: (map['currentBalance'] as num?)?.toDouble() ?? 0.0,
      currency: map['currency'] as String? ?? 'USD',
      lastUpdated: (map['lastUpdated'] as Timestamp?)?.toDate(),
      createdAt: (map['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'currentBalance': currentBalance,
      'currency': currency,
      'lastUpdated': lastUpdated != null ? Timestamp.fromDate(lastUpdated!) : FieldValue.serverTimestamp(),
      'createdAt': createdAt != null ? Timestamp.fromDate(createdAt!) : FieldValue.serverTimestamp(),
    };
  }

  FinanceAccount copyWith({
    double? currentBalance,
    String? currency,
    DateTime? lastUpdated,
    DateTime? createdAt,
  }) {
    return FinanceAccount(
      currentBalance: currentBalance ?? this.currentBalance,
      currency: currency ?? this.currency,
      lastUpdated: lastUpdated ?? this.lastUpdated,
      createdAt: createdAt ?? this.createdAt,
    );
  }
}
