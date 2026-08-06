import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/static_page_model.dart';
import 'package:palmnazi/services/admin_colors.dart';
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/services/audit_log_service.dart';
import 'package:palmnazi/services/static_page_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminStaticPagesScreen
//
// Lets an admin edit the platform's static pages (About Us, Privacy Policy,
// Terms of Service, Cookie Policy) without touching code. Each page is a
// title/subtitle plus a repeatable list of heading+body sections — see
// StaticPageModel. Public screens (about_screen.dart, StaticPageScreen in
// static_info_screen.dart) fall back to hardcoded defaults until a page is
// first saved here.
// ─────────────────────────────────────────────────────────────────────────────

final Logger _log = Logger(
  printer: PrettyPrinter(
    methodCount: 0,
    errorMethodCount: 8,
    lineLength: 100,
    colors: true,
    printEmojis: true,
  ),
);

// English-only seed values for a page's initial title (used only to
// pre-fill the editable "Page Title" field before an admin has saved
// anything for that slug) — not a display-only chrome label, so it isn't
// run through context.tr here.
const Map<String, String> _pageLabelsEn = {
  'about': 'About Us',
  'privacy-policy': 'Privacy Policy',
  'terms-of-service': 'Terms of Service',
  'cookie-policy': 'Cookie Policy',
};

String _pageLabel(BuildContext context, String slug) {
  switch (slug) {
    case 'about':
      return context.tr('admin_static_pages_label_about');
    case 'privacy-policy':
      return context.tr('admin_static_pages_label_privacy');
    case 'terms-of-service':
      return context.tr('admin_static_pages_label_terms');
    case 'cookie-policy':
      return context.tr('admin_static_pages_label_cookie');
    default:
      return slug;
  }
}

class AdminStaticPagesScreen extends StatelessWidget {
  const AdminStaticPagesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.all(20),
      children: StaticPageService.managedSlugs
          .map((slug) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _PageTile(slug: slug),
              ))
          .toList(),
    );
  }
}

class _PageTile extends StatelessWidget {
  final String slug;
  const _PageTile({required this.slug});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<StaticPageModel?>(
      stream: StaticPageService.stream(slug),
      builder: (context, snap) {
        final page = snap.data;
        return Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AdC.surface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: AdC.overlay(0.12)),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: AdC.teal.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.description_outlined,
                  color: AdC.teal, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_pageLabel(context, slug),
                      style: TextStyle(
                          color: AdC.textPri,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    page == null
                        ? context.tr('admin_static_pages_not_edited_yet')
                        : '${context.tr('admin_static_pages_last_edited_by_prefix')} ${page.updatedByEmail ?? context.tr('admin_static_pages_unknown_editor')}'
                            '${page.updatedAt != null ? " · ${_fmt(page.updatedAt!)}" : ""}',
                    style: TextStyle(color: AdC.textMute, fontSize: 11),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _openEditor(context, slug, page),
              icon: const Icon(Icons.edit_rounded, size: 14),
              label: Text(context.tr('admin_static_pages_edit_button')),
              style: OutlinedButton.styleFrom(
                foregroundColor: AdC.teal,
                side: BorderSide(color: AdC.teal.withValues(alpha: 0.4)),
              ),
            ),
          ]),
        );
      },
    );
  }

  String _fmt(DateTime d) => '${d.day}/${d.month}/${d.year}';

  void _openEditor(BuildContext context, String slug, StaticPageModel? page) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => _StaticPageEditorScreen(slug: slug, initial: page),
      ),
    );
  }
}

class _StaticPageEditorScreen extends StatefulWidget {
  final String slug;
  final StaticPageModel? initial;
  const _StaticPageEditorScreen({required this.slug, this.initial});

  @override
  State<_StaticPageEditorScreen> createState() =>
      _StaticPageEditorScreenState();
}

