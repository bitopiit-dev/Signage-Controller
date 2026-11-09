import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:desktop_drop/desktop_drop.dart';
import 'package:path/path.dart' as p;
import '../models/playlist_item.dart';
import '../core/constants.dart';
import '../utils/media_utils.dart';

/// Media library + running order.
///
/// The list is flat so drag-to-reorder always matches the real playback
/// order. Filter chips narrow the view; reordering is available in "ALL".
class EnterpriseLibrary extends StatefulWidget {
  final double width;
  final List<PlaylistItem> playlist;
  final String? currentFilename;
  final int? selectedIndex;
  final Set<int> selectedIndices;
  final bool busy;
  final String mediaDir;
  final Function(int) onItemSelected;
  final Function(int)? onItemDoubleTap;
  final Function(int, int) onItemReorder;
  final Function(int) onToggleSelect;
  final Function(bool)? onSelectAll;
  final VoidCallback onDeleteSelected;
  final VoidCallback onAddMedia;
  final VoidCallback onAddYoutube;
  final Function(int)? onEditItem;
  final Function(List<String>)? onFilesDropped;

  /// Optional panel shown above the list (video conversion progress).
  final Widget? jobsPanel;

  const EnterpriseLibrary({
    super.key,
    this.width = 400,
    required this.playlist,
    this.currentFilename,
    required this.selectedIndex,
    required this.selectedIndices,
    this.busy = false,
    this.mediaDir = '',
    required this.onItemSelected,
    this.onItemDoubleTap,
    required this.onItemReorder,
    required this.onToggleSelect,
    this.onSelectAll,
    required this.onDeleteSelected,
    required this.onAddMedia,
    required this.onAddYoutube,
    this.onEditItem,
    this.onFilesDropped,
    this.jobsPanel,
  });

  @override
  State<EnterpriseLibrary> createState() => _EnterpriseLibraryState();
}

enum _Filter { all, video, audio, image, docs, youtube }

class _EnterpriseLibraryState extends State<EnterpriseLibrary> {
  _Filter _filter = _Filter.all;
  bool _isDragging = false;

  bool _matches(PlaylistItem item) {
    switch (_filter) {
      case _Filter.all:
        return true;
      case _Filter.video:
        return item.type == MediaType.video || item.type == MediaType.movie;
      case _Filter.audio:
        return item.type == MediaType.audio;
      case _Filter.image:
        return item.type == MediaType.image;
      case _Filter.docs:
        return item.type == MediaType.pdf || item.type == MediaType.document;
      case _Filter.youtube:
        return item.type == MediaType.youtube;
    }
  }

  int _count(_Filter f) {
    final prev = _filter;
    _filter = f;
    final c = widget.playlist.where(_matches).length;
    _filter = prev;
    return c;
  }

