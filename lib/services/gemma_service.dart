import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'offline_coach_config.dart';

/// On-device offline financial advisor powered by Google AI Edge LiteRT-LM
/// with Gemma 4 E2B. All inference happens locally via a native Kotlin
/// MethodChannel — no network is required once the model is downloaded.
class OfflineCoachPlatformCapabilities {
  const OfflineCoachPlatformCapabilities({
    required this.isAndroid,
    required this.runtime,
    required this.sdkInt,
    required this.totalRamMb,
    required this.availableStorageMb,
    required this.isSupported,
    required this.reasons,
  });

  final bool isAndroid;
  final String runtime;
  final int sdkInt;
  final int totalRamMb;
  final int availableStorageMb;
  final bool isSupported;
  final List<String> reasons;

  factory OfflineCoachPlatformCapabilities.fromMap(Map<String, dynamic> map) {
    return OfflineCoachPlatformCapabilities(
      isAndroid: map['isAndroid'] as bool? ?? false,
      runtime: map['runtime'] as String? ?? OfflineCoachConfig.runtime,
      sdkInt: (map['sdkInt'] as num?)?.toInt() ?? 0,
      totalRamMb: (map['totalRamMb'] as num?)?.toInt() ?? 0,
      availableStorageMb: (map['availableStorageMb'] as num?)?.toInt() ?? 0,
      isSupported: map['isSupported'] as bool? ?? false,
      reasons:
          (map['reasons'] as List?)?.map((e) => e.toString()).toList() ??
          const [],
    );
  }

  factory OfflineCoachPlatformCapabilities.unsupported(String reason) =>
      OfflineCoachPlatformCapabilities(
        isAndroid: false,
        runtime: OfflineCoachConfig.runtime,
        sdkInt: 0,
        totalRamMb: 0,
        availableStorageMb: 0,
        isSupported: false,
        reasons: [reason],
      );
}

class OfflineCoachModelStatus {
  const OfflineCoachModelStatus({
    required this.isDownloaded,
    required this.isReady,
    required this.isInitializing,
    required this.downloadedBytes,
    required this.requiredBytes,
    required this.message,
  });

  final bool isDownloaded;
  final bool isReady;
  final bool isInitializing;
  final int downloadedBytes;
  final int requiredBytes;
  final String message;

  factory OfflineCoachModelStatus.fromMap(Map<String, dynamic> map) {
    return OfflineCoachModelStatus(
      isDownloaded: map['isDownloaded'] as bool? ?? false,
      isReady: map['isReady'] as bool? ?? false,
      isInitializing: map['isInitializing'] as bool? ?? false,
      downloadedBytes: (map['downloadedBytes'] as num?)?.toInt() ?? 0,
      requiredBytes:
          (map['requiredBytes'] as num?)?.toInt() ??
          OfflineCoachConfig.modelSizeBytes,
      message: map['message'] as String? ?? '',
    );
  }
}

class OfflineCoachDownloadStatus {
  const OfflineCoachDownloadStatus({
    required this.state,
    required this.downloadedBytes,
    required this.totalBytes,
    required this.progress,
    required this.message,
  });

  final String state;
  final int downloadedBytes;
  final int totalBytes;
  final double? progress;
  final String message;

  bool get isActive => state == 'pending' || state == 'running';

  factory OfflineCoachDownloadStatus.fromMap(Map<String, dynamic> map) {
    final downloaded = (map['downloadedBytes'] as num?)?.toInt() ?? 0;
    final total = (map['totalBytes'] as num?)?.toInt() ?? 0;
    return OfflineCoachDownloadStatus(
      state: map['state'] as String? ?? 'idle',
      downloadedBytes: downloaded,
      totalBytes: total,
      progress: (downloaded > 0 && total > 0) ? downloaded / total : null,
      message: map['message'] as String? ?? '',
    );
  }
}

class GemmaService {
  GemmaService._();
  static final GemmaService instance = GemmaService._();

  static const MethodChannel _channel = MethodChannel(
    'com.burnrate.burnrate/offline_coach',
  );

