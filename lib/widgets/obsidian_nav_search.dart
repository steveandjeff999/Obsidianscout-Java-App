import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../l10n/app_localizations.dart';
import '../theme/obsidian_ui_theme.dart';

/// Extra search terms per page. Mirrors PAGE_SEARCH_KEYWORDS in the website's
/// js/layout/navigation.js, plus the app-only pages, so both sidebars find the same things.
const Map<String, List<String>> kPageSearchKeywords = {
  'dashboard': ['home', 'main', 'overview', 'summary', 'inicio', 'panel'],
  'my-assignments': ['tasks', 'todo', 'assigned', 'schedule', 'mis tareas', 'asignaciones'],
  'scout': ['match scouting', 'form', 'entry', 'submit', 'partido', 'formulario'],
  'pit-scout': ['pits', 'inspection', 'robot specs', 'dimensions', 'inspeccion', 'foso'],
  'qual-scout': ['qualitative', 'subjective', 'notes', 'defense', 'driver', 'cualitativo', 'notas'],
  'prescout': ['pre-scouting', 'past events', 'videos', 'research', 'pre-scout'],
  'qr-scanner': ['camera', 'scan', 'jab', 'qr code', 'barcode', 'offline sync', 'transfer', 'escaner'],
  'scout-history': ['history', 'offline storage', 'cache', 'submissions', 'entries', 'historial'],
  'match-predictions': ['predictions', 'guess', 'pick winner', 'pronosticos'],
  'prediction-leaderboard': ['leaderboard', 'predictions', 'points', 'standings', 'clasificacion'],
  'custom-analytics': ['custom charts', 'builder', 'metrics', 'custom tables', 'sql', 'tablas', 'graficos'],
  'data-validation': ['verify', 'audit', 'anomalies', 'errors', 'fix data', 'validacion', 'auditoria'],
  'all-data': ['raw entries', 'table', 'export', 'csv', 'spreadsheet', 'todos los datos'],
  'match-data': ['breakdown', 'match entries', 'scores', 'datos de partidos'],
  'qual-data': ['qualitative notes', 'ratings', 'comments', 'datos cualitativos'],
  'pit-data': ['pit entries', 'photos', 'specifications', 'datos de pits'],
  'analytics': ['graphs', 'averages', 'leaderboard', 'opr', 'epa', 'analiticas'],
  'compare': ['comparison', 'head to head', 'compare teams', 'side by side', 'comparar'],
  'graphs': ['charts', 'scatter', 'box plot', 'bar chart', 'trends', 'graficos'],
  'teams': ['team list', 'roster', 'profiles', 'lookup', 'equipos'],
  'rankings': ['standings', 'leaderboard', 'rank', 'rp', 'ranking points', 'clasificacion'],
  'projected-rankings': ['projections', 'forecast', 'future standings', 'simulations', 'clasificacion proyectada'],
  'qual-rankings': ['driver rankings', 'defense rankings', 'qual ratings', 'ranking cualitativo'],
  'matches': ['match schedule', 'results', 'scores', 'partidos', 'horario'],
  'predictor': ['match predictor', 'win probability', 'score prediction', 'pronostico'],
  'event-predictor': ['event simulation', 'playoffs', 'bracket', 'pronostico de evento'],
  'alliances': ['alliance selection', 'partners', 'captain', 'picks', 'alianzas'],
  'alliance-selection': ['draft board', 'captain board', 'seleccion de alianzas'],
  'pick-list': ['pick list', 'picklist', 'ranking', 'draft order', 'do not pick', 'dnp', 'lista de seleccion'],
  'match-planning': ['strategy', 'whiteboard', 'game plan', 'match plan', 'planificacion'],
  'match-checklist': ['pre-match', 'checklist', 'drive team', 'on the field', 'pit crew', 'lista de verificacion'],
  'battery-tracker': ['battery', 'batteries', 'rotation', 'charging', 'pit battery', 'drive team', 'bateria', 'baterias'],
  'events': ['event list', 'competitions', 'regional', 'district', 'eventos'],
  'scout-assignments': ['scout assignments', 'matrix', 'scheduler', 'assign scouts', 'asignar scouts'],
  'users': ['accounts', 'roster', 'roles', 'permissions', 'team members', 'usuarios'],
  'chat': ['messages', 'team chat', 'conversations', 'mensajes'],
  'event-info': ['announcements', 'event info', 'files', 'documents', 'photos', 'pit map', 'schedule', 'informacion del evento'],
  'banners': ['announcements', 'notifications', 'alerts', 'notice', 'avisos'],
  'shared-links': ['public links', 'external sharing', 'enlaces compartidos'],
  'admin-settings': ['admin', 'config editor', 'form config', 'system settings', 'permissions', 'security', 'configuracion de admin'],
  'default-configs': ['schema presets', 'game config', 'form config', 'configuraciones predeterminadas'],
  'schema-history': ['config history', 'schema versions', 'revisions', 'historial'],
  'config-migration': ['schema migration', 'config upgrade', 'remap fields', 'migracion'],
  'theme-editor': ['theme', 'colors', 'appearance', 'branding', 'tema', 'colores'],
  'scouter-report': ['scouter stats', 'accuracy', 'contributions', 'leaderboard', 'reporte'],
  'cluster-management': ['server nodes', 'cluster', 'hosts', 'servidores'],
  'storage-manager': ['database storage', 'files', 'backups', 'disk', 'almacenamiento'],
  'error-reports': ['crash logs', 'client errors', 'diagnostics', 'reportes de errores'],
  'fcm-settings': ['push notifications', 'firebase', 'fcm', 'notificaciones'],
  'settings': ['preferences', 'config', 'dark mode', 'theme', 'language', 'color', 'cache', 'configuracion'],
  'backup': ['export', 'import', 'data sharing', 'json export', 'copia de seguridad'],
  'migration': ['database migration', 'postgres', 'sqlite', 'transfer', 'migracion'],
  'contact': ['support', 'email', 'bug report', 'feedback', 'contacto'],
};

