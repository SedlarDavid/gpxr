import 'package:flutter/material.dart';
import '../utils/theme.dart';
import '../widgets/map_view.dart';
import '../widgets/sidebar.dart';
import '../widgets/toolbar.dart';
import '../widgets/welcome_dialog.dart';

/// Below this width the side-by-side layout doesn't fit and we collapse
/// the sidebar into a draggable bottom panel that shares the screen with
/// the map.
const double _mobileBreakpoint = 900;

class EditorScreen extends StatefulWidget {
  const EditorScreen({super.key});

  @override
  State<EditorScreen> createState() => _EditorScreenState();
}

/// Min/max bounds for the desktop sidebar drag-to-resize handle. The
/// minimum keeps stat chips and tab labels legible; the cap stops the
/// sidebar from eating the entire window.
const double _sidebarMinWidth = 260;
const double _sidebarMaxWidth = 720;
const double _sidebarDefaultWidth = 340;

class _EditorScreenState extends State<EditorScreen> {
  /// Mobile only — when true the bottom panel is expanded to ~70% of the
  /// screen so the user can scroll waypoint/climb/split lists; when
  /// false it collapses to a 64 px header showing route stats and a tab
  /// chooser. Persisted only for the current session.
  bool _panelExpanded = false;

  /// Desktop only. Updated by the splitter on the right edge of the
  /// sidebar. Session-only — no localStorage so a fresh load always
  /// starts at the default; we can persist later if asked.
  double _sidebarWidth = _sidebarDefaultWidth;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      maybeShowWelcomeDialog(context);
    });
  }

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    return Scaffold(
      drawer: const GpxDrawer(),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isMobile = constraints.maxWidth < _mobileBreakpoint;
          if (!isMobile) {
            // Cap the sidebar so the map keeps at least 240 px of width
            // even if the user previously dragged the splitter very far
            // and then shrunk the window.
            final maxAllowed = (constraints.maxWidth - 240).clamp(
              _sidebarMinWidth,
              _sidebarMaxWidth,
            );
            final effectiveWidth = _sidebarWidth.clamp(
              _sidebarMinWidth,
              maxAllowed,
            );
            return Column(
              children: [
                const Toolbar(),
                Expanded(
                  child: Row(
                    children: [
                      Sidebar(width: effectiveWidth),
                      _SidebarResizeHandle(
                        onDrag: (delta) {
                          setState(() {
                            _sidebarWidth = (_sidebarWidth + delta).clamp(
                              _sidebarMinWidth,
                              maxAllowed,
                            );
                          });
                        },
                      ),
                      const Expanded(child: MapView()),
                    ],
                  ),
                ),
              ],
            );
          }
          return _MobileLayout(
            expanded: _panelExpanded,
            onToggle: () => setState(() => _panelExpanded = !_panelExpanded),
          );
        },
      ),
    );
  }
}

/// 6 px-wide vertical splitter that sits between the sidebar and the
/// map. Drags horizontally to resize the sidebar. Renders the resize
/// cursor on hover so the affordance is discoverable without a label.
class _SidebarResizeHandle extends StatefulWidget {
  const _SidebarResizeHandle({required this.onDrag});

  final ValueChanged<double> onDrag;

  @override
  State<_SidebarResizeHandle> createState() => _SidebarResizeHandleState();
}

class _SidebarResizeHandleState extends State<_SidebarResizeHandle> {
  bool _hover = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    final active = _hover || _dragging;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onHorizontalDragStart: (_) => setState(() => _dragging = true),
        onHorizontalDragEnd: (_) => setState(() => _dragging = false),
        onHorizontalDragCancel: () => setState(() => _dragging = false),
        onHorizontalDragUpdate: (d) => widget.onDrag(d.delta.dx),
        child: SizedBox(
          width: 6,
          child: Center(
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 120),
              width: active ? 3 : 1,
              color: active
                  ? AppTheme.primaryColor.withValues(alpha: 0.7)
                  : AppTheme.borderColor,
            ),
          ),
        ),
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    return Column(
      children: [
        const Toolbar(),
        Expanded(
          child: Stack(
            children: [
              const Positioned.fill(child: MapView()),
              Positioned(
                left: 0,
                right: 0,
                bottom: 0,
                child: _MobileSidebarPanel(
                  expanded: expanded,
                  onToggle: onToggle,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MobileSidebarPanel extends StatelessWidget {
  const _MobileSidebarPanel({required this.expanded, required this.onToggle});

  final bool expanded;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    AppTheme.subscribe(context);
    final mediaHeight = MediaQuery.of(context).size.height;
    // 48 here (not 44) to account for the 1 px top BoxDecoration border
    // and the inner handle's 44 px height — without the buffer the
    // collapsed Column overflows by 1 px and Flutter logs a layout
    // error in debug.
    final collapsedHeight = 48.0;
    // 78% gives enough room for the route stats header + tab bar + a
    // few list rows on phones without the inner Column ever needing to
    // overflow. Capped so it never eats the whole map on tablets.
    final expandedHeight = (mediaHeight * 0.78).clamp(360.0, 720.0);

    return AnimatedContainer(
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOutCubic,
      height: expanded ? expandedHeight : collapsedHeight,
      decoration: BoxDecoration(
        color: AppTheme.cardColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
        border: Border(top: BorderSide(color: AppTheme.borderColor)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        children: [
          InkWell(
            onTap: onToggle,
            child: SizedBox(
              height: 44,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 44,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppTheme.borderColor,
                      borderRadius: BorderRadius.circular(3),
                    ),
                  ),
                  Positioned(
                    right: 12,
                    child: Icon(
                      expanded
                          ? Icons.keyboard_arrow_down_rounded
                          : Icons.keyboard_arrow_up_rounded,
                      color: AppTheme.textSecondary,
                      size: 22,
                    ),
                  ),
                  Positioned(
                    left: 12,
                    child: Row(
                      children: [
                        Icon(
                          Icons.route_rounded,
                          size: 16,
                          color: AppTheme.textSecondary,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          expanded ? 'Hide details' : 'Route details',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: AppTheme.textSecondary,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const Expanded(child: Sidebar(mobile: true)),
            // Reserve the iOS home-indicator strip explicitly inside
            // the panel so the list's last row is never overlapped by
            // it. We did this with a SafeArea before, but Sidebar's
            // ListView didn't reliably reach its scroll extent when
            // wrapped that way — pushing the inset into the panel's
            // own Column avoids the issue.
            SizedBox(height: MediaQuery.of(context).viewPadding.bottom),
          ],
        ],
      ),
    );
  }
}
