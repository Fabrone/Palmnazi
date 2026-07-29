import 'package:flutter/material.dart';
import 'package:logger/logger.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/static_page_model.dart';
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

const _kSurface = Color(0xFF111827);
const _kTeal = Color(0xFF14FFEC);
const _kRed = Color(0xFFCF6679);

const Map<String, String> _pageLabels = {
  'about': 'About Us',
  'privacy-policy': 'Privacy Policy',
  'terms-of-service': 'Terms of Service',
  'cookie-policy': 'Cookie Policy',
};

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
            color: _kSurface,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white12),
          ),
          child: Row(children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _kTeal.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.description_outlined,
                  color: _kTeal, size: 18),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_pageLabels[slug] ?? slug,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 3),
                  Text(
                    page == null
                        ? 'Not edited yet — showing built-in default copy'
                        : 'Last edited by ${page.updatedByEmail ?? "unknown"}'
                            '${page.updatedAt != null ? " · ${_fmt(page.updatedAt!)}" : ""}',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => _openEditor(context, slug, page),
              icon: const Icon(Icons.edit_rounded, size: 14),
              label: const Text('Edit'),
              style: OutlinedButton.styleFrom(
                foregroundColor: _kTeal,
                side: BorderSide(color: _kTeal.withValues(alpha: 0.4)),
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
    _titleCtrl =
        TextEditingController(text: p?.title ?? _pageLabels[widget.slug] ?? '');
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
          targetLabel: _pageLabels[widget.slug] ?? widget.slug);
      _log.i('✅ [AdminStaticPagesScreen] Saved ${widget.slug}');
      if (mounted) Navigator.pop(context);
    } catch (e) {
      _log.e('❌ [AdminStaticPagesScreen] Save failed', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Could not save: $e'),
          backgroundColor: _kRed,
        ));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: _kSurface,
        title: Text('Edit ${_pageLabels[widget.slug] ?? widget.slug}',
            style: const TextStyle(color: Colors.white, fontSize: 16)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AdminField(ctrl: _titleCtrl, label: 'Page Title'),
              AdminField(
                  ctrl: _subtitleCtrl,
                  label: 'Subtitle / Tagline',
                  helperText: 'Optional — used on About Us only'),
              AdminField(
                  ctrl: _lastUpdatedCtrl,
                  label: 'Last Updated Label',
                  hint: 'e.g. July 2026'),
              const SizedBox(height: 12),
              const Text('Sections',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              ..._sections.asMap().entries.map((e) => Container(
                    margin: const EdgeInsets.only(bottom: 12),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: _kSurface,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white12),
                    ),
                    child: Column(children: [
                      Row(children: [
                        Expanded(
                          child: Text('Section ${e.key + 1}',
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12)),
                        ),
                        IconButton(
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: _kRed, size: 18),
                          onPressed: _sections.length == 1
                              ? null
                              : () => setState(
                                  () => _sections.removeAt(e.key).dispose()),
                        ),
                      ]),
                      AdminField(
                          ctrl: e.value.headingCtrl,
                          label: 'Heading',
                          helperText: 'Leave blank for a plain paragraph'),
                      AdminField(
                          ctrl: e.value.bodyCtrl, label: 'Body', maxLines: 5),
                    ]),
                  )),
              TextButton.icon(
                onPressed: () =>
                    setState(() => _sections.add(_SectionEditRow())),
                icon: const Icon(Icons.add_rounded, color: _kTeal, size: 18),
                label:
                    const Text('Add section', style: TextStyle(color: _kTeal)),
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
                  label: Text(_saving ? 'Saving…' : 'Save Page'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kTeal,
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
