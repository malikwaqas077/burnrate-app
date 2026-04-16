import 'package:hive_flutter/hive_flutter.dart';

class LocalStorageService {
  static const String _transactionsBox = 'transactions';
  static const String _chatHistoryBox = 'chat_history';
  static const String _settingsBox = 'settings';

  static Future<void> init() async {
    await Hive.initFlutter();
    await Hive.openBox(_transactionsBox);
    await Hive.openBox(_chatHistoryBox);
    await Hive.openBox(_settingsBox);
  }

  // ── Settings ──────────────────────────────────────────────────────────────

  static Box get _settings => Hive.box(_settingsBox);

  static bool get isLocalStorageEnabled =>
      _settings.get('localStorageEnabled', defaultValue: false) as bool;

  static set isLocalStorageEnabled(bool value) =>
      _settings.put('localStorageEnabled', value);

  static bool get aiCloudConsentEnabled =>
      _settings.get('aiCloudConsentEnabled', defaultValue: false) as bool;

  static set aiCloudConsentEnabled(bool value) =>
      _settings.put('aiCloudConsentEnabled', value);

  static bool get preferOnlineAi =>
      _settings.get('preferOnlineAi', defaultValue: false) as bool;

  static set preferOnlineAi(bool value) =>
      _settings.put('preferOnlineAi', value);

  static bool get includeAllTimeCloudAiContext =>
      _settings.get('includeAllTimeCloudAiContext', defaultValue: false)
          as bool;

  static set includeAllTimeCloudAiContext(bool value) =>
      _settings.put('includeAllTimeCloudAiContext', value);

  // ── Transactions (local mode) ─────────────────────────────────────────────

  static Box get _transactions => Hive.box(_transactionsBox);

  static Future<void> saveTransaction(Map<String, dynamic> tx) async {
    final id = tx['id'] ?? DateTime.now().millisecondsSinceEpoch.toString();
    await _transactions.put(id, tx);
  }

  static List<Map<String, dynamic>> getTransactions() {
    return _transactions.values
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
      ..sort((a, b) {
        final dateA = DateTime.tryParse(a['date'] ?? '') ?? DateTime(2000);
        final dateB = DateTime.tryParse(b['date'] ?? '') ?? DateTime(2000);
        return dateB.compareTo(dateA);
      });
  }

  static Future<void> deleteTransaction(String id) async {
    await _transactions.delete(id);
  }

  // ── Chat History (always local) ───────────────────────────────────────────

  static Box get _chatHistory => Hive.box(_chatHistoryBox);

  static Future<void> saveChatMessage(Map<String, String> message) async {
    final messages = getChatMessages();
    messages.add(message);
    await _chatHistory.put('messages', messages);
  }

  static List<Map<String, String>> getChatMessages() {
    final raw = _chatHistory.get('messages', defaultValue: <dynamic>[]) as List;
    return raw.map((e) => Map<String, String>.from(e as Map)).toList();
  }

  static Future<void> clearChatHistory() async {
    await _chatHistory.put('messages', <dynamic>[]);
  }
}
