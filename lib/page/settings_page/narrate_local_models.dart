import 'package:anx_reader/l10n/generated/L10n.dart';
import 'package:anx_reader/service/tts/local/local_tts_model_catalog.dart';
import 'package:anx_reader/service/tts/local/local_tts_model_manager.dart';
import 'package:anx_reader/service/tts/tts_service.dart' as tts_svc;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Model download / management section shown when the local TTS service is
/// selected. Models are curated in [kLocalTtsModelCatalog] and installed
/// under the application support directory.
class LocalTtsModelsSection extends ConsumerStatefulWidget {
  final VoidCallback? onSelectionChanged;

  const LocalTtsModelsSection({super.key, this.onSelectionChanged});

  @override
  ConsumerState<LocalTtsModelsSection> createState() =>
      _LocalTtsModelsSectionState();
}

class _LocalTtsModelsSectionState extends ConsumerState<LocalTtsModelsSection> {
  String? _selectedVoiceId;

  @override
  void initState() {
    super.initState();
    _selectedVoiceId =
        tts_svc.getTtsService('local').provider.getSelectedVoice();
  }

  String? get _selectedModelId =>
      _selectedVoiceId?.split('#').firstOrNull;

  void _useModel(LocalTtsModelCatalogEntry entry) {
    tts_svc
        .getTtsService('local')
        .provider
        .setSelectedVoice(localTtsVoiceId(entry.id, 0));
    setState(() {
      _selectedVoiceId = localTtsVoiceId(entry.id, 0);
    });
    widget.onSelectionChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final statuses = ref.watch(localTtsModelsProvider);
    final anyInstalled = statuses.values
        .any((s) => s.phase == LocalTtsModelPhase.installed);
    final l10n = L10n.of(context);

    return Padding(
      padding: const EdgeInsets.fromLTRB(16.0, 8.0, 16.0, 16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.settingsNarrateLocalTtsTip,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
          ),
          const SizedBox(height: 8),
          for (final entry in kLocalTtsModelCatalog)
            _buildModelTile(entry, statuses[entry.id], anyInstalled),
        ],
      ),
    );
  }

  Widget _buildModelTile(
    LocalTtsModelCatalogEntry entry,
    LocalTtsModelStatus? status,
    bool anyInstalled,
  ) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final phase = status?.phase ?? LocalTtsModelPhase.notInstalled;
    final isSelected = _selectedModelId == entry.id;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Container(
        padding: const EdgeInsets.all(12.0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected
                ? theme.colorScheme.primary
                : theme.colorScheme.outlineVariant,
          ),
          color: isSelected
              ? theme.colorScheme.primaryContainer.withAlpha(80)
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Flexible(
                            child: Text(
                              entry.displayName,
                              style: theme.textTheme.titleSmall,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (!anyInstalled && entry.isDefault) ...[
                            const SizedBox(width: 6),
                            _buildBadge(l10n.settingsNarrateLocalTtsRecommended),
                          ],
                          if (isSelected) ...[
                            const SizedBox(width: 6),
                            _buildBadge(l10n.settingsNarrateLocalTtsInUse),
                          ],
                        ],
                      ),
                      if (entry.description.isNotEmpty)
                        Text(
                          entry.description,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      Text(
                        '${entry.languages} · ≈${entry.approxSizeMb}MB · '
                        '${l10n.settingsNarrateLocalTtsVoicesLabel(entry.numSpeakers)}',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildAction(entry, phase, status),
              ],
            ),
            if (phase == LocalTtsModelPhase.downloading) ...[
              const SizedBox(height: 10),
              LinearProgressIndicator(
                value: status!.progress <= 0 ? null : status.progress,
              ),
              const SizedBox(height: 4),
              Text(
                '${(status.progress * 100).toStringAsFixed(0)}%',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildBadge(String label) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        label,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSecondaryContainer,
            ),
      ),
    );
  }

  Widget _buildAction(
    LocalTtsModelCatalogEntry entry,
    LocalTtsModelPhase phase,
    LocalTtsModelStatus? status,
  ) {
    final l10n = L10n.of(context);
    switch (phase) {
      case LocalTtsModelPhase.installed:
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              tooltip: l10n.settingsNarrateLocalTtsDelete,
              icon: const Icon(Icons.delete_outline),
              onPressed: () async {
                await ref.read(localTtsModelsProvider.notifier).delete(entry.id);
                if (mounted) setState(() {});
              },
            ),
            if (_selectedModelId != entry.id)
              TextButton(
                onPressed: () => _useModel(entry),
                child: Text(l10n.settingsNarrateLocalTtsUse),
              ),
          ],
        );
      case LocalTtsModelPhase.downloading:
        return TextButton(
          onPressed: () =>
              ref.read(localTtsModelsProvider.notifier).cancelDownload(entry.id),
          child: Text(l10n.settingsNarrateLocalTtsCancel),
        );
      case LocalTtsModelPhase.extracting:
        return const SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(strokeWidth: 2),
        );
      case LocalTtsModelPhase.failed:
        return TextButton(
          onPressed: () => ref.read(localTtsModelsProvider.notifier).download(entry.id),
          child: Text(l10n.settingsNarrateLocalTtsFailed),
        );
      case LocalTtsModelPhase.notInstalled:
        return FilledButton.tonal(
          onPressed: () => ref.read(localTtsModelsProvider.notifier).download(entry.id),
          child: Text(l10n.settingsNarrateLocalTtsDownload),
        );
    }
  }
}
