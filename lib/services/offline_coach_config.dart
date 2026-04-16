abstract final class OfflineCoachConfig {
  static const String runtime = 'LiteRT-LM';
  static const String runtimePackage =
      'com.google.ai.edge.litertlm:litertlm-android';
  static const String modelFamily = 'Gemma 4';
  static const String modelVariant = 'Gemma 4 E2B';
  static const String modelFormat = 'litertlm';
  static const String modelFileName = 'gemma-4-E2B-it.litertlm';
  static const String modelVersion = 'gemma4-e2b-it-2026-04';
  static const String modelDownloadUrl =
      'https://huggingface.co/litert-community/gemma-4-E2B-it-litert-lm/resolve/main/gemma-4-E2B-it.litertlm?download=1';

  static const int modelSizeBytes = 2583 * 1024 * 1024;
  static const int minSupportedAndroidSdk = 29;
  static const int minimumRamMb = 6144;
  static const int recommendedRamMb = 8192;
  static const int minimumFreeStorageMb = 4096;

  static const int maxPromptChars = 5000;
  static const int deepInsightsMaxPromptChars = 14000;
  static const int defaultInsightsDays = 30;
  static const int deepInsightsDays = 180;
  static const int deepInsightsRawTransactionLimit = 120;

  static const String onlineProvider = 'claude-haiku';
  static const String onlineFunctionRegion = 'us-central1';
  static const String onlineFunctionName = 'onlineCoachChat';
  static const String onlineModel = 'claude-haiku-4-5-20251001';

  static const List<String> safetyBoundaries = [
    'Do not recommend specific investment products, stocks, or funds.',
    'Do not give legally binding tax, accounting, or regulatory advice.',
    'Encourage the user to consult a licensed professional for complex decisions.',
    'Keep answers short, practical, and focused on personal finance and burn rate.',
  ];
}