class _StaticPageEditorScreenState extends State<_StaticPageEditorScreen> {
  late final TextEditingController _titleCtrl;
  late final TextEditingController _subtitleCtrl;
  late final TextEditingController _lastUpdatedCtrl;
  final List<_SectionEditRow> _sections = [];
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final p = widget.initial;
    _titleCtrl = TextEditingController(
        text: p?.title ?? _pageLabelsEn[widget.slug] ?? '');
    _subtitleCtrl = TextEditingController(text: p?.subtitle ?? '');
    _lastUpdatedCtrl = TextEditingController(text: p?.lastUpdatedLabel ?? '');
    if (p != null && p.sections.isNotEmpty) {
      _sections.addAll(p.sections.map((s) => _SectionEditRow.from(s)));
    } else {
      _sections.add(_SectionEditRow());
    }
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _subtitleCtrl.dispose();
    _lastUpdatedCtrl.dispose();
    for (final s in _sections) {
      s.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final pageLabel = _pageLabel(context, widget.slug);
    setState(() => _saving = true);
    try {
      final page = StaticPageModel(
        slug: widget.slug,
        title: _titleCtrl.text.trim(),
        subtitle: _subtitleCtrl.text.trim(),
        lastUpdatedLabel: _lastUpdatedCtrl.text.trim(),
        sections: _sections
            .where((s) => s.bodyCtrl.text.trim().isNotEmpty)
            .map((s) => StaticPageSection(
                heading: s.headingCtrl.text.trim(),
                body: s.bodyCtrl.text.trim()))
            .toList(),
      );
      await StaticPageService.save(page);
      AuditLogService.log(
          action: 'update',
          module: 'StaticPage',
          targetId: widget.slug,
          targetLabel: pageLabel);
      _log.i('✅ [AdminStaticPagesScreen] Saved ${widget.slug}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _log.e('❌ [AdminStaticPagesScreen] Save failed', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              '${context.tr('admin_static_pages_error_save_failed_prefix')} $e'),
          backgroundColor: AdC.red,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AdC.bg,
      appBar: AppBar(
        backgroundColor: AdC.surface,
        title: Text(
            '${context.tr('admin_static_pages_edit_title_prefix')} ${_pageLabel(context, widget.slug)}',
            style: TextStyle(color: AdC.textPri, fontSize: 16)),
        iconTheme: IconThemeData(color: AdC.textPri),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminField(
                  ctrl: _titleCtrl,
                  label: context.tr('admin_static_pages_field_page_title')),
              AdminField(
                  ctrl: _subtitleCtrl,
                  label: context.tr('admin_static_pages_field_subtitle'),
                  helperText: context.tr('admin_static_pages_subtitle_helper')),
              AdminField(
                  ctrl: _lastUpdatedCtrl,
                  label: context.tr('admin_static_pages_field_last_updated'),
                  hint: context.tr('admin_static_pages_hint_last_updated')),
              const SizedBox(height: 12),
              Text(context.tr('admin_static_pages_sections_heading'),
                  style: TextStyle(
                      color: AdC.textPri,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._sections.asMap().entries.map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: AdC.surface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AdC.overlay(0.12)),
                    ),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                          child: Text(
                              '${context.tr('admin_static_pages_section_prefix')} ${e.key + 1}',
                              style:
                                  TextStyle(color: AdC.textMute, fontSize: 12)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: AdC.red, size: 18),
                          onPressed: _sections.length == 1
                              ? null
                              : () => setState(
                                  () => _sections.removeAt(e.key).dispose()),
                        ),
                      ]),
                      AdminField(
                          ctrl: e.value.headingCtrl,
                          label: context.tr('admin_static_pages_field_heading'),
                          helperText:
                              context.tr('admin_static_pages_heading_helper')),
                      AdminField(
                          ctrl: e.value.bodyCtrl,
                          label: context.tr('admin_static_pages_field_body'),
                          maxLines: 5),
                    ]),
                  )),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _sections.add(_SectionEditRow())),
                icon: const Icon(Icons.add_rounded, color: AdC.teal, size: 18),
                label: Text(context.tr('admin_static_pages_add_section'),
                    style: const TextStyle(color: AdC.teal)),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: _saving
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.black38))
                      : const Icon(Icons.save_rounded, size: 18),
                  label: Text(_saving
                      ? context.tr('admin_static_pages_saving')
                      : context.tr('admin_static_pages_save_page')),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AdC.teal,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionEditRow {
  final TextEditingController headingCtrl;
  final TextEditingController bodyCtrl;

  _SectionEditRow()
      : headingCtrl = TextEditingController(),
        bodyCtrl = TextEditingController();

  _SectionEditRow.from(StaticPageSection s)
      : headingCtrl = TextEditingController(text: s.heading),
        bodyCtrl = TextEditingController(text: s.body);

  void dispose() {
    headingCtrl.dispose();
    bodyCtrl.dispose();
  }
}
