import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_service.dart';
import '../theme/obsidian_ui_theme.dart';
import '../widgets/ported_page_kit.dart';

/// The Local AI Assistant runs its model inside a web browser (WebGPU), so the app opens the
/// server's Assistant page in the browser instead of running a model itself.
class AssistantScreen extends StatelessWidget {
  final ApiService apiService;
  final bool isVisible;
  final bool isBarsVisible;

  const AssistantScreen({
    super.key,
    required this.apiService,
    this.isVisible = true,
    this.isBarsVisible = true,
  });

  Future<void> _openAssistant() async {
    final base = Uri.parse(apiService.currentServerUrl);
    final uri = base.replace(path: '${base.path.replaceAll(RegExp(r'/$'), '')}/assistant');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      await launchUrl(uri, mode: LaunchMode.platformDefault);
    }
  }

  @override
  Widget build(BuildContext context) {
    final primary = ObsidianUITheme.getPrimaryTextColor(context);
    final muted = ObsidianUITheme.getSecondaryTextColor(context);
    return PortedPageList(
      onRefresh: () async {},
      isBarsVisible: isBarsVisible,
      children: [
        PortedSection(
          title: 'Assistant',
          subtitle: 'Ask questions about your scouting data in plain English, such as "Top 5 teams by auto points".',
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'The assistant runs its AI model on your device, inside a web browser, so nothing is sent to an outside AI '
                'service. It needs a browser with WebGPU (recent Chrome or Edge on a laptop works best), so the app opens it there.',
                style: TextStyle(fontSize: 13.5, height: 1.45, color: primary),
              ),
              const SizedBox(height: 8),
              Text(
                'Sign in on the browser page if asked, then turn the assistant on under Personal Settings > Local AI. '
                "It's an experiment: don't rely on it at events.",
                style: TextStyle(fontSize: 12.5, height: 1.45, color: muted),
              ),
              const SizedBox(height: 14),
              FilledButton.icon(
                onPressed: _openAssistant,
                icon: const Icon(Icons.open_in_browser_rounded),
                label: const Text('Open Assistant in browser'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
