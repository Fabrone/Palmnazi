import 'package:flutter/material.dart';
import 'package:flutter_quill/flutter_quill.dart';
import 'package:flutter_quill_delta_from_html/flutter_quill_delta_from_html.dart';
import 'package:vsc_quill_delta_to_html/vsc_quill_delta_to_html.dart';
import 'package:palmnazi/admin/admin_api_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminBlogComposeScreen
//
// Full-screen rich-text editor for creating and editing blog posts.
//
// DEPENDENCIES — add to pubspec.yaml:
//   flutter_quill: ^11.5.0
//   flutter_quill_delta_from_html: ^1.0.5
//   vsc_quill_delta_to_html: ^0.6.2
//
// ── FIX v2.1 ─────────────────────────────────────────────────────────────────
//
// BUG 1 — MissingFlutterQuillLocalizationException (CRASH)
//   flutter_quill v11+ requires FlutterQuillLocalizations.delegate to be
//   present somewhere in the widget tree above every QuillSimpleToolbar /
//   QuillEditor.  If the host MaterialApp does not register it (the common
//   case), every toolbar button throws at build time.
//
//   PREFERRED global fix (add once to your MaterialApp in main.dart):
//
//     import 'package:flutter_quill/flutter_quill.dart';
//
//     MaterialApp(
//       localizationsDelegates: const [
//         FlutterQuillLocalizations.delegate,   // ← add this
//         GlobalMaterialLocalizations.delegate,
//         GlobalWidgetsLocalizations.delegate,
//         GlobalCupertinoLocalizations.delegate,
//       ],
//       ...
//     )
//
//   LOCAL fix applied here (belt-and-suspenders, works even when the global
//   fix is absent):
//     _ContentTab.build() now wraps its subtree in Localizations.override,
//     injecting FlutterQuillLocalizations.delegate into the local scope.
//     This is safe: Localizations.override merges with — not replaces — the
//     parent's localizations, so all existing Material/Cupertino text stays
//     correctly localised.
//
// BUG 2 — ScrollController memory leak
//   The previous code created ScrollController() inline inside
//   _ContentTab.build(), producing a new, never-disposed controller on every
//   rebuild.  The controller is now a late final field in
//   _AdminBlogComposeScreenState, passed down to _ContentTab, and disposed
//   alongside the other controllers.
//
// ─────────────────────────────────────────────────────────────────────────────

class AdminBlogComposeScreen extends StatefulWidget {
  final AdminApiService        apiService;
  final Map<String, dynamic>?  existingPost; // null → create mode

  const AdminBlogComposeScreen({
    super.key,
    required this.apiService,
    this.existingPost,
  });

  @override
  State<AdminBlogComposeScreen> createState() =>
      _AdminBlogComposeScreenState();
}