  @override
  Widget build(BuildContext context) {
    final visible = <int>[
      for (var i = 0; i < widget.playlist.length; i++)
        if (_matches(widget.playlist[i])) i
    ];
    final canReorder = _filter == _Filter.all;
    final totalSeconds = widget.playlist.fold<int>(0, (a, b) => a + b.durationSeconds);

    return ClipRRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 15, sigmaY: 15),
        child: DropTarget(
          onDragEntered: (_) => setState(() => _isDragging = true),
          onDragExited: (_) => setState(() => _isDragging = false),
          onDragDone: (details) {
            setState(() => _isDragging = false);
            final paths = details.files.map((f) => f.path).toList();
            if (paths.isNotEmpty) {
              widget.onFilesDropped?.call(paths);
            }
          },
          child: Stack(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: widget.width,
                decoration: BoxDecoration(
                  color: _isDragging ? AppColors.accentCyan.withOpacity(0.12) : AppColors.surfaceNavy.withOpacity(0.7),
                  border: Border.all(
                    color: _isDragging ? AppColors.accentCyan : AppColors.glassWhite,
                    width: _isDragging ? 2 : 1,
                  ),
                ),
                child: Column(
                  children: [
                    _buildHeader(),
                    _buildFilters(),
                    _buildSelectionBar(totalSeconds),
                    if (widget.busy)
                      const LinearProgressIndicator(
                        minHeight: 2,
                        color: AppColors.accentCyan,
                        backgroundColor: Colors.transparent,
                      ),
                    if (widget.jobsPanel != null) widget.jobsPanel!,
                    Expanded(
                      child: widget.playlist.isEmpty
                          ? _EmptyLibrary(onAdd: widget.onAddMedia)
                          : ReorderableListView.builder(
                              padding: const EdgeInsets.fromLTRB(AppSpacing.s2, 4, AppSpacing.s2, AppSpacing.s2),
                              buildDefaultDragHandles: false,
                              itemCount: visible.length,
                              onReorder: (oldPos, newPos) {
                                if (!canReorder) return;
                                widget.onItemReorder(oldPos, newPos);
                              },
                              itemBuilder: (context, pos) {
                                final index = visible[pos];
                                final item = widget.playlist[index];
                                final tile = _MediaListItem(
                                  key: ValueKey('item_${item.filename}'),
                                  listPosition: pos,
                                  order: index + 1,
                                  item: item,
                                  canReorder: canReorder,
                                  isPlaying: item.filename == widget.currentFilename,
                                  isSelected: widget.selectedIndex == index,
                                  isMultiSelected: widget.selectedIndices.contains(index),
                                  mediaDir: widget.mediaDir,
                                  onTap: () => widget.onItemSelected(index),
                                  onPlay: widget.onItemDoubleTap != null ? () => widget.onItemDoubleTap!(index) : null,
                                  onEdit: widget.onEditItem != null ? () => widget.onEditItem!(index) : null,
                                  onToggleSelect: () => widget.onToggleSelect(index),
                                );
                                if (canReorder) {
                                  return ReorderableDragStartListener(
                                    key: ValueKey('drag_${item.filename}'),
                                    index: pos,
                                    child: tile,
                                  );
                                }
                                return tile;
                              },
                            ),
                    ),
                  ],
                ),
              ),
              if (_isDragging)
                Positioned.fill(
                  child: Container(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceNavy.withOpacity(0.92),
                      borderRadius: BorderRadius.circular(AppRadius.large),
                      border: Border.all(color: AppColors.accentCyan, width: 2),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(Icons.file_download_rounded, size: 54, color: AppColors.accentCyan),
                        const SizedBox(height: 12),
                        const Text(
                          'DROP FILES HERE TO ADD TO LIBRARY',
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w900, color: AppColors.accentCyan, letterSpacing: 1.5),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Supports Videos, Images, Audio, PDFs & YouTube Links',
                          style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.6)),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s3, AppSpacing.s3, AppSpacing.s2, AppSpacing.s1),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: AppColors.actionBlue.withOpacity(0.1),
              borderRadius: BorderRadius.circular(AppRadius.standard),
            ),
            child: const Icon(Icons.inventory_2_outlined, color: AppColors.actionBlue, size: 20),
          ),
          const SizedBox(width: 14),
          const Expanded(
            child: Text(
              'ADMIN PLAY GROUND',
              style: TextStyle(
                fontWeight: FontWeight.w900,
                letterSpacing: 1.5,
                fontSize: 13,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (widget.selectedIndices.isNotEmpty)
            _HeaderAction(
              icon: Icons.delete_sweep_rounded,
              color: AppColors.dangerRose,
              onPressed: widget.onDeleteSelected,
              tooltip: 'Delete Selected',
            ),
          _HeaderAction(
            icon: Icons.add_link_rounded,
            color: Colors.white70,
            onPressed: widget.onAddYoutube,
            tooltip: 'Add YouTube Link',
          ),
          _HeaderAction(
            icon: Icons.add_circle_rounded,
            color: AppColors.actionBlue,
            onPressed: widget.busy ? () {} : widget.onAddMedia,
            tooltip: 'Add Media',
          ),
        ],
      ),
    );
  }

  Widget _buildFilters() {
    const labels = {
      _Filter.all: 'ALL',
      _Filter.video: 'VIDEO',
      _Filter.audio: 'AUDIO',
      _Filter.image: 'IMAGE',
      _Filter.docs: 'DOCS',
      _Filter.youtube: 'YOUTUBE',
    };
    final availableFilters = _Filter.values.where((f) => f == _Filter.all || _count(f) > 0).toList();

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          final currentIndex = availableFilters.indexOf(_filter);
          if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
            final nextIndex = (currentIndex + 1) % availableFilters.length;
            setState(() => _filter = availableFilters[nextIndex]);
            return KeyEventResult.handled;
          } else if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
            final prevIndex = (currentIndex - 1 + availableFilters.length) % availableFilters.length;
            setState(() => _filter = availableFilters[prevIndex]);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: Builder(
        builder: (context) {
          final hasFocus = Focus.of(context).hasFocus;
          return Container(
            height: 42,
            decoration: BoxDecoration(
              border: Border.symmetric(
                horizontal: BorderSide(
                  color: hasFocus ? AppColors.accentCyan.withOpacity(0.4) : Colors.transparent,
                  width: 1,
                ),
              ),
            ),
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s2),
              children: _Filter.values.map((f) {
                final count = _count(f);
                if (f != _Filter.all && count == 0) return const SizedBox.shrink();
                final selected = _filter == f;
                return Padding(
                  padding: const EdgeInsets.only(right: 6, top: 6, bottom: 6),
                  child: Material(
                    color: Colors.transparent,
                    borderRadius: BorderRadius.circular(20),
                    child: InkWell(
                      onTap: () => setState(() => _filter = f),
                      borderRadius: BorderRadius.circular(20),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: selected ? AppColors.accentCyan.withOpacity(0.12) : Colors.white.withOpacity(0.03),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: selected ? AppColors.accentCyan.withOpacity(0.5) : AppColors.glassWhite,
                          ),
                        ),
                        child: Text(
                          '${labels[f]}  $count',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1,
                            color: selected ? AppColors.accentCyan : Colors.white54,
                          ),
                        ),
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          );
        },
      ),
    );
  }

  Widget _buildSelectionBar(int totalSeconds) {
    final allSelected =
        widget.playlist.isNotEmpty && widget.selectedIndices.length == widget.playlist.length;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.s3, 2, AppSpacing.s2, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '${widget.playlist.length} ITEMS • ${formatSeconds(totalSeconds)} LOOP',
              style: const TextStyle(
                  fontSize: 9, fontWeight: FontWeight.w800, letterSpacing: 1, color: Colors.white38),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (_filter != _Filter.all)
            const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Text('REORDER IN "ALL"',
                  style: TextStyle(fontSize: 8, color: Colors.white24, fontWeight: FontWeight.w800)),
            ),
          if (widget.onSelectAll != null && widget.playlist.isNotEmpty)
            Material(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              child: InkWell(
                onTap: () => widget.onSelectAll!(!allSelected),
                borderRadius: BorderRadius.circular(6),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Text(
                    allSelected ? 'CLEAR' : 'SELECT ALL',
                    style: const TextStyle(
                        fontSize: 9, fontWeight: FontWeight.w900, color: AppColors.accentCyan, letterSpacing: 1),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  final VoidCallback onAdd;
  const _EmptyLibrary({required this.onAdd});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.video_library_outlined, size: 48, color: Colors.white.withOpacity(0.15)),
            const SizedBox(height: 16),
            const Text('LIBRARY IS EMPTY',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w900, letterSpacing: 2, color: Colors.white38)),
            const SizedBox(height: 8),
            Text('Add videos, images, audio or PDFs.\nThey stream to every screen automatically.',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 11, color: Colors.white.withOpacity(0.3))),
            const SizedBox(height: 20),
            ElevatedButton.icon(
              onPressed: onAdd,
              icon: const Icon(Icons.add_rounded, size: 18),
              label: const Text('ADD MEDIA'),
            ),
          ],
        ),
      ),
    );
  }
}

