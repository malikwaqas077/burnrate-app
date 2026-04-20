import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/gemma_service.dart';
import '../services/local_storage_service.dart';
import '../services/online_ai_service.dart';
import '../services/offline_coach_config.dart';
import '../theme/app_theme.dart';

/// On-device AI financial advisor, powered by LiteRT-LM + Gemma 4 E2B.
///
/// Flow matches DriveMate's Driving Companion:
/// 1. Show capability + download card.
/// 2. User taps "Download companion" (no Hugging Face token needed — uses
///    the public litert-community mirror).
/// 3. Once downloaded, user taps "Get advisor ready" to load the model.
/// 4. Once ready, chat UI appears.
class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});

  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final GemmaService _service = GemmaService.instance;
  final OnlineAiService _onlineService = OnlineAiService.instance;
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<Map<String, String>> _messages = [];

  OfflineCoachPlatformCapabilities? _capabilities;
  OfflineCoachModelStatus? _modelStatus;
  OfflineCoachDownloadStatus? _downloadStatus;
  Timer? _pollTimer;

  bool _isBusy = false;
  bool _isPreparing = false;
  bool _isSending = false;
  bool _deepInsightsMode = false;
  bool _allowCloudData = false;
  bool _useOnlineAi = false;
  bool _includeAllTimeCloudContext = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadAiPreferences();
    _refreshState();
  }

  void _loadAiPreferences() {
    _allowCloudData = LocalStorageService.aiCloudConsentEnabled;
    _useOnlineAi = LocalStorageService.preferOnlineAi && _allowCloudData;
    _includeAllTimeCloudContext =
        LocalStorageService.includeAllTimeCloudAiContext && _allowCloudData;
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _inputController.dispose();
    _scrollController.dispose();
    _service.disposeModel();
    super.dispose();
  }

  Future<void> _refreshState() async {
    setState(() => _error = null);
    try {
      final results = await Future.wait<Object>([
        _service.getPlatformCapabilities(),
        _service.getModelStatus(),
        _service.getDownloadStatus(),
      ]);
      if (!mounted) return;
      setState(() {
        _capabilities = results[0] as OfflineCoachPlatformCapabilities;
        _modelStatus = results[1] as OfflineCoachModelStatus;
        _downloadStatus = results[2] as OfflineCoachDownloadStatus;
      });
      _updatePolling();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    }
  }

  void _updatePolling() {
    final shouldPoll = _downloadStatus?.isActive == true;
    if (!shouldPoll) {
      _pollTimer?.cancel();
      _pollTimer = null;
      return;
    }
    _pollTimer ??= Timer.periodic(
      const Duration(seconds: 2),
      (_) => _refreshState(),
    );
  }

  Future<void> _download() async {
    setState(() {
      _isBusy = true;
      _error = null;
    });
    try {
      final status = await _service.startDownload();
      if (!mounted) return;
      setState(() => _downloadStatus = status);
      _updatePolling();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _cancelDownload() async {
    setState(() => _isBusy = true);
    try {
      final status = await _service.cancelDownload();
      if (!mounted) return;
      setState(() => _downloadStatus = status);
      _updatePolling();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<void> _prepareAdvisor() async {
    if (_isPreparing) return;
    setState(() {
      _isPreparing = true;
      _error = null;
    });
    try {
      final status = await _service.initializeModel();
      if (!mounted) return;
      setState(() => _modelStatus = status);
      await _refreshState();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isPreparing = false);
    }
  }

  Future<void> _deleteModel() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: AppColors.surface,
        title: const Text(
          'Remove local model?',
          style: TextStyle(color: AppColors.text),
        ),
        content: const Text(
          'This frees ~2.5 GB on your device. You can download it again anytime.',
          style: TextStyle(color: AppColors.textMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text(
              'Remove',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirm != true) return;

    setState(() => _isBusy = true);
    try {
      final status = await _service.deleteModel();
      if (!mounted) return;
      setState(() {
        _modelStatus = status;
        _messages.clear();
      });
      await _refreshState();
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _isBusy = false);
    }
  }

  Future<Map<String, dynamic>?> _buildFinancialContext(
    String userMessage, {
    required bool includeAllTime,
  }) async {
    if (LocalStorageService.isLocalStorageEnabled) {
      return _buildLocalContext(userMessage, includeAllTime: includeAllTime);
    }
    return _buildCloudContext(userMessage, includeAllTime: includeAllTime);
  }

  Map<String, dynamic>? _buildLocalContext(
    String userMessage, {
    required bool includeAllTime,
  }) {
    final transactions = LocalStorageService.getTransactions();
    if (transactions.isEmpty) return null;

    final days = includeAllTime
        ? null
        : (_deepInsightsMode
              ? OfflineCoachConfig.deepInsightsDays
              : OfflineCoachConfig.defaultInsightsDays);
    final cutoff = days == null
        ? null
        : DateTime.now().subtract(Duration(days: days));
    final normalized = <Map<String, dynamic>>[];

    for (final tx in transactions) {
      final dateStr = tx['date']?.toString();
      if (dateStr == null || dateStr.isEmpty) continue;
      final date = DateTime.tryParse(dateStr);
      if (date == null) continue;
      if (cutoff != null && date.isBefore(cutoff)) continue;
      normalized.add({
        'date': date,
        'amount': double.tryParse(tx['amount']?.toString() ?? '0') ?? 0,
        'category': (tx['category'] ?? 'other').toString().trim(),
        'merchant': (tx['merchant'] ?? tx['name'] ?? '').toString().trim(),
        'note': (tx['note'] ?? tx['description'] ?? '').toString().trim(),
      });
    }

    if (normalized.isEmpty) return null;
    return _buildContextFromTransactions(
      normalized,
      userMessage: userMessage,
      analysisWindowDays: days,
      allTime: includeAllTime,
      deepMode: _deepInsightsMode,
    );
  }

  Future<Map<String, dynamic>?> _buildCloudContext(
    String userMessage, {
    required bool includeAllTime,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return null;

      final days = includeAllTime
          ? null
          : (_deepInsightsMode
                ? OfflineCoachConfig.deepInsightsDays
                : OfflineCoachConfig.defaultInsightsDays);
      final cutoff = days == null
          ? null
          : DateTime.now().subtract(Duration(days: days));

      final txRef = FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('transactions');
      final snap = cutoff == null
          ? await txRef.get()
          : await txRef
                .where(
                  'date',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(cutoff),
                )
                .get();

      if (snap.docs.isEmpty) return null;
      final normalized = <Map<String, dynamic>>[];

      for (final doc in snap.docs) {
        final data = doc.data();
        final rawDate = data['date'];
        DateTime? date;
        if (rawDate is Timestamp) {
          date = rawDate.toDate();
        } else if (rawDate is DateTime) {
          date = rawDate;
        } else if (rawDate is String) {
          date = DateTime.tryParse(rawDate);
        }
        if (date == null) continue;
        if (cutoff != null && date.isBefore(cutoff)) continue;
        normalized.add({
          'date': date,
          'amount': (data['amount'] as num?)?.toDouble() ?? 0,
          'category': (data['category'] ?? 'other').toString().trim(),
          'merchant': (data['merchant'] ?? data['name'] ?? '')
              .toString()
              .trim(),
          'note': (data['note'] ?? data['description'] ?? '').toString().trim(),
        });
      }

      if (normalized.isEmpty) return null;
      return _buildContextFromTransactions(
        normalized,
        userMessage: userMessage,
        analysisWindowDays: days,
        allTime: includeAllTime,
        deepMode: _deepInsightsMode,
      );
    } catch (_) {
      return null;
    }
  }

  bool get _isOnlineReady => _allowCloudData && _useOnlineAi;

  bool get _isOfflineReady =>
      _capabilities?.isSupported != false &&
      _modelStatus?.isDownloaded == true &&
      _modelStatus?.isReady == true;

  void _setCloudConsent(bool value) {
    setState(() {
      _allowCloudData = value;
      if (!value) {
        _useOnlineAi = false;
        _includeAllTimeCloudContext = false;
      }
      _error = null;
    });
    LocalStorageService.aiCloudConsentEnabled = value;
    LocalStorageService.preferOnlineAi = _useOnlineAi;
    LocalStorageService.includeAllTimeCloudAiContext =
        _includeAllTimeCloudContext;
  }

  void _setOnlineMode(bool value) {
    if (value && !_allowCloudData) return;
    setState(() {
      _useOnlineAi = value;
      if (!value) {
        _includeAllTimeCloudContext = false;
      }
      _error = null;
    });
    LocalStorageService.preferOnlineAi = value;
    LocalStorageService.includeAllTimeCloudAiContext =
        _includeAllTimeCloudContext;
  }

  void _setAllTimeCloudContext(bool value) {
    if (!_allowCloudData || !_useOnlineAi) return;
    setState(() {
      _includeAllTimeCloudContext = value;
      _error = null;
    });
    LocalStorageService.includeAllTimeCloudAiContext = value;
  }

  Future<void> _sendMessage() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _isSending) return;
    if (!_isOnlineReady && !_isOfflineReady) {
      setState(
        () => _error =
            'Set up offline model or enable online advisor before sending.',
      );
      return;
    }

    _inputController.clear();
    setState(() {
      _messages.add({'role': 'user', 'content': text});
      _isSending = true;
      _error = null;
    });
    _scrollToBottom();
    LocalStorageService.saveChatMessage({'role': 'user', 'content': text});

    try {
      final ctx = await _buildFinancialContext(
        text,
        includeAllTime: _isOnlineReady && _includeAllTimeCloudContext,
      );
      final reply = _isOnlineReady
          ? await _onlineService.sendMessage(
              userMessage: text,
              financialContext: ctx,
              history: List<Map<String, String>>.from(_messages),
              deepInsights: _deepInsightsMode,
            )
          : await _service.sendMessage(
              text,
              financialContext: ctx,
              history: List<Map<String, String>>.from(_messages),
              deepInsights: _deepInsightsMode,
            );
      if (!mounted) return;
      setState(() {
        _messages.add({'role': 'assistant', 'content': reply});
        _isSending = false;
      });
      LocalStorageService.saveChatMessage({
        'role': 'assistant',
        'content': reply,
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add({
          'role': 'assistant',
          'content':
              'Sorry, something went wrong running the advisor. Please try again.',
        });
        _isSending = false;
        _error = e.toString();
      });
    }
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final capabilities = _capabilities;
    final modelStatus = _modelStatus;
    final downloadStatus = _downloadStatus;
    final isReady = _isOnlineReady || _isOfflineReady;

    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        title: const Row(
          children: [
            Icon(Icons.auto_awesome, color: AppColors.primary, size: 24),
            SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'BurnRate AI',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: AppColors.text,
                    letterSpacing: -0.5,
                  ),
                ),
                Text(
                  'On-device advisor',
                  style: TextStyle(fontSize: 11, color: AppColors.textMuted),
                ),
              ],
            ),
          ],
        ),
        actions: [
          if (modelStatus?.isDownloaded == true)
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.textMuted),
              color: AppColors.surfaceLight,
              onSelected: (v) {
                if (v == 'refresh') _refreshState();
                if (v == 'remove') _deleteModel();
              },
              itemBuilder: (_) => const [
                PopupMenuItem(value: 'refresh', child: Text('Refresh')),
                PopupMenuItem(
                  value: 'remove',
                  child: Text(
                    'Remove local model',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              ],
            ),
        ],
      ),
      body: isReady
          ? _buildReadyView()
          : RefreshIndicator(
              onRefresh: _refreshState,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                children: [
                  _buildIntroCard(),
                  const SizedBox(height: 16),
                  _buildAiModeCard(),
                  const SizedBox(height: 16),
                  if (capabilities != null && !capabilities.isSupported) ...[
                    _buildUnavailableCard(capabilities),
                    const SizedBox(height: 16),
                  ],
                  if (modelStatus != null && downloadStatus != null)
                    _buildModelCard(modelStatus, downloadStatus),
                  if (_error != null) ...[
                    const SizedBox(height: 16),
                    _buildErrorCard(_error!),
                  ],
                ],
              ),
            ),
    );
  }

  Widget _buildIntroCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.auto_awesome_rounded, color: AppColors.primary),
              SizedBox(width: 10),
              Text(
                'Your AI financial advisor',
                style: TextStyle(
                  color: AppColors.text,
                  fontSize: 17,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          const Text(
            'Get simple, practical help based on your spending and burn rate. '
            'Use on-device Gemma by default, or opt into cloud Claude for deeper online analysis.',
            style: TextStyle(color: AppColors.text, height: 1.4, fontSize: 14),
          ),
        ],
      ),
    );
  }

  Widget _buildAiModeCard() {
    final subtitle = _isOnlineReady
        ? 'Online Claude mode enabled. Your selected financial context is sent to secure cloud processing.'
        : 'Offline Gemma mode keeps all inference on your device.';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'AI mode and data sharing',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            subtitle,
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Allow cloud AI data sharing',
                  style: TextStyle(color: AppColors.text, fontSize: 13),
                ),
              ),
              Switch(
                value: _allowCloudData,
                onChanged: _isSending ? null : _setCloudConsent,
                activeThumbColor: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Use online advisor (Claude)',
                  style: TextStyle(
                    color: _allowCloudData
                        ? AppColors.text
                        : AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
              Switch(
                value: _useOnlineAi,
                onChanged: (!_allowCloudData || _isSending)
                    ? null
                    : _setOnlineMode,
                activeThumbColor: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Include all-time history in cloud analysis',
                  style: TextStyle(
                    color: (_allowCloudData && _useOnlineAi)
                        ? AppColors.text
                        : AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
              ),
              Switch(
                value: _includeAllTimeCloudContext,
                onChanged: (!_allowCloudData || !_useOnlineAi || _isSending)
                    ? null
                    : _setAllTimeCloudContext,
                activeThumbColor: AppColors.primary,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _useOnlineAi
                ? 'Provider: Claude (${OfflineCoachConfig.onlineModel})'
                : 'Provider: Gemma on-device',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
          ),
          if (_useOnlineAi && _includeAllTimeCloudContext)
            const Padding(
              padding: EdgeInsets.only(top: 6),
              child: Text(
                'All-time mode sends the full transaction history context to cloud AI for this chat.',
                style: TextStyle(color: AppColors.textMuted, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildUnavailableCard(OfflineCoachPlatformCapabilities caps) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Not available on this device',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'This feature needs a recent Android device with enough RAM and storage.',
            style: TextStyle(color: AppColors.textMuted),
          ),
          if (caps.reasons.isNotEmpty) ...[
            const SizedBox(height: 10),
            ...caps.reasons.map(
              (r) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  '• $r',
                  style: const TextStyle(color: AppColors.textMuted),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildModelCard(
    OfflineCoachModelStatus status,
    OfflineCoachDownloadStatus download,
  ) {
    final progress = download.progress;
    final ready = status.isDownloaded && status.isReady;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  status.isDownloaded
                      ? 'Ready when you are'
                      : 'Download to get started',
                  style: const TextStyle(
                    color: AppColors.text,
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (ready)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.check_circle_outline,
                        size: 16,
                        color: AppColors.primary,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Ready',
                        style: TextStyle(
                          color: AppColors.primary,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            status.isDownloaded
                ? 'The advisor is saved on this phone and ready to help you understand your spending.'
                : 'Download it once, then come back any time for on-device financial advice.',
            style: const TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(Icons.download_rounded, 'One-time download'),
              _chip(
                Icons.memory_rounded,
                _formatBytes(OfflineCoachConfig.modelSizeBytes),
              ),
              _chip(Icons.lock_outline_rounded, 'On-device only'),
            ],
          ),
          if (download.isActive || download.state == 'completed') ...[
            const SizedBox(height: 16),
            LinearProgressIndicator(
              value: progress,
              backgroundColor: AppColors.surfaceLight,
              valueColor: const AlwaysStoppedAnimation<Color>(
                AppColors.primary,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              progress == null
                  ? download.message
                  : '${(progress * 100).toStringAsFixed(0)}% • '
                        '${_formatBytes(download.downloadedBytes)} of '
                        '${_formatBytes(download.totalBytes)}',
              style: const TextStyle(color: AppColors.textMuted, fontSize: 12),
            ),
          ],
          const SizedBox(height: 16),
          if (!status.isDownloaded)
            ElevatedButton.icon(
              onPressed: _isBusy ? null : _download,
              icon: const Icon(Icons.download_for_offline_rounded),
              label: const Text('Download advisor'),
            ),
          if (download.isActive) ...[
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _isBusy ? null : _cancelDownload,
              icon: const Icon(Icons.close_rounded),
              label: const Text('Cancel download'),
            ),
          ],
          if (status.isDownloaded) ...[
            ElevatedButton.icon(
              onPressed: (_isBusy || _isPreparing || ready)
                  ? null
                  : _prepareAdvisor,
              icon: _isPreparing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.play_circle_outline_rounded),
              label: Text(
                ready
                    ? 'Advisor ready'
                    : _isPreparing
                    ? 'Getting things ready...'
                    : 'Get advisor ready',
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: _isBusy ? null : _deleteModel,
              icon: const Icon(
                Icons.delete_outline_rounded,
                color: AppColors.danger,
              ),
              label: const Text(
                'Remove local model',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildReadyView() {
    return Column(
      children: [
        Expanded(
          child: ListView(
            controller: _scrollController,
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            children: [
              _buildWelcomeCard(),
              const SizedBox(height: 12),
              _buildAiModeCard(),
              const SizedBox(height: 12),
              if (_error != null) ...[
                _buildErrorCard(_error!),
                const SizedBox(height: 12),
              ],
              if (_messages.isEmpty) _buildEmptyChat(),
              ..._messages.map((m) => _buildBubble(m)),
              if (_isSending) ...[
                const SizedBox(height: 8),
                _buildTypingBubble(),
              ],
            ],
          ),
        ),
        _buildComposer(),
      ],
    );
  }

  Widget _buildWelcomeCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Ask anything about your spending',
            style: TextStyle(
              color: AppColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          const Text(
            "I can explain your burn rate, suggest ways to save, and help you plan realistic goals.",
            style: TextStyle(color: AppColors.textMuted, fontSize: 13),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: AppColors.surfaceLight,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.border),
            ),
            child: Row(
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Deep insights mode',
                        style: TextStyle(
                          color: AppColors.text,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      SizedBox(height: 2),
                      Text(
                        'Uses longer history and richer analysis for better answers.',
                        style: TextStyle(
                          color: AppColors.textMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: _deepInsightsMode,
                  onChanged: _isSending
                      ? null
                      : (value) => setState(() => _deepInsightsMode = value),
                  activeThumbColor: AppColors.primary,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyChat() {
    return Container(
      padding: const EdgeInsets.all(14),
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: const Text(
        "Try: “How's my burn rate this month?” or “Where am I overspending?”",
        style: TextStyle(color: AppColors.textMuted, fontSize: 13),
      ),
    );
  }

  Widget _buildBubble(Map<String, String> msg) {
    final isUser = msg['role'] == 'user';
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: isUser
            ? MainAxisAlignment.end
            : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [AppColors.primary, AppColors.accent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.local_fire_department, size: 20, color: Colors.white),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? AppColors.primary.withValues(alpha: 0.15)
                    : AppColors.surface,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(18),
                  topRight: const Radius.circular(18),
                  bottomLeft: isUser
                      ? const Radius.circular(18)
                      : const Radius.circular(4),
                  bottomRight: isUser
                      ? const Radius.circular(4)
                      : const Radius.circular(18),
                ),
                border: Border.all(
                  color: isUser ? AppColors.primary : AppColors.border,
                ),
              ),
              child: Text(
                msg['content'] ?? '',
                style: TextStyle(
                  color: isUser ? AppColors.primary : AppColors.text,
                  fontSize: 15,
                  height: 1.4,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 40),
        ],
      ),
    );
  }

  Widget _buildTypingBubble() {
    return Row(
      children: [
        Container(
          width: 36, height: 36,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [AppColors.primary, AppColors.accent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(10),
          ),
          child: const Icon(Icons.local_fire_department, size: 20, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: AppColors.border),
          ),
          child: const _TypingDotsIndicator(),
        ),
      ],
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        decoration: BoxDecoration(
          color: AppColors.surface,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.2),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                textCapitalization: TextCapitalization.sentences,
                style: const TextStyle(color: AppColors.text),
                minLines: 1,
                maxLines: 4,
                decoration: InputDecoration(
                  hintText: 'Ask about your finances...',
                  filled: true,
                  fillColor: AppColors.surfaceLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _sendMessage(),
                enabled: !_isSending,
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _isSending ? null : _sendMessage,
              icon: _isSending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.send_rounded),
              style: IconButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: AppColors.surfaceLighter,
                padding: const EdgeInsets.all(12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorCard(String err) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.danger.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withValues(alpha: 0.3)),
      ),
      child: Text(
        err,
        style: const TextStyle(color: AppColors.danger, fontSize: 12),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceLight,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: AppColors.textMuted),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(color: AppColors.text, fontSize: 12),
          ),
        ],
      ),
    );
  }

  String _formatBytes(num bytes) {
    const kb = 1024;
    const mb = kb * 1024;
    const gb = mb * 1024;
    if (bytes >= gb) return '${(bytes / gb).toStringAsFixed(2)} GB';
    if (bytes >= mb) return '${(bytes / mb).toStringAsFixed(0)} MB';
    if (bytes >= kb) return '${(bytes / kb).toStringAsFixed(0)} KB';
    return '$bytes B';
  }

  Map<String, dynamic> _buildContextFromTransactions(
    List<Map<String, dynamic>> rows, {
    required String userMessage,
    required int? analysisWindowDays,
    required bool allTime,
    required bool deepMode,
  }) {
    double totalIncome = 0;
    double totalExpenses = 0;
    final categoryTotals = <String, double>{};
    final monthlyTotals = <String, double>{};
    final weekdayWeekend = <String, double>{'weekday': 0, 'weekend': 0};
    final expenseAmounts = <double>[];
    final spendByDay = <String, double>{};

    for (final tx in rows) {
      final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
      final date = tx['date'] as DateTime?;
      if (date == null) continue;
      final categoryRaw = tx['category']?.toString().trim().toLowerCase();
      final category = (categoryRaw == null || categoryRaw.isEmpty)
          ? 'other'
          : categoryRaw;

      if (amount > 0) {
        totalIncome += amount;
      } else if (amount < 0) {
        final expense = amount.abs();
        totalExpenses += expense;
        expenseAmounts.add(expense);
        categoryTotals[category] = (categoryTotals[category] ?? 0) + expense;
        final monthKey =
            '${date.year}-${date.month.toString().padLeft(2, '0')}';
        monthlyTotals[monthKey] = (monthlyTotals[monthKey] ?? 0) + expense;
        final dayKey =
            '${date.year}-${date.month.toString().padLeft(2, '0')}-${date.day.toString().padLeft(2, '0')}';
        spendByDay[dayKey] = (spendByDay[dayKey] ?? 0) + expense;
        if (date.weekday <= DateTime.friday) {
          weekdayWeekend['weekday'] =
              (weekdayWeekend['weekday'] ?? 0) + expense;
        } else {
          weekdayWeekend['weekend'] =
              (weekdayWeekend['weekend'] ?? 0) + expense;
        }
      }
    }

    final sortedCats = categoryTotals.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final medianExpense = _median(expenseAmounts);
    final largestExpense = expenseAmounts.isEmpty
        ? 0
        : expenseAmounts.reduce(math.max);
    final netCashFlow = totalIncome - totalExpenses;
    final effectiveDays = analysisWindowDays ?? _estimateAnalysisDays(rows);
    final avgDailySpend = effectiveDays > 0
        ? (totalExpenses / effectiveDays)
        : 0;

    final trend = _buildSpendingTrend(monthlyTotals);
    final recurring = deepMode
        ? _detectRecurringCharges(rows)
        : const <String>[];
    final highSpendDays = deepMode
        ? _buildHighSpendDays(spendByDay)
        : const <String>[];
    final relevantTransactions = _buildRelevantTransactions(
      rows,
      userMessage: userMessage,
      limit: deepMode ? OfflineCoachConfig.deepInsightsRawTransactionLimit : 25,
    );

    return {
      'analysisWindowDays': allTime ? null : analysisWindowDays,
      'analysisWindowLabel': allTime
          ? 'all-time'
          : '${analysisWindowDays ?? effectiveDays}d',
      'totalIncome': totalIncome.toStringAsFixed(2),
      'totalExpenses': totalExpenses.toStringAsFixed(2),
      'netCashFlow': netCashFlow.toStringAsFixed(2),
      'avgDailySpend': avgDailySpend.toStringAsFixed(2),
      'medianExpense': medianExpense.toStringAsFixed(2),
      'largestExpense': largestExpense.toStringAsFixed(2),
      'transactionCount': rows.length,
      'categoryBreakdown': categoryTotals.map(
        (k, v) => MapEntry(k, v.toStringAsFixed(2)),
      ),
      'topCategories': sortedCats.take(8).map((e) => e.key).toList(),
      'monthlyTotals': monthlyTotals.map(
        (k, v) => MapEntry(k, v.toStringAsFixed(2)),
      ),
      'weekdayWeekendSplit': weekdayWeekend.map(
        (k, v) => MapEntry(k, v.toStringAsFixed(2)),
      ),
      'spendingTrend': trend,
      'recurringSubscriptions': recurring,
      'highSpendDays': highSpendDays,
      'sampleTransactions': relevantTransactions,
      'monthlyBurnRate': totalExpenses.toStringAsFixed(2),
    };
  }

  int _estimateAnalysisDays(List<Map<String, dynamic>> rows) {
    final dates = rows
        .map((e) => e['date'] as DateTime?)
        .whereType<DateTime>()
        .toList();
    if (dates.isEmpty) return 1;
    dates.sort();
    return dates.last.difference(dates.first).inDays + 1;
  }

  double _median(List<double> values) {
    if (values.isEmpty) return 0;
    final sorted = [...values]..sort();
    final mid = sorted.length ~/ 2;
    if (sorted.length.isOdd) return sorted[mid];
    return (sorted[mid - 1] + sorted[mid]) / 2;
  }

  String _buildSpendingTrend(Map<String, double> monthlyTotals) {
    if (monthlyTotals.length < 2) return 'Not enough monthly data yet.';
    final months = monthlyTotals.keys.toList()..sort();
    final latest = monthlyTotals[months.last] ?? 0;
    final previous = monthlyTotals[months[months.length - 2]] ?? 0;
    if (previous <= 0) return 'Spending data is growing; baseline is limited.';
    final deltaPct = ((latest - previous) / previous) * 100;
    final direction = deltaPct >= 0 ? 'up' : 'down';
    return 'Latest month is ${deltaPct.abs().toStringAsFixed(1)}% $direction vs previous month.';
  }

  List<String> _detectRecurringCharges(List<Map<String, dynamic>> rows) {
    final groups = <String, List<Map<String, dynamic>>>{};
    for (final tx in rows) {
      final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
      if (amount >= 0) continue;
      final merchant = tx['merchant']?.toString().trim().toLowerCase() ?? '';
      final category =
          tx['category']?.toString().trim().toLowerCase() ?? 'other';
      final key = merchant.isNotEmpty ? merchant : category;
      groups.putIfAbsent(key, () => []).add(tx);
    }

    final recurring = <String>[];
    groups.forEach((key, items) {
      if (items.length < 2) return;
      final expenses =
          items
              .map((i) => ((i['amount'] as num?)?.toDouble() ?? 0).abs())
              .toList()
            ..sort();
      final minAmt = expenses.first;
      final maxAmt = expenses.last;
      final avgAmt = expenses.reduce((a, b) => a + b) / expenses.length;
      final stableAmount = avgAmt > 0 && ((maxAmt - minAmt) / avgAmt) <= 0.2;
      if (!stableAmount) return;

      final dates =
          items
              .map((i) => i['date'] as DateTime?)
              .whereType<DateTime>()
              .toList()
            ..sort();
      if (dates.length < 2) return;
      final gaps = <int>[];
      for (var i = 1; i < dates.length; i++) {
        gaps.add(dates[i].difference(dates[i - 1]).inDays.abs());
      }
      final avgGap = gaps.reduce((a, b) => a + b) / gaps.length;
      if (avgGap < 20 || avgGap > 40) return;

      recurring.add(
        '${_titleCase(key)} ~£${avgAmt.toStringAsFixed(2)} every ${avgGap.toStringAsFixed(0)} days (${dates.length} charges)',
      );
    });

    recurring.sort();
    return recurring.take(12).toList();
  }

  List<String> _buildHighSpendDays(Map<String, double> spendByDay) {
    final days = spendByDay.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    return days
        .take(10)
        .map((e) => '${e.key}: £${e.value.toStringAsFixed(2)}')
        .toList();
  }

  List<String> _buildRelevantTransactions(
    List<Map<String, dynamic>> rows, {
    required String userMessage,
    required int limit,
  }) {
    final queryWords = userMessage
        .toLowerCase()
        .split(RegExp(r'[^a-z0-9]+'))
        .where((w) => w.length >= 3)
        .toSet();

    final scored = <Map<String, dynamic>>[];
    for (final tx in rows) {
      final date = tx['date'] as DateTime?;
      if (date == null) continue;
      final amount = (tx['amount'] as num?)?.toDouble() ?? 0;
      final category = tx['category']?.toString().trim() ?? 'other';
      final merchant = tx['merchant']?.toString().trim() ?? '';
      final note = tx['note']?.toString().trim() ?? '';
      final haystack = '$category $merchant $note'.toLowerCase();

      var score = 0.0;
      for (final w in queryWords) {
        if (haystack.contains(w)) score += 6;
      }
      score += amount < 0 ? 2 : 0;
      score += (amount.abs() / 100).clamp(0, 8).toDouble();
      final recencyDays = DateTime.now().difference(date).inDays;
      score += (30 - recencyDays).clamp(0, 30) / 10;

      scored.add({
        'score': score,
        'date': date,
        'amount': amount,
        'category': category,
        'merchant': merchant,
        'note': note,
      });
    }

    scored.sort((a, b) {
      final byScore = (b['score'] as double).compareTo(a['score'] as double);
      if (byScore != 0) return byScore;
      return (b['date'] as DateTime).compareTo(a['date'] as DateTime);
    });

    return scored.take(limit).map((tx) {
      final date = tx['date'] as DateTime;
      final amount = tx['amount'] as double;
      final category = tx['category'] as String;
      final merchant = tx['merchant'] as String;
      final note = tx['note'] as String;
      final title = merchant.isNotEmpty ? merchant : category;
      final desc = note.isNotEmpty ? ' | $note' : '';
      return '${date.toIso8601String().split('T').first} | '
          '${amount >= 0 ? '+' : '-'}£${amount.abs().toStringAsFixed(2)} | '
          '$title ($category)$desc';
    }).toList();
  }

  String _titleCase(String input) {
    final words = input
        .split(RegExp(r'\s+'))
        .where((w) => w.isNotEmpty)
        .map((w) => '${w[0].toUpperCase()}${w.substring(1)}');
    return words.join(' ');
  }
}

class _TypingDotsIndicator extends StatefulWidget {
  const _TypingDotsIndicator();

  @override
  State<_TypingDotsIndicator> createState() => _TypingDotsIndicatorState();
}

class _TypingDotsIndicatorState extends State<_TypingDotsIndicator>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            final delay = i * 0.2;
            final t = (_controller.value - delay).clamp(0.0, 1.0);
            final opacity = 0.3 + 0.7 * math.sin(t * math.pi);
            return Container(
              margin: EdgeInsets.only(right: i < 2 ? 4 : 0),
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: AppColors.primary.withValues(alpha: opacity),
                shape: BoxShape.circle,
              ),
            );
          }),
        );
      },
    );
  }
}
