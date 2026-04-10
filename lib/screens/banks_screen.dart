import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/bank_service.dart';
import '../theme/app_theme.dart';

class BanksScreen extends StatefulWidget {
  const BanksScreen({super.key});

  @override
  State<BanksScreen> createState() => _BanksScreenState();
}

class _BanksScreenState extends State<BanksScreen> with WidgetsBindingObserver {
  late final User _user;
  late final BankService _bankService;
  Map<String, bool> _status = const {'monzo': false, 'truelayer': false};
  bool _loadingStatus = true;
  String? _syncingProvider;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _user = FirebaseAuth.instance.currentUser!;
    _bankService = BankService(userEmail: _user.email);
    _refreshStatus();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _refreshStatus();
    }
  }

  Future<void> _refreshStatus() async {
    if (!mounted) return;
    setState(() => _loadingStatus = true);
    try {
      final status = await _bankService.fetchBankStatus(_user);
      if (!mounted) return;
      setState(() => _status = status);
    } catch (_) {
      if (!mounted) return;
      setState(() => _status = const {'monzo': false, 'truelayer': false});
    } finally {
      if (mounted) {
        setState(() => _loadingStatus = false);
      }
    }
  }

  Future<void> _syncProvider(String provider) async {
    if (!mounted) return;
    setState(() => _syncingProvider = provider);
    try {
      await _bankService.syncProvider(_user, provider);
      await _refreshStatus();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sync complete')));
    } catch (e) {
      if (!mounted) return;
      final message = e.toString().replaceFirst('Exception: ', '').trim();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            message.isEmpty ? 'Sync failed. Please try again.' : message,
          ),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _syncingProvider = null);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = _user.uid;

    return Scaffold(
      appBar: AppBar(title: const Text('Bank Accounts')),
      body: RefreshIndicator(
        onRefresh: _refreshStatus,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            const Text(
              'Connect your banks to automatically import transactions',
              style: TextStyle(color: AppColors.textMuted, fontSize: 14),
            ),
            const SizedBox(height: 20),
            _BankCard(
              name: 'Monzo',
              description:
                  'Import transactions directly from your Monzo account',
              color: AppColors.monzo,
              icon: Icons.account_balance_wallet,
              configured: _bankService.isMonzoConfigured,
              connected: _status['monzo'] == true,
              loading: _loadingStatus,
              syncing: _syncingProvider == 'monzo',
              onConnect: () => _bankService.connectMonzo(uid),
              onSync: () => _syncProvider('monzo'),
            ),
            const SizedBox(height: 12),
            _BankCard(
              name: 'Lloyds',
              description:
                  'Connect via TrueLayer to import transactions from Lloyds and other supported banks.',
              color: AppColors.lloyds,
              icon: Icons.account_balance,
              configured: _bankService.isTrueLayerConfigured,
              connected: _status['truelayer'] == true,
              loading: _loadingStatus,
              syncing: _syncingProvider == 'truelayer',
              onConnect: () => _bankService.connectLloyds(uid),
              onSync: () => _syncProvider('truelayer'),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(
                        Icons.info_outline,
                        color: AppColors.primary,
                        size: 20,
                      ),
                      SizedBox(width: 8),
                      Text(
                        'Setup Guide',
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _setupSection('Monzo', AppColors.monzo, [
                    'Go to developers.monzo.com and create an OAuth client',
                    'Set redirect URI to your Cloud Function URL',
                    'Configure MONZO_CLIENT_ID and MONZO_CLIENT_SECRET',
                  ]),
                  const SizedBox(height: 16),
                  _setupSection('Lloyds (via TrueLayer)', AppColors.lloyds, [
                    'Sign up at console.truelayer.com',
                    'Create a live TrueLayer app and configure the callback URL',
                    'Configure TRUELAYER_CLIENT_ID and TRUELAYER_CLIENT_SECRET',
                    'Choose Lloyds in the TrueLayer bank picker during connection.',
                  ]),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static Widget _setupSection(String title, Color color, List<String> steps) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 8),
        ...steps.asMap().entries.map(
          (e) => Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${e.key + 1}. ',
                  style: const TextStyle(
                    color: AppColors.textMuted,
                    fontSize: 13,
                  ),
                ),
                Expanded(
                  child: Text(
                    e.value,
                    style: const TextStyle(
                      color: AppColors.textMuted,
                      fontSize: 13,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _BankCard extends StatelessWidget {
  final String name;
  final String description;
  final Color color;
  final IconData icon;
  final bool configured;
  final bool connected;
  final bool loading;
  final bool syncing;
  final VoidCallback onConnect;
  final VoidCallback onSync;

  const _BankCard({
    required this.name,
    required this.description,
    required this.color,
    required this.icon,
    required this.configured,
    required this.connected,
    required this.loading,
    required this.syncing,
    required this.onConnect,
    required this.onSync,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
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
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: color,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      description,
                      style: const TextStyle(
                        color: AppColors.textMuted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (!configured)
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.warning_amber, color: AppColors.warning, size: 18),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'API keys not configured. Set up Cloud Functions to enable.',
                      style: TextStyle(color: AppColors.warning, fontSize: 12),
                    ),
                  ),
                ],
              ),
            )
          else if (loading)
            const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            )
          else if (connected)
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.success.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    children: const [
                      Icon(
                        Icons.check_circle,
                        color: AppColors.success,
                        size: 18,
                      ),
                      SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'Connected successfully.',
                          style: TextStyle(
                            color: AppColors.success,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: syncing ? null : onSync,
                    child: Text(syncing ? 'Syncing...' : 'Sync Now'),
                  ),
                ),
              ],
            )
          else
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onConnect,
                style: ElevatedButton.styleFrom(backgroundColor: color),
                child: Text('Connect $name'),
              ),
            ),
        ],
      ),
    );
  }
}
