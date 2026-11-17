import 'package:flutter/material.dart';
import '../theme/obsidian_tokens.dart';

/// Plain page header matching the site: serif title, muted description, optional actions.
/// Mirrors `.main-content .card:has(h1)` in `design.css`.
class ObsidianPageHeader extends StatelessWidget {
  final String title;
  final String? description;
  final List<Widget> actions;
  final EdgeInsetsGeometry padding;

  const ObsidianPageHeader({
    super.key,
    required this.title,
    this.description,
    this.actions = const [],
    this.padding = const EdgeInsets.fromLTRB(0, 4, 0, 16),
  });

  @override
  Widget build(BuildContext context) {
    final t = ObsidianTokens.of(context);
    final width = MediaQuery.sizeOf(context).width;
    // clamp(2rem, 2.6vw, 2.6rem) on the site, scaled down for phones
    final titleSize = (width * 0.026).clamp(26.0, 38.0);

    final titleBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: ObsidianTokens.serif(
            base: TextStyle(color: t.ink, height: 1.08),
            size: titleSize,
            weight: FontWeight.w500,
          ),
        ),
        if (description != null && description!.isNotEmpty) ...[
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 640),
            child: Text(
              description!,
              style: TextStyle(color: t.muted, fontSize: 15, height: 1.55),
            ),
          ),
        ],
      ],
    );

    if (actions.isEmpty) {
      return Padding(padding: padding, child: titleBlock);
    }

    return Padding(
      padding: padding,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final narrow = constraints.maxWidth < 600;
          if (narrow) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                titleBlock,
                const SizedBox(height: 12),
                Wrap(spacing: 8, runSpacing: 8, children: actions),
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: titleBlock),
              const SizedBox(width: 16),
              Flexible(
                child: Wrap(
                  alignment: WrapAlignment.end,
                  spacing: 8,
                  runSpacing: 8,
                  children: actions,
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