class _MediaListItem extends StatelessWidget {
  final int listPosition;
  final int order;
  final PlaylistItem item;
  final bool canReorder;
  final bool isPlaying;
  final bool isSelected;
  final bool isMultiSelected;
  final String mediaDir;
  final VoidCallback onTap;
  final VoidCallback? onPlay;
  final VoidCallback? onEdit;
  final VoidCallback onToggleSelect;

  const _MediaListItem({
    super.key,
    required this.listPosition,
    required this.order,
    required this.item,
    required this.canReorder,
    required this.isPlaying,
    required this.isSelected,
    required this.isMultiSelected,
    required this.mediaDir,
    required this.onTap,
    this.onPlay,
    this.onEdit,
    required this.onToggleSelect,
  });

  @override
  Widget build(BuildContext context) {
    final highlight = isPlaying ? AppColors.successEmerald : AppColors.actionBlue;
    final active = isPlaying || isSelected;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: active ? highlight.withOpacity(0.08) : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.large),
        border: Border.all(
          color: active
              ? highlight.withOpacity(0.4)
              : (isMultiSelected ? Colors.white.withOpacity(0.1) : Colors.transparent),
        ),
        boxShadow: active
            ? [BoxShadow(color: highlight.withOpacity(0.1), blurRadius: 15, spreadRadius: -5)]
            : [],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          onDoubleTap: onPlay,
          borderRadius: BorderRadius.circular(AppRadius.large),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: [
                Padding(
                  padding: const EdgeInsets.all(4),
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    color: canReorder ? Colors.white.withOpacity(0.5) : Colors.white.withOpacity(0.15),
                    size: 18,
                  ),
                ),
                SizedBox(
                  width: 22,
                  child: Text(
                    '$order',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                        fontSize: 10, fontFamily: 'JetBrains Mono', color: Colors.white.withOpacity(0.3)),
                  ),
                ),
                const SizedBox(width: 4),
                _TypeBadge(type: item.type),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              item.filename,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                                color: active ? Colors.white : Colors.white.withOpacity(0.9),
                              ),
                            ),
                          ),
                          if (isPlaying) const _OnAirDot(),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        '${mediaTypeToString(item.type).toUpperCase()} • ${formatSeconds(item.durationSeconds)}'
                        ' • ${transitionTypeToString(item.transition)}'
                        '${item.volume < 0.999 ? ' • VOL ${(item.volume * 100).round()}%' : ''}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: Colors.white.withOpacity(0.4),
                          fontFamily: 'JetBrains Mono',
                        ),
                      ),
                    ],
                  ),
                ),
                if (item.type == MediaType.youtube && item.url != null)
                  _RowIcon(
                    icon: Icons.open_in_new_rounded,
                    color: const Color(0xFFFF0000),
                    tooltip: 'Open YouTube URL',
                    onTap: () => MediaUtils.openUrl(item.url!),
                  )
                else if ((item.type == MediaType.pdf || item.type == MediaType.document) && mediaDir.isNotEmpty)
                  _RowIcon(
                    icon: Icons.folder_open_rounded,
                    color: AppColors.actionBlue,
                    tooltip: 'Open local document/PDF file',
                    onTap: () => MediaUtils.openFile(p.join(mediaDir, item.filename)),
                  ),
                if (onPlay != null)
                  _RowIcon(
                    icon: isPlaying ? Icons.graphic_eq_rounded : Icons.play_arrow_rounded,
                    color: isPlaying ? AppColors.successEmerald : AppColors.accentCyan,
                    tooltip: 'Play on all screens now',
                    onTap: onPlay!,
                  ),
                if (onEdit != null)
                  _RowIcon(
                    icon: Icons.tune_rounded,
                    color: Colors.white54,
                    tooltip: 'Duration, volume & transition',
                    onTap: onEdit!,
                  ),
                SizedBox(
                  width: 32,
                  child: Transform.scale(
                    scale: 0.8,
                    child: Checkbox(
                      value: isMultiSelected,
                      onChanged: (_) => onToggleSelect(),
                      activeColor: AppColors.actionBlue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(4)),
                      side: BorderSide(color: Colors.white.withOpacity(0.2)),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RowIcon extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String tooltip;
  final VoidCallback onTap;
  const _RowIcon({required this.icon, required this.color, required this.tooltip, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.all(6),
            child: Icon(icon, size: 18, color: color),
          ),
        ),
      ),
    );
  }
}