/// True when every word of [query] appears in the nav item's page id, label,
/// subtitle or search keywords (same rule as the website's sidebar search).
bool navItemMatchesQuery(BuildContext context, Map<String, dynamic> item, String query) {
  final tokens = query.trim().toLowerCase().split(RegExp(r'\s+')).where((t) => t.isNotEmpty);
  if (tokens.isEmpty) return true;
  final pageId = item['pageId'] as String? ?? '';
  final label = context.tr(item['labelKey'] as String? ?? '');
  final subKey = item['subKey'] as String?;
  final subtitle = subKey != null ? context.tr(subKey) : '';
  final keywords = (kPageSearchKeywords[pageId] ?? const []).join(' ');
  final haystack = '$pageId $label $subtitle $keywords'.toLowerCase();
  return tokens.every(haystack.contains);
}

/// Search box for the navigation drawer and desktop sidebar.
/// Enter opens the highlighted match, arrow keys move the highlight, Escape clears.
class ObsidianNavSearchField extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSubmitted;
  final ValueChanged<int>? onMoveSelection;
  final bool compact;
  final String? shortcutHint;

  const ObsidianNavSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSubmitted,
    this.onMoveSelection,
    this.compact = false,
    this.shortcutHint,
  });

  void _clear() {
    controller.clear();
    onChanged('');
  }

  @override
  Widget build(BuildContext context) {
    final isDark = ObsidianUITheme.isDark(context);
    final borderColor = ObsidianUITheme.getBorderColor(context);
    final primaryAccent = ObsidianUITheme.getPrimaryAccent(context);
    final secondaryText = ObsidianUITheme.getSecondaryTextColor(context);
    final radius = ObsidianUITheme.getButtonRadius(context, fallback: 10.0).clamp(4.0, 16.0);
    final fontSize = compact ? 12.5 : 14.0;

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (node, event) {
        if (event is! KeyDownEvent && event is! KeyRepeatEvent) return KeyEventResult.ignored;
        final key = event.logicalKey;
        if (key == LogicalKeyboardKey.arrowDown && onMoveSelection != null) {
          onMoveSelection!(1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.arrowUp && onMoveSelection != null) {
          onMoveSelection!(-1);
          return KeyEventResult.handled;
        }
        if (key == LogicalKeyboardKey.escape) {
          _clear();
          focusNode.unfocus();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, value, _) {
          return TextField(
            controller: controller,
            focusNode: focusNode,
            onChanged: onChanged,
            onSubmitted: (_) => onSubmitted(),
            textInputAction: TextInputAction.go,
            autocorrect: false,
            enableSuggestions: false,
            style: TextStyle(fontSize: fontSize, color: ObsidianUITheme.getPrimaryTextColor(context)),
            decoration: InputDecoration(
              isDense: true,
              hintText: context.tr('sidebar.search.placeholder', 'Search pages...'),
              hintStyle: TextStyle(fontSize: fontSize, color: secondaryText),
              prefixIcon: Icon(Icons.search_rounded, size: compact ? 18.0 : 20.0, color: secondaryText),
              prefixIconConstraints: BoxConstraints(minWidth: compact ? 34.0 : 40.0),
              suffixIcon: value.text.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close_rounded, size: compact ? 16.0 : 18.0, color: secondaryText),
                      tooltip: context.tr('sidebar.search.clear', 'Clear search'),
                      onPressed: _clear,
                    )
                  : (shortcutHint != null
                      ? Padding(
                          padding: const EdgeInsets.only(right: 8.0),
                          child: Center(
                            widthFactor: 1.0,
                            child: Container(
                              padding: const EdgeInsets.symmetric(horizontal: 5.0, vertical: 1.5),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(4.0),
                                border: Border.all(color: borderColor),
                              ),
                              child: Text(shortcutHint!, style: TextStyle(fontSize: 10.0, color: secondaryText)),
                            ),
                          ),
                        )
                      : null),
              filled: true,
              fillColor: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.04),
              contentPadding: EdgeInsets.symmetric(vertical: compact ? 9.0 : 12.0),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radius),
                borderSide: BorderSide(color: borderColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radius),
                borderSide: BorderSide(color: borderColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(radius),
                borderSide: BorderSide(color: primaryAccent, width: 1.4),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Shown in place of the nav list when a search has no matches.
class ObsidianNavSearchEmpty extends StatelessWidget {
  const ObsidianNavSearchEmpty({super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 24.0, horizontal: 12.0),
      child: Text(
        context.tr('sidebar.search.no_results', 'No matching pages'),
        textAlign: TextAlign.center,
        style: TextStyle(fontSize: 12.5, color: ObsidianUITheme.getSecondaryTextColor(context)),
      ),
    );
  }
}
