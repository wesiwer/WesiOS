import 'package:flutter/material.dart';
import '../theme/app_theme.dart';
import '../localization/wesi_locale.dart';

/// Контекстное меню (ПКМ) + инфо-карточка при наведении.
/// Hover-карточка с IgnorePointer — без мерцания на краю лого.
class WesiContextMenu extends StatefulWidget {
  final String title;
  final String description;
  final String purpose;
  final List<Widget> children;

  const WesiContextMenu({
    super.key,
    required this.title,
    required this.description,
    required this.purpose,
    required this.children,
  });

  @override
  State<WesiContextMenu> createState() => _WesiContextMenuState();
}

class _WesiContextMenuState extends State<WesiContextMenu> {
  OverlayEntry? _hoverCard;
  bool _pending = false;

  void _showHoverCard() {
    if (_hoverCard != null || !mounted) return;

    final box = context.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;

    final offset = box.localToGlobal(Offset.zero);
    final size = box.size;

    // Справа от лого, не поверх — курсор остаётся на child
    final left = offset.dx + size.width + 12;
    final top = offset.dy;

    _hoverCard = OverlayEntry(
      builder: (_) => Positioned(
        left: left.clamp(8.0, MediaQuery.sizeOf(context).width - 320),
        top: top.clamp(8.0, MediaQuery.sizeOf(context).height - 280),
        child: IgnorePointer(
          child: Material(
            color: Colors.transparent,
            child: Container(
              width: 300,
              padding: EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppTheme.carbonDark.withOpacity(0.98),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                    color: AppTheme.accent.withOpacity(0.35)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.45),
                    blurRadius: 20,
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Container(
                        width: 28,
                        height: 28,
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [AppTheme.accent, Color(0xFFFFD700)],
                          ),
                          borderRadius: BorderRadius.circular(7),
                        ),
                        child: Icon(Icons.info_outline,
                            color: Colors.white, size: 16),
                      ),
                      SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          widget.title,
                          style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: AppTheme.textPrimary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  SizedBox(height: 12),
                  Text(
                    widget.description,
                    style: TextStyle(
                      fontSize: 13,
                      color: AppTheme.textSecondary,
                      height: 1.45,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    widget.purpose,
                    style: TextStyle(
                      fontSize: 12,
                      color: AppTheme.accent.withOpacity(0.85),
                      fontStyle: FontStyle.italic,
                      height: 1.35,
                    ),
                  ),
                  SizedBox(height: 10),
                  Divider(color: AppTheme.glassBorder.withOpacity(0.5)),
                  SizedBox(height: 6),
                  Text(
                    WesiLocale.get('click_to_open'),
                    style: TextStyle(
                      fontSize: 11,
                      color: AppTheme.textMuted.withOpacity(0.75),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_hoverCard!);
  }

  void _hideHoverCard() {
    _pending = false;
    _hoverCard?.remove();
    _hoverCard = null;
  }

  void _onEnter() {
    _pending = true;
    Future.delayed(const Duration(milliseconds: 280), () {
      if (_pending && mounted) _showHoverCard();
    });
  }

  void _onExit() => _hideHoverCard();

  void _showContextMenu(BuildContext context) {
    final box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero);

    showMenu(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx + box.size.width / 2,
        offset.dy + box.size.height / 2,
        offset.dx + box.size.width / 2 + 1,
        offset.dy + box.size.height / 2 + 1,
      ),
      color: AppTheme.carbonDark.withOpacity(0.98),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: AppTheme.accent.withOpacity(0.3)),
      ),
      items: [
        PopupMenuItem(
          enabled: false,
          padding: EdgeInsets.all(20),
          child: SizedBox(
            width: 280,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(widget.title,
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: AppTheme.textPrimary)),
                SizedBox(height: 12),
                Text(widget.description,
                    style: TextStyle(
                        fontSize: 13,
                        color: AppTheme.textSecondary,
                        height: 1.5)),
                SizedBox(height: 8),
                Text(widget.purpose,
                    style: TextStyle(
                        fontSize: 12,
                        color: AppTheme.accent.withOpacity(0.8),
                        fontStyle: FontStyle.italic)),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  void dispose() {
    _hideHoverCard();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Без Stack + Positioned.fill — они давали лишние hit-границы
    return MouseRegion(
      onEnter: (_) => _onEnter(),
      onExit: (_) => _onExit(),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onSecondaryTap: () => _showContextMenu(context),
        child: widget.children.length == 1
            ? widget.children.first
            : Row(mainAxisSize: MainAxisSize.min, children: widget.children),
      ),
    );
  }
}