class _OnAirDot extends StatelessWidget {
  const _OnAirDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(left: 6),
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: AppColors.successEmerald.withOpacity(0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: AppColors.successEmerald.withOpacity(0.4)),
      ),
      child: const Text('ON AIR',
          style: TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: AppColors.successEmerald, letterSpacing: 0.5)),
    );
  }
}

class _TypeBadge extends StatelessWidget {
  final MediaType type;
  const _TypeBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    IconData icon;
    Color color;

    switch (type) {
      case MediaType.video:
      case MediaType.movie:
        icon = Icons.play_circle_fill_rounded; color = const Color(0xFFFF9800); break;
      case MediaType.image:
        icon = Icons.image_rounded; color = AppColors.successEmerald; break;
      case MediaType.pdf:
      case MediaType.document:
        icon = Icons.description_rounded; color = AppColors.dangerRose; break;
      case MediaType.audio:
        icon = Icons.graphic_eq_rounded; color = AppColors.actionBlue; break;
      case MediaType.youtube:
        icon = Icons.smart_display_rounded; color = const Color(0xFFFF0000); break;
    }

    return Container(
      padding: const EdgeInsets.all(7),
      decoration: BoxDecoration(
        color: color.withOpacity(0.15),
        borderRadius: BorderRadius.circular(AppRadius.standard),
        border: Border.all(color: color.withOpacity(0.2), width: 0.5),
      ),
      child: Icon(icon, color: color, size: 16),
    );
  }
}

class _HeaderAction extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;
  final String tooltip;

  const _HeaderAction({
    required this.icon,
    required this.color,
    required this.onPressed,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: IconButton(
        icon: Icon(icon, color: color.withOpacity(0.8), size: 20),
        onPressed: onPressed,
        tooltip: tooltip,
        splashRadius: 20,
      ),
    );
  }
}