class _AdminBlogComposeScreenState extends State<AdminBlogComposeScreen>
    with SingleTickerProviderStateMixin {
  // ── Plain-text field controllers ───────────────────────────────────────────
  late final TextEditingController _titleCtrl;
  late final TextEditingController _excerptCtrl;
  late final TextEditingController _categoriesCtrl;
  late final TextEditingController _tagsCtrl;
  late final TextEditingController _featuredImageCtrl;
  late final TextEditingController _metaTitleCtrl;
  late final TextEditingController _metaDescCtrl;
  late final TextEditingController _cityIdCtrl;
  late final TextEditingController _scheduledCtrl;

  // ── flutter_quill controller (pure Dart, no WebView) ──────────────────────
  late QuillController  _quillCtrl;
  final FocusNode       _quillFocus = FocusNode();

  // FIX BUG 2: ScrollController promoted from an inline build() expression
  // to a properly lifecycle-managed field.
  late final ScrollController _quillScrollCtrl;

  late final TabController _tabCtrl;

  String _status = 'DRAFT';
  bool   _saving = false;
  final Map<String, String> _fieldErrors = {};

  static const _accent    = Color(0xFF14FFEC);
  static const _blogColor = Color(0xFFE91E8C);

  bool get _isEdit => widget.existingPost != null;

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    final p = widget.existingPost;

    final cats = (p?['categories'] as List?)?.join(', ') ?? '';
    final tags = (p?['tags']       as List?)?.join(', ') ?? '';

    _titleCtrl         = TextEditingController(text: p?['title']           ?? '');
    _excerptCtrl       = TextEditingController(text: p?['excerpt']         ?? '');
    _categoriesCtrl    = TextEditingController(text: cats);
    _tagsCtrl          = TextEditingController(text: tags);
    _featuredImageCtrl = TextEditingController(text: p?['featuredImage']   ?? '');
    _metaTitleCtrl     = TextEditingController(text: p?['metaTitle']       ?? '');
    _metaDescCtrl      = TextEditingController(text: p?['metaDescription'] ?? '');
    _cityIdCtrl        = TextEditingController(text: p?['city']?['id']     ?? '');
    _scheduledCtrl     = TextEditingController(text: p?['scheduledFor']    ?? '');
    _status            = (p?['status'] as String? ?? 'DRAFT').toUpperCase();

    // Build the Quill document from existing HTML (edit mode) or empty (create)
    _quillCtrl       = _buildQuillController(p?['content'] as String? ?? '');

    // FIX BUG 2: initialise here, dispose below.
    _quillScrollCtrl = ScrollController();

    _tabCtrl = TabController(length: 3, vsync: this);
  }

  /// Convert an HTML string to a QuillController with the appropriate Delta.
  /// Falls back to an empty document if the string is blank.
  QuillController _buildQuillController(String html) {
    if (html.trim().isEmpty) {
      return QuillController.basic();
    }
    try {
      final delta = HtmlToDelta().convert(html);
      return QuillController(
        document:  Document.fromDelta(delta),
        selection: const TextSelection.collapsed(offset: 0),
      );
    } catch (_) {
      return QuillController.basic();
    }
  }

  @override
  void dispose() {
    for (final c in [
      _titleCtrl, _excerptCtrl, _categoriesCtrl, _tagsCtrl,
      _featuredImageCtrl, _metaTitleCtrl, _metaDescCtrl,
      _cityIdCtrl, _scheduledCtrl,
    ]) {
      c.dispose();
    }
    _quillCtrl.dispose();
    _quillFocus.dispose();
    _quillScrollCtrl.dispose(); // FIX BUG 2
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Helpers ────────────────────────────────────────────────────────────────

  List<String> _splitComma(String raw) =>
      raw.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();

  /// Export the current Quill document to an HTML string.
  String _getHtml() {
    final delta = _quillCtrl.document.toDelta();
    final ops   = List<Map<String, dynamic>>.from(delta.toJson());
    return QuillDeltaToHtmlConverter(ops).convert();
  }

  /// Plain text from the Quill document for character-count validation.
  String _getPlainText() =>
      _quillCtrl.document.toPlainText().replaceAll(RegExp(r'\s+'), ' ').trim();

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save({required String status}) async {
    setState(() {
      _fieldErrors.clear();
      _saving = true;
    });

    final rawHtml   = _getHtml();
    final plainText = _getPlainText();

    // ── Client-side validation ─────────────────────────────────────────────
    if (_titleCtrl.text.trim().isEmpty) {
      _fieldErrors['title'] = 'Title is required';
    }
    if (plainText.length < 100) {
      _fieldErrors['content'] =
          'Content must be at least 100 characters (currently ${plainText.length})';
    }
    if (status == 'SCHEDULED' && _scheduledCtrl.text.trim().isEmpty) {
      _fieldErrors['scheduledFor'] = 'Scheduled date/time is required';
    }

    if (_fieldErrors.isNotEmpty) {
      setState(() => _saving = false);
      _jumpToFirstError();
      return;
    }

    final payload = <String, dynamic>{
      'title':   _titleCtrl.text.trim(),
      'content': rawHtml,
      'status':  status,
      if (_excerptCtrl.text.isNotEmpty)
        'excerpt': _excerptCtrl.text.trim(),
      if (_categoriesCtrl.text.isNotEmpty)
        'categories': _splitComma(_categoriesCtrl.text),
      if (_tagsCtrl.text.isNotEmpty)
        'tags': _splitComma(_tagsCtrl.text),
      if (_featuredImageCtrl.text.isNotEmpty)
        'featuredImage': _featuredImageCtrl.text.trim(),
      if (_metaTitleCtrl.text.isNotEmpty)
        'metaTitle': _metaTitleCtrl.text.trim(),
      if (_metaDescCtrl.text.isNotEmpty)
        'metaDescription': _metaDescCtrl.text.trim(),
      if (_cityIdCtrl.text.isNotEmpty)
        'cityId': _cityIdCtrl.text.trim(),
      if (status == 'SCHEDULED' && _scheduledCtrl.text.isNotEmpty)
        'scheduledFor': _scheduledCtrl.text.trim(),
    };

    try {
      if (_isEdit) {
        await widget.apiService
            .updateBlogPost(widget.existingPost!['slug'] as String, payload);
      } else {
        await widget.apiService.createBlogPost(payload);
      }

      if (!mounted) return;
      setState(() => _saving = false);

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(
            _isEdit ? 'Post updated successfully' : 'Post created successfully'),
        backgroundColor: const Color(0xFF0D7377),
        behavior: SnackBarBehavior.floating,
      ));

      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);

      if (e is AdminApiException) {
        const tab0Fields = ['title', 'content', 'excerpt', 'categories', 'tags'];
        const tab1Fields = ['metaTitle', 'metaDescription', 'featuredImage'];
        const tab2Fields = ['scheduledFor', 'cityId'];

        for (final field in [...tab0Fields, ...tab1Fields, ...tab2Fields]) {
          final err = e.fieldError(field);
          if (err != null) _fieldErrors[field] = err;
        }

        if (_fieldErrors.isNotEmpty) {
          setState(() {});
          _jumpToFirstError();
          return;
        }
        _showError(e.message);
      } else {
        _showError(e.toString());
      }
    }
  }

  void _jumpToFirstError() {
    const tab0Fields = ['title', 'content', 'excerpt', 'categories', 'tags'];
    const tab1Fields = ['metaTitle', 'metaDescription', 'featuredImage'];
    if (_fieldErrors.keys.any((k) => tab0Fields.contains(k))) {
      _tabCtrl.animateTo(0);
    } else if (_fieldErrors.keys.any((k) => tab1Fields.contains(k))) {
      _tabCtrl.animateTo(1);
    } else {
      _tabCtrl.animateTo(2);
    }
  }

  void _showError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: Colors.redAccent,
      behavior: SnackBarBehavior.floating,
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              size: 18, color: Colors.white54),
          onPressed: () => Navigator.of(context).pop(false),
        ),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: _blogColor.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              _isEdit ? Icons.edit_rounded : Icons.edit_note_rounded,
              color: _blogColor,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Text(
            _isEdit ? 'Edit Post' : 'New Blog Post',
            style: const TextStyle(
                fontSize: 16, fontWeight: FontWeight.w600),
          ),
        ]),
        bottom: TabBar(
          controller: _tabCtrl,
          labelColor: _accent,
          unselectedLabelColor: Colors.white38,
          indicatorColor: _accent,
          indicatorSize: TabBarIndicatorSize.label,
          tabs: const [
            Tab(text: 'Content'),
            Tab(text: 'Meta & SEO'),
            Tab(text: 'Settings'),
          ],
        ),
        actions: _saving
            ? [
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 16),
                  child: SizedBox(
                    width: 20, height: 20,
                    child: CircularProgressIndicator(
                        strokeWidth: 2, color: _accent),
                  ),
                ),
              ]
            : [
                TextButton(
                  onPressed: () => _save(status: 'DRAFT'),
                  child: const Text('Save Draft',
                      style: TextStyle(color: Colors.white54, fontSize: 13)),
                ),
                const SizedBox(width: 4),
                Padding(
                  padding: const EdgeInsets.only(right: 12),
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF0D7377),
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                    ),
                    icon: const Icon(Icons.publish_rounded, size: 16),
                    label: const Text('Publish',
                        style: TextStyle(fontSize: 13)),
                    onPressed: () => _save(status: 'PUBLISHED'),
                  ),
                ),
              ],
      ),
      body: TabBarView(
        controller: _tabCtrl,
        children: [
          // FIX BUG 2: pass the managed _quillScrollCtrl instead of
          // creating a new ScrollController() on each build.
          _ContentTab(
            titleCtrl:        _titleCtrl,
            excerptCtrl:      _excerptCtrl,
            categoriesCtrl:   _categoriesCtrl,
            tagsCtrl:         _tagsCtrl,
            fieldErrors:      _fieldErrors,
            quillCtrl:        _quillCtrl,
            quillFocus:       _quillFocus,
            quillScrollCtrl:  _quillScrollCtrl,
          ),
          _MetaTab(
            metaTitleCtrl:     _metaTitleCtrl,
            metaDescCtrl:      _metaDescCtrl,
            featuredImageCtrl: _featuredImageCtrl,
            fieldErrors:       _fieldErrors,
          ),
          _SettingsTab(
            status:          _status,
            onStatusChanged: (s) => setState(() => _status = s),
            cityIdCtrl:      _cityIdCtrl,
            scheduledCtrl:   _scheduledCtrl,
            scheduledError:  _fieldErrors['scheduledFor'],
            onSchedule:      () => _save(status: 'SCHEDULED'),
            saving:          _saving,
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Shared plain-text form field
// ─────────────────────────────────────────────────────────────────────────────

class _Field extends StatelessWidget {
  final String                label;
  final TextEditingController ctrl;
  final String?               hint;
  final String?               helper;
  final bool                  required;
  final String?               error;
  final int                   maxLines;
  final IconData?             icon;
  final TextInputType?        keyboardType;

  const _Field({
    required this.label,
    required this.ctrl,
    this.hint,
    this.helper,
    this.required = false,
    this.error,
    this.maxLines = 1,
    this.icon,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          Row(children: [
            Text(label,
                style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 13,
                    fontWeight: FontWeight.w500)),
            if (required)
              const Text(' *',
                  style: TextStyle(
                      color: Color(0xFF14FFEC), fontSize: 13)),
          ]),
          const SizedBox(height: 8),
          TextFormField(
            controller:   ctrl,
            maxLines:     maxLines,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText:  hint,
              hintStyle: const TextStyle(
                  color: Colors.white24, fontSize: 13),
              helperText:  error == null ? helper : null,
              helperStyle: const TextStyle(
                  color: Colors.white38, fontSize: 11),
              errorText:   error,
              prefixIcon:  icon != null
                  ? Icon(icon, size: 16, color: Colors.white38)
                  : null,
              filled:    true,
              fillColor: const Color(0xFF0D1117),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.white12),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: error != null
                        ? Colors.redAccent.withValues(alpha: 0.5)
                        : Colors.white12),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                    color: error != null
                        ? Colors.redAccent
                        : const Color(0xFF14FFEC)),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(color: Colors.redAccent),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide:
                    const BorderSide(color: Colors.redAccent),
              ),
              contentPadding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 12),
            ),
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1 — Content  (flutter_quill rich-text editor)
// ─────────────────────────────────────────────────────────────────────────────