  Future<OfflineCoachPlatformCapabilities> getPlatformCapabilities() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) {
      return OfflineCoachPlatformCapabilities.unsupported(
        'Offline advisor is currently supported on Android only.',
      );
    }
    final result = await _channel.invokeMethod<Object?>(
      'getPlatformCapabilities',
    );
    return OfflineCoachPlatformCapabilities.fromMap(_asMap(result));
  }

  Future<OfflineCoachModelStatus> getModelStatus() async {
    final result = await _channel.invokeMethod<Object?>('getModelStatus');
    return OfflineCoachModelStatus.fromMap(_asMap(result));
  }

  Future<OfflineCoachDownloadStatus> getDownloadStatus() async {
    final result = await _channel.invokeMethod<Object?>('getDownloadStatus');
    return OfflineCoachDownloadStatus.fromMap(_asMap(result));
  }

  Future<OfflineCoachDownloadStatus> startDownload({
    bool wifiOnly = true,
  }) async {
    final result = await _channel.invokeMethod<Object?>('downloadModel', {
      'url': OfflineCoachConfig.modelDownloadUrl,
      'version': OfflineCoachConfig.modelVersion,
      'wifiOnly': wifiOnly,
    });
    return OfflineCoachDownloadStatus.fromMap(_asMap(result));
  }

  Future<OfflineCoachDownloadStatus> cancelDownload() async {
    final result = await _channel.invokeMethod<Object?>('cancelDownload');
    return OfflineCoachDownloadStatus.fromMap(_asMap(result));
  }

  Future<OfflineCoachModelStatus> deleteModel() async {
    final result = await _channel.invokeMethod<Object?>('deleteModel');
    return OfflineCoachModelStatus.fromMap(_asMap(result));
  }

  Future<OfflineCoachModelStatus> initializeModel({
    bool preferGpu = false,
  }) async {
    final result = await _channel.invokeMethod<Object?>('initializeModel', {
      'preferGpu': preferGpu,
    });
    return OfflineCoachModelStatus.fromMap(_asMap(result));
  }

  Future<void> disposeModel() async {
    if (kIsWeb || defaultTargetPlatform != TargetPlatform.android) return;
    await _channel.invokeMethod<void>('disposeModel');
  }

  /// Send a user chat message. Optionally include a financial snapshot
  /// so the model can ground its answer in the user's actual numbers.
  Future<String> sendMessage(
    String userMessage, {
    Map<String, dynamic>? financialContext,
    List<Map<String, String>> history = const [],
    bool deepInsights = false,
  }) async {
    final systemPrompt = _buildSystemPrompt();
    final userPrompt = _buildUserPrompt(
      userMessage: userMessage,
      financialContext: financialContext,
      history: history,
      deepInsights: deepInsights,
    );

    final result = await _channel.invokeMethod<Object?>('generateResponse', {
      'systemPrompt': systemPrompt,
      'userPrompt': userPrompt,
    });
    final map = _asMap(result);
    final text = (map['text'] as String? ?? '').trim();
    if (text.isEmpty) {
      throw StateError('The offline advisor returned an empty response.');
    }
    return text;
  }

  String _buildSystemPrompt() {
    final boundaries = OfflineCoachConfig.safetyBoundaries
        .map((b) => '- $b')
        .join('\n');
    return '''
You are BurnRate AI, a friendly on-device personal finance advisor inside the BurnRate expense-tracking app.

Your role:
- Analyse the user's spending patterns and monthly burn rate.
- Suggest practical, low-effort ways to save money.
- Explain financial concepts in plain, encouraging language.
- Help the user set and track realistic financial goals.
- Use £ (GBP) as the default currency.

Style:
- Keep replies concise (3-5 sentences or a short bullet list).
- Be encouraging and non-judgmental.
- Use the user's financial snapshot when provided; cite real numbers.
- When explaining burn rate, describe it as how fast money is spent relative to income.

Safety boundaries:
$boundaries
''';
  }

  String _buildUserPrompt({
    required String userMessage,
    Map<String, dynamic>? financialContext,
    List<Map<String, String>> history = const [],
    bool deepInsights = false,
  }) {
    final maxHistory = deepInsights ? 10 : 6;
    final recent = history.length <= maxHistory
        ? history
        : history.sublist(history.length - maxHistory);

    final historyBlock = recent.isEmpty
        ? 'No previous chat yet.'
        : recent
              .map(
                (m) =>
                    '${m['role'] == 'user' ? 'User' : 'Advisor'}: ${(m['content'] ?? '').trim()}',
              )
              .join('\n');

    final buf = StringBuffer()
      ..writeln('Recent conversation:')
      ..writeln(historyBlock)
      ..writeln()
      ..writeln('Insight mode: ${deepInsights ? 'Deep' : 'Standard'}')
      ..writeln()
      ..writeln('Latest user question:')
      ..writeln(userMessage.trim());

    if (financialContext != null && financialContext.isNotEmpty) {
      buf
        ..writeln()
        ..writeln('User financial snapshot (last 30 days):')
        ..writeln(_formatContext(financialContext));
    }

    final text = buf.toString().trim();
    final cap = deepInsights
        ? OfflineCoachConfig.deepInsightsMaxPromptChars
        : OfflineCoachConfig.maxPromptChars;
    if (text.length <= cap) return text;
    return text.substring(0, cap);
  }

  String _formatContext(Map<String, dynamic> ctx) {
    final buf = StringBuffer();
    final income = ctx['totalIncome'];
    final expenses = ctx['totalExpenses'];
    final burn = ctx['monthlyBurnRate'];
    final count = ctx['transactionCount'];
    final topCats = ctx['topCategories'] as List?;
    final catBreakdown = ctx['categoryBreakdown'] as Map?;
    final windowDays = ctx['analysisWindowDays'];
    final windowLabelValue = ctx['analysisWindowLabel']?.toString();
    final netCashFlow = ctx['netCashFlow'];
    final avgDailySpend = ctx['avgDailySpend'];
    final medianExpense = ctx['medianExpense'];
    final largestExpense = ctx['largestExpense'];
    final spendingTrend = ctx['spendingTrend'];
    final weekdayWeekendSplit = ctx['weekdayWeekendSplit'] as Map?;
    final monthlyTotals = ctx['monthlyTotals'] as Map?;
    final recurringSubscriptions = ctx['recurringSubscriptions'] as List?;
    final highSpendDays = ctx['highSpendDays'] as List?;
    final sampleTransactions = ctx['sampleTransactions'] as List?;

    final windowLabel =
        windowLabelValue ??
        ((windowDays == null) ? 'selected window' : '${windowDays}d');
    if (windowDays != null) {
      buf.writeln('- Analysis window: $windowDays days');
    } else if (windowLabelValue != null) {
      buf.writeln('- Analysis window: $windowLabelValue');
    }
    if (income != null) buf.writeln('- Income ($windowLabel): £$income');
    if (expenses != null) buf.writeln('- Expenses ($windowLabel): £$expenses');
    if (burn != null) buf.writeln('- Monthly burn rate: £$burn');
    if (netCashFlow != null) buf.writeln('- Net cash flow: £$netCashFlow');
    if (avgDailySpend != null) {
      buf.writeln('- Average daily spend: £$avgDailySpend');
    }
    if (medianExpense != null) {
      buf.writeln('- Median expense amount: £$medianExpense');
    }
    if (largestExpense != null) {
      buf.writeln('- Largest expense: £$largestExpense');
    }
    if (spendingTrend != null) buf.writeln('- Spending trend: $spendingTrend');
    if (count != null) buf.writeln('- Transactions: $count');
    if (topCats != null && topCats.isNotEmpty) {
      buf.writeln('- Top categories: ${topCats.join(', ')}');
    }
    if (catBreakdown != null && catBreakdown.isNotEmpty) {
      buf.writeln('- Category spend:');
      catBreakdown.forEach((k, v) => buf.writeln('    $k: £$v'));
    }
    if (weekdayWeekendSplit != null && weekdayWeekendSplit.isNotEmpty) {
      buf.writeln('- Weekday vs weekend spend:');
      weekdayWeekendSplit.forEach((k, v) => buf.writeln('    $k: £$v'));
    }
    if (monthlyTotals != null && monthlyTotals.isNotEmpty) {
      buf.writeln('- Monthly spend totals:');
      monthlyTotals.forEach((k, v) => buf.writeln('    $k: £$v'));
    }
    if (recurringSubscriptions != null && recurringSubscriptions.isNotEmpty) {
      buf.writeln('- Likely recurring charges:');
      for (final item in recurringSubscriptions.take(20)) {
        buf.writeln('    - $item');
      }
    }
    if (highSpendDays != null && highSpendDays.isNotEmpty) {
      buf.writeln('- Highest spend days:');
      for (final item in highSpendDays.take(12)) {
        buf.writeln('    - $item');
      }
    }
    if (sampleTransactions != null && sampleTransactions.isNotEmpty) {
      buf.writeln('- Relevant transactions sample:');
      for (final item in sampleTransactions.take(60)) {
        buf.writeln('    - $item');
      }
    }
    return buf.toString();
  }

  static Map<String, dynamic> _asMap(Object? raw) {
    if (raw is Map) {
      return raw.map((k, v) => MapEntry(k.toString(), v));
    }
    return const <String, dynamic>{};
  }
}