class _ContentTab extends StatelessWidget {
  final TextEditingController titleCtrl;
  final TextEditingController excerptCtrl;
  final TextEditingController categoriesCtrl;
  final TextEditingController tagsCtrl;
  final Map<String, String>   fieldErrors;
  final QuillController       quillCtrl;
  final FocusNode             quillFocus;
  // FIX BUG 2: receive the managed ScrollController instead of creating one.
  final ScrollController      quillScrollCtrl;

  const _ContentTab({
    required this.titleCtrl,
    required this.excerptCtrl,
    required this.categoriesCtrl,
    required this.tagsCtrl,
    required this.fieldErrors,
    required this.quillCtrl,
    required this.quillFocus,
    required this.quillScrollCtrl, // FIX BUG 2
  });

  static const _accent    = Color(0xFF14FFEC);
  static const _blogColor = Color(0xFFE91E8C);

  @override
  Widget build(BuildContext context) {
    // ─────────────────────────────────────────────────────────────────────────
    // FIX BUG 1 — MissingFlutterQuillLocalizationException
    //
    // flutter_quill v11+ resolves its localisation strings (button tooltips,
    // ARIA labels, placeholder text, etc.) via Flutter's standard Localizations
    // mechanism.  Every QuillSimpleToolbar and QuillEditor widget calls
    //
    //   FlutterQuillLocalizations.of(context)
    //
    // If the delegate is not present in the ancestor Localizations widget the
    // call throws UnimplementedError at build time, which is what caused the
    // cascade of exceptions in the logs.
    //
    // Localizations.override() merges the new delegate into — rather than
    // replacing — the parent's existing Localizations scope.  All existing
    // Material and Cupertino strings therefore continue to work normally; only
    // the Quill-specific strings are newly resolved here.
    //
    // This local fix is self-contained and does not require touching main.dart.
    // However, also adding FlutterQuillLocalizations.delegate to your
    // MaterialApp.localizationsDelegates (see the class-level comment at the
    // top of this file) is the recommended belt-and-suspenders approach.
    // ─────────────────────────────────────────────────────────────────────────
    return Localizations.override(
      context: context,
      delegates: const [
        FlutterQuillLocalizations.delegate,
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Quill toolbar ──────────────────────────────────────────────────
          Container(
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              border: Border(
                bottom: BorderSide(
                    color: Colors.white.withValues(alpha: 0.08)),
              ),
            ),
            child: QuillSimpleToolbar(
              controller: quillCtrl,
              config: QuillSimpleToolbarConfig(
                multiRowsDisplay:          false,
                toolbarIconAlignment:      WrapAlignment.start,
                showBoldButton:            true,
                showItalicButton:          true,
                showUnderLineButton:       true,
                showStrikeThrough:         true,
                showInlineCode:            true,
                showCodeBlock:             true,
                showQuote:                 true,
                showLink:                  true,
                showListNumbers:           true,
                showListBullets:           true,
                showListCheck:             true,
                showHeaderStyle:           true,
                showIndent:                true,
                showAlignmentButtons:      true,
                showColorButton:           true,
                showBackgroundColorButton: true,
                showUndo:                  true,
                showRedo:                  true,
                showClearFormat:           true,
                showSearchButton:          false,
                showFontFamily:            false,
                showFontSize:              false,
                decoration: const BoxDecoration(
                  color: Color(0xFF111827),
                ),
              ),
            ),
          ),

          // ── Scrollable fields ──────────────────────────────────────────────
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                // Title
                _Field(
                  label:    'Post Title',
                  ctrl:     titleCtrl,
                  required: true,
                  hint:     'e.g. 10 Best Hotels in Mombasa',
                  icon:     Icons.title_rounded,
                  error:    fieldErrors['title'],
                ),

                // Content label
                Row(children: [
                  const Text('Content',
                      style: TextStyle(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w500)),
                  const Text(' *',
                      style: TextStyle(
                          color: _accent, fontSize: 13)),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _blogColor.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                          color: _blogColor.withValues(alpha: 0.2)),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.auto_awesome_rounded,
                            size: 10, color: _blogColor),
                        SizedBox(width: 4),
                        Text('Rich Text',
                            style: TextStyle(
                                color: _blogColor,
                                fontSize: 10,
                                fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ]),
                const SizedBox(height: 8),

                // Content error banner
                if (fieldErrors['content'] != null)
                  Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.redAccent.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color:
                              Colors.redAccent.withValues(alpha: 0.4)),
                    ),
                    child: Row(children: [
                      const Icon(Icons.error_outline_rounded,
                          size: 14, color: Colors.redAccent),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(fieldErrors['content']!,
                            style: const TextStyle(
                                color: Colors.redAccent, fontSize: 12)),
                      ),
                    ]),
                  ),

                // ── flutter_quill editor ───────────────────────────────────
                Container(
                  constraints:
                      const BoxConstraints(minHeight: 320, maxHeight: 480),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0D1117),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: fieldErrors['content'] != null
                          ? Colors.redAccent.withValues(alpha: 0.5)
                          : Colors.white12,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: QuillEditor(
                    controller:       quillCtrl,
                    focusNode:        quillFocus,
                    // FIX BUG 2: use the lifecycle-managed controller.
                    scrollController: quillScrollCtrl,
                    config: QuillEditorConfig(
                      placeholder: 'Start writing your article here. Use '
                          'the toolbar above to format text, add headings, '
                          'bullet lists, links…',
                      padding:    const EdgeInsets.all(14),
                      autoFocus:  false,
                      expands:    false,
                      scrollable: true,
                      customStyles: DefaultStyles(
                        paragraph: DefaultTextBlockStyle(
                          const TextStyle(
                            color:    Colors.white70,
                            fontSize: 14,
                            height:   1.6,
                          ),
                          const HorizontalSpacing(0, 0),
                          const VerticalSpacing(2, 2),
                          const VerticalSpacing(0, 0),
                          null,
                        ),
                        h1: DefaultTextBlockStyle(
                          const TextStyle(
                            color:      Colors.white,
                            fontSize:   24,
                            fontWeight: FontWeight.w700,
                            height:     1.3,
                          ),
                          const HorizontalSpacing(0, 0),
                          const VerticalSpacing(8, 4),
                          const VerticalSpacing(0, 0),
                          null,
                        ),
                        h2: DefaultTextBlockStyle(
                          const TextStyle(
                            color:      Colors.white,
                            fontSize:   20,
                            fontWeight: FontWeight.w600,
                            height:     1.35,
                          ),
                          const HorizontalSpacing(0, 0),
                          const VerticalSpacing(6, 3),
                          const VerticalSpacing(0, 0),
                          null,
                        ),
                        h3: DefaultTextBlockStyle(
                          const TextStyle(
                            color:      Colors.white,
                            fontSize:   17,
                            fontWeight: FontWeight.w600,
                            height:     1.4,
                          ),
                          const HorizontalSpacing(0, 0),
                          const VerticalSpacing(4, 2),
                          const VerticalSpacing(0, 0),
                          null,
                        ),
                        bold: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700),
                        italic: const TextStyle(
                            color: Colors.white70,
                            fontStyle: FontStyle.italic),
                        underline: const TextStyle(
                            color: Colors.white70,
                            decoration: TextDecoration.underline),
                        strikeThrough: const TextStyle(
                            color: Colors.white38,
                            decoration: TextDecoration.lineThrough),
                        link: TextStyle(
                            color: const Color(0xFF14FFEC),
                            decoration: TextDecoration.underline,
                            decorationColor: const Color(0xFF14FFEC)
                                .withValues(alpha: 0.5)),
                        placeHolder: DefaultTextBlockStyle(
                          const TextStyle(
                              color: Colors.white24, fontSize: 14),
                          const HorizontalSpacing(0, 0),
                          const VerticalSpacing(2, 2),
                          const VerticalSpacing(0, 0),
                          null,
                        ),
                        code: DefaultTextBlockStyle(
                          const TextStyle(
                            color:      Color(0xFF14FFEC),
                            fontSize:   13,
                            fontFamily: 'monospace',
                          ),
                          const HorizontalSpacing(12, 12),
                          const VerticalSpacing(4, 4),
                          const VerticalSpacing(4, 4),
                          BoxDecoration(
                            color: Colors.black38,
                            borderRadius: BorderRadius.circular(6),
                          ),
                        ),
                        quote: DefaultTextBlockStyle(
                          const TextStyle(
                              color: Colors.white38,
                              fontStyle: FontStyle.italic,
                              fontSize: 14),
                          const HorizontalSpacing(16, 0),
                          const VerticalSpacing(4, 4),
                          const VerticalSpacing(0, 0),
                          BoxDecoration(
                            border: Border(
                              left: BorderSide(
                                color: const Color(0xFF14FFEC)
                                    .withValues(alpha: 0.4),
                                width: 3,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),

                const SizedBox(height: 4),
                const Text('Minimum 100 characters of actual content.',
                    style: TextStyle(
                        color: Colors.white24, fontSize: 11)),
                const SizedBox(height: 20),

                // Excerpt
                _Field(
                  label:    'Excerpt',
                  ctrl:     excerptCtrl,
                  maxLines: 3,
                  hint:     'Short teaser shown in post listings…',
                  helper:   'Optional — auto-generated if left empty.',
                  error:    fieldErrors['excerpt'],
                ),

                // Categories
                _Field(
                  label:  'Categories',
                  ctrl:   categoriesCtrl,
                  hint:   'accommodation, dining, wellness',
                  helper: 'Comma-separated category slugs.',
                  icon:   Icons.label_rounded,
                  error:  fieldErrors['categories'],
                ),

                // Tags
                _Field(
                  label:  'Tags',
                  ctrl:   tagsCtrl,
                  hint:   'luxury, budget-friendly, family',
                  helper: 'Comma-separated tags.',
                  icon:   Icons.tag_rounded,
                  error:  fieldErrors['tags'],
                ),
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2 — Meta & SEO
// ─────────────────────────────────────────────────────────────────────────────

class _MetaTab extends StatelessWidget {
  final TextEditingController metaTitleCtrl;
  final TextEditingController metaDescCtrl;
  final TextEditingController featuredImageCtrl;
  final Map<String, String>   fieldErrors;

  const _MetaTab({
    required this.metaTitleCtrl,
    required this.metaDescCtrl,
    required this.featuredImageCtrl,
    required this.fieldErrors,
  });

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // ── Live SEO preview ───────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            margin: const EdgeInsets.only(bottom: 24),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              const Row(children: [
                Icon(Icons.search_rounded,
                    color: Color(0xFF14FFEC), size: 15),
                SizedBox(width: 8),
                Text('SEO Preview',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 12),
              const Text('resortcities.com › blog',
                  style: TextStyle(
                      color: Colors.greenAccent, fontSize: 11)),
              const SizedBox(height: 4),
              ValueListenableBuilder(
                valueListenable: metaTitleCtrl,
                builder: (_, __, ___) => Text(
                  metaTitleCtrl.text.isEmpty
                      ? 'Page title…'
                      : metaTitleCtrl.text,
                  style: const TextStyle(
                      color: Color(0xFF4A90E2),
                      fontSize: 15,
                      fontWeight: FontWeight.w500),
                ),
              ),
              const SizedBox(height: 4),
              ValueListenableBuilder(
                valueListenable: metaDescCtrl,
                builder: (_, __, ___) => Text(
                  metaDescCtrl.text.isEmpty
                      ? 'Meta description will appear here…'
                      : metaDescCtrl.text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white38, fontSize: 12),
                ),
              ),
            ]),
          ),

          _Field(
            label:  'Meta Title',
            ctrl:   metaTitleCtrl,
            hint:   'e.g. 10 Best Hotels in Mombasa — 2026 Guide',
            helper: 'Recommended: 50–60 characters.',
            icon:   Icons.text_fields_rounded,
            error:  fieldErrors['metaTitle'],
          ),
          _Field(
            label:    'Meta Description',
            ctrl:     metaDescCtrl,
            maxLines: 3,
            hint:     'Compelling description for search engines…',
            helper:   'Recommended: 150–160 characters.',
            error:    fieldErrors['metaDescription'],
          ),
          _Field(
            label:        'Featured Image URL',
            ctrl:         featuredImageCtrl,
            hint:         'https://cdn.resortcities.com/images/…',
            helper:       'Full URL to the post cover image.',
            icon:         Icons.image_rounded,
            keyboardType: TextInputType.url,
            error:        fieldErrors['featuredImage'],
          ),

          // ── Live image preview ─────────────────────────────────────────
          ValueListenableBuilder(
            valueListenable: featuredImageCtrl,
            builder: (_, __, ___) {
              final url = featuredImageCtrl.text.trim();
              if (url.isEmpty || !url.startsWith('http')) {
                return const SizedBox.shrink();
              }
              return ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: Image.network(
                  url,
                  height: 180,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Container(
                    height: 56,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: const Color(0xFF111827),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Text(
                        'Could not load image preview',
                        style: TextStyle(
                            color: Colors.white38, fontSize: 12)),
                  ),
                ),
              );
            },
          ),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 3 — Settings
// ─────────────────────────────────────────────────────────────────────────────

class _SettingsTab extends StatelessWidget {
  final String                status;
  final ValueChanged<String>  onStatusChanged;
  final TextEditingController cityIdCtrl;
  final TextEditingController scheduledCtrl;
  final String?               scheduledError;
  final VoidCallback          onSchedule;
  final bool                  saving;

  const _SettingsTab({
    required this.status,
    required this.onStatusChanged,
    required this.cityIdCtrl,
    required this.scheduledCtrl,
    required this.scheduledError,
    required this.onSchedule,
    required this.saving,
  });

  Widget _statusOption(
      String value, IconData icon, Color color,
      ValueChanged<String> onChange) {
    final selected = status == value;
    return GestureDetector(
      onTap: () => onChange(value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: selected
              ? color.withValues(alpha: 0.15)
              : const Color(0xFF111827),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected
                ? color.withValues(alpha: 0.5)
                : Colors.white12,
            width: selected ? 1.5 : 1,
          ),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 14, color: selected ? color : Colors.white38),
          const SizedBox(width: 8),
          Text(value,
              style: TextStyle(
                color: selected ? color : Colors.white38,
                fontSize: 13,
                fontWeight:
                    selected ? FontWeight.w600 : FontWeight.normal,
              )),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
          // ── Status picker ────────────────────────────────────────────
          const Text('Post Status',
              style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: [
            _statusOption('DRAFT', Icons.drafts_rounded,
                Colors.white38, onStatusChanged),
            _statusOption('PUBLISHED', Icons.public_rounded,
                Colors.greenAccent, onStatusChanged),
            _statusOption('SCHEDULED', Icons.schedule_rounded,
                Colors.blueAccent, onStatusChanged),
          ]),
          const SizedBox(height: 24),

          // ── Scheduled fields ─────────────────────────────────────────
          if (status == 'SCHEDULED') ...[
            _Field(
              label:  'Publish Date & Time (ISO 8601)',
              ctrl:   scheduledCtrl,
              hint:   '2026-06-01T06:00:00Z',
              helper: 'Format: YYYY-MM-DDTHH:MM:SSZ',
              icon:   Icons.calendar_today_rounded,
              error:  scheduledError,
            ),
            const SizedBox(height: 4),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    Colors.blueAccent.withValues(alpha: 0.15),
                foregroundColor: Colors.blueAccent,
                elevation: 0,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(
                      color: Colors.blueAccent.withValues(alpha: 0.4)),
                ),
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
              ),
              icon: saving
                  ? const SizedBox(
                      width: 14, height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.blueAccent))
                  : const Icon(Icons.schedule_rounded, size: 16),
              label: const Text('Save as Scheduled',
                  style: TextStyle(fontSize: 13)),
              onPressed: saving ? null : onSchedule,
            ),
            const SizedBox(height: 24),
          ],

          // ── City association ─────────────────────────────────────────
          _Field(
            label:  'City ID (optional)',
            ctrl:   cityIdCtrl,
            hint:   'city_nairobi',
            helper: 'Associate this post with a specific resort city.',
            icon:   Icons.location_city_rounded,
          ),
          const SizedBox(height: 8),

          // ── Info card ────────────────────────────────────────────────
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF14FFEC).withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: const Color(0xFF14FFEC)
                      .withValues(alpha: 0.15)),
            ),
            child: const Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
              Row(children: [
                Icon(Icons.info_outline_rounded,
                    color: Color(0xFF14FFEC), size: 14),
                SizedBox(width: 8),
                Text('Publishing Notes',
                    style: TextStyle(
                        color: Color(0xFF14FFEC),
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ]),
              SizedBox(height: 10),
              Text(
                '• DRAFT — only visible in admin.\n'
                '• PUBLISHED — live immediately on the user app.\n'
                '• SCHEDULED — goes live at the specified date & time.',
                style: TextStyle(
                    color: Colors.white38, fontSize: 12, height: 1.6),
              ),
            ]),
          ),
        ]),
      );
}