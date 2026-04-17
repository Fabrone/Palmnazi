import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/material.dart';

import 'package:palmnazi/admin/admin_api_service.dart';
import 'package:palmnazi/admin/admin_shared_widgets.dart';
import 'package:palmnazi/models/city_model.dart';
import 'package:palmnazi/models/category_model.dart';
import 'package:palmnazi/models/place_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AdminPlaceWizardScreen
//
// Full-screen 11-step wizard for creating or editing a Place.
//
// Step 1:  Create draft          → POST /api/places
// Step 2:  Basic info            → PATCH /api/places/:id
// Step 3:  Location              → PATCH /api/places/:id/location
// Step 4:  Contact               → PATCH /api/places/:id/contact
// Step 5:  Attributes            → PATCH /api/places/:id/attributes
// Step 6:  Nested data           → POST /api/places/:id/rooms (accommodation)
//                                  POST /api/places/:id/menu-sections + menu-items (dining)
//                                  POST /api/places/:id/shows + performances (entertainment)
//                                  POST /api/places/:id/exhibitions + artifacts (cultural)
// Step 7:  Media                 → PATCH /api/places/:id/media
// Step 8:  Booking & pricing     → PATCH /api/places/:id/booking
// Step 9:  Link categories       → PUT /api/places/:id/categories
// Step 10: Validate              → GET /api/places/:id/submit
// Step 11: Submit                → POST /api/places/:id/submit
// ─────────────────────────────────────────────────────────────────────────────

class AdminPlaceWizardScreen extends StatefulWidget {
  final AdminApiService apiService;
  final List<CityModel> cities;
  final List<CategoryModel> categories;
  final PlaceModel? existingPlace;

  const AdminPlaceWizardScreen({
    super.key,
    required this.apiService,
    required this.cities,
    required this.categories,
    this.existingPlace,
  });

  @override
  State<AdminPlaceWizardScreen> createState() => _AdminPlaceWizardScreenState();
}

class _AdminPlaceWizardScreenState extends State<AdminPlaceWizardScreen> {
  int _step = 0;
  bool _saving = false;
  String? _stepError;

  PlaceModel? _place;

  // ── Step 1 — Draft
  final _nameCtrl = TextEditingController();
  String? _selectedCityId;
  String? _primaryCategorySlug;

  // ── Step 2 — Basic info
  final _shortDescCtrl = TextEditingController();
  final _descCtrl = TextEditingController();
  final _areaCtrl = TextEditingController();

  // ── Step 3 — Location
  final _addressCtrl = TextEditingController();
  final _latCtrl = TextEditingController();
  final _lngCtrl = TextEditingController();

  // ── Step 4 — Contact
  final _phoneCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();

  // ── Step 5 — Attributes (category-aware)
  final _checkInCtrl = TextEditingController();
  final _checkOutCtrl = TextEditingController();
  final _starRatingCtrl = TextEditingController();
  final _amenitiesCtrl = TextEditingController();
  final _cuisineCtrl = TextEditingController();
  final _seatingCapCtrl = TextEditingController();
  final _openingHoursCtrl = TextEditingController();

  // ── Step 6 — Nested data (built as lists, submitted in one POST)
  final List<Map<String, dynamic>> _rooms = [];
  final List<Map<String, dynamic>> _menuSections = [];
  final List<Map<String, dynamic>> _menuItems = [];
  final List<Map<String, dynamic>> _shows = [];

  // ── Step 7 — Media
  final _coverImageCtrl = TextEditingController();
  final List<TextEditingController> _imageUrlCtrls = [TextEditingController()];

  // Step 7 — upload state (cover)
  Uint8List? _coverImageBytes;
  bool _uploadingCover = false;
  double _coverUploadProgress = 0.0;

  // Step 7 — upload state (gallery — parallel to _imageUrlCtrls)
  final List<Uint8List?> _galleryBytes = [null];
  final List<bool> _galleryUploading = [false];
  final List<double> _galleryProgress = [0.0];

  // Pre-captured FirebaseStorage instance.
  //
  // WHY: On Flutter Web, DDC (Dart Dev Compiler) compiles every `async`
  // function body — including synchronous lines before the first `await` —
  // into an `_asyncStartSync` JS trampoline. Any access to
  // `FirebaseStorage.instance` inside an async function therefore runs inside
  // the JS async machinery, where firebase_core_web's `app()` method cannot
  // resolve the Dart-side Firebase registry, producing:
  //   "type 'FirebaseException' is not a subtype of type 'JavaScriptObject'"
  //
  // `initState()` is a plain synchronous Dart lifecycle call — never wrapped
  // in any JS async trampoline — so capturing the instance here is the only
  // location guaranteed to work on Flutter Web. The same pattern is used by
  // the city-cover upload in admin_resort_cities_screen.dart.
  FirebaseStorage? _storage;

  // ── Step 8 — Booking
  bool _isBookable = false;
  final _minPriceCtrl = TextEditingController();
  final _maxPriceCtrl = TextEditingController();
  String _priceUnit = 'night';
  String _currency = 'KES';
  String _cancellationPolicy = 'flexible';

  // ── Step 9 — Categories (multi-select)
  final Set<String> _selectedCategoryIds = {};

  // ── Step 10 — Validation result
  PlaceValidationResult? _validationResult;

  // ── Step-completion tracking ─────────────────────────────────────────────
  //
  // Tracks which steps (0-indexed) have been explicitly saved to the backend
  // during this session, OR inferred as complete from the existing place data
  // when editing.  Used by _StepProgressBar and _IncompleteStepsStrip to show
  // the user which sections still need attention.
  final Set<int> _completedSteps = {};

  // True while an automatic background validation is in progress (triggered
  // when the user jumps directly to step 9 via the progress bar).  Kept
  // separate from _saving so the main Save & Continue button stays active.
  bool _validating = false;

  @override
  void initState() {
    super.initState();
    if (widget.existingPlace != null) {
      _preloadFromExisting(widget.existingPlace!);
    }

    // Capture FirebaseStorage.instance synchronously here — NOT inside any
    // async function — so it resolves within the plain Dart execution context.
    // See the _storage field declaration above for the full explanation.
    try {
      _storage = FirebaseStorage.instance;
    } catch (storageErr, storageSt) {
      debugPrint('Failed to pre-cache FirebaseStorage: $storageErr\n$storageSt');
    }
  }

  void _preloadFromExisting(PlaceModel p) {
    _place = p;
    _step = 1; // Skip to step 2 for editing
    _nameCtrl.text = p.name;
    _selectedCityId = p.cityId;
    // ── Restore primary category slug ────────────────────────────────────────
    //
    // BUG FIX: Do NOT use categoryLinks.first.categorySlug here.
    //
    // categoryLinks is populated by Step 9 and may contain subcategory slugs
    // (e.g. "luxury-resorts") or be empty entirely if the list API returned a
    // thin model.  Either case makes _isAccommodationType / _isDiningType return
    // false, so _saveStep5 silently skips the PATCH — attributes are never
    // persisted — while still marking step 4 as complete.
    //
    // The backend stores the value from the Step 1 `primaryCategory` field in
    // the `taxonomy` array.  That is always the root-category slug (e.g.
    // "accommodation", "dining") and is the canonical source.
    //
    // Resolution order:
    //   1. taxonomy.first  — set by the backend from Step 1's primaryCategory
    //   2. Root-level category link (parentName == null) — fallback
    //   3. First categoryLink slug — last resort
    if (p.taxonomy.isNotEmpty) {
      _primaryCategorySlug = p.taxonomy.first;
      debugPrint('[Wizard/preload] _primaryCategorySlug from taxonomy: $_primaryCategorySlug');
    } else {
      final rootLink = p.categoryLinks
          .where((l) => l.parentName == null)
          .cast<PlaceCategoryLink?>()
          .firstOrNull;
      _primaryCategorySlug = rootLink?.categorySlug
          ?? (p.categoryLinks.isNotEmpty ? p.categoryLinks.first.categorySlug : null);
      debugPrint('[Wizard/preload] _primaryCategorySlug from categoryLinks: $_primaryCategorySlug '
          '(taxonomy was empty — check that backend populates taxonomy on draft creation)');
    }
    _shortDescCtrl.text = p.shortDescription ?? '';
    _descCtrl.text = p.description ?? '';
    _areaCtrl.text = p.area ?? '';
    _addressCtrl.text = p.address ?? '';
    _latCtrl.text = p.latitude?.toString() ?? '';
    _lngCtrl.text = p.longitude?.toString() ?? '';
    _phoneCtrl.text = p.contact?.phone ?? '';
    _emailCtrl.text = p.contact?.email ?? '';
    _websiteCtrl.text = p.contact?.website ?? '';
    _coverImageCtrl.text = p.coverImage ?? '';
    _isBookable = p.isBookable;
    _minPriceCtrl.text = p.pricing?.min?.toString() ?? '';
    _maxPriceCtrl.text = p.pricing?.max?.toString() ?? '';
    _priceUnit = p.pricing?.unit ?? 'night';
    _currency = p.pricing?.currency ?? 'KES';
    _cancellationPolicy =
        p.bookingSettings?.cancellationPolicy ?? 'flexible';
    for (final link in p.categoryLinks) {
      _selectedCategoryIds.add(link.categoryId);
    }

    // ── Restore attributes into their step-5 controllers ─────────────────
    //
    // The attributes JSONB blob is saved to the backend in Step 5 but was
    // never loaded back into the text controllers on edit, making the section
    // appear empty even after an initial save.  We read the exact same keys
    // that _saveStep5 writes so round-tripping is lossless.
    final attrs = p.attributes;
    if (attrs.isNotEmpty) {
      debugPrint('[Wizard/preload] Restoring ${attrs.length} attribute(s): ${attrs.keys.toList()}');
      _checkInCtrl.text  = (attrs['checkInTime']  as String?) ?? '';
      _checkOutCtrl.text = (attrs['checkOutTime'] as String?) ?? '';
      final star = attrs['starRating'];
      if (star != null) _starRatingCtrl.text = star.toString();

      final amenities = attrs['generalAmenities'];
      if (amenities is List && amenities.isNotEmpty) {
        _amenitiesCtrl.text = amenities.join(', ');
      }
      final cuisine = attrs['cuisine'];
      if (cuisine is List && cuisine.isNotEmpty) {
        _cuisineCtrl.text = cuisine.join(', ');
      }
      final seating = attrs['seatingCapacity'];
      if (seating != null) _seatingCapCtrl.text = seating.toString();
      _openingHoursCtrl.text = (attrs['openingHoursNote'] as String?) ?? '';
    }

    // Infer which steps are already complete from the existing place data
    _inferCompletionFromExisting(p);
  }

  // ── Step-completion inference ────────────────────────────────────────────
  //
  // Determines which wizard steps already have data saved in the backend so
  // the progress bar and incomplete-steps strip reflect reality immediately
  // when the user opens an existing place for editing.
  void _inferCompletionFromExisting(PlaceModel p) {
    // Step 0 — Draft: always complete if the place exists
    _completedSteps.add(0);

    // Step 1 — Basic Info
    if ((p.description?.isNotEmpty ?? false) ||
        (p.shortDescription?.isNotEmpty ?? false)) {
      _completedSteps.add(1);
    }

    // Step 2 — Location
    if ((p.address?.isNotEmpty ?? false) ||
        p.latitude != null ||
        p.longitude != null) {
      _completedSteps.add(2);
    }

    // Step 3 — Contact
    final c = p.contact;
    if (c != null &&
        ((c.phone?.isNotEmpty ?? false) ||
         (c.email?.isNotEmpty ?? false) ||
         (c.website?.isNotEmpty ?? false))) {
      _completedSteps.add(3);
    }

    // Step 4 — Attributes
    final attrs = p.attributes;
    if (attrs.isNotEmpty) {
      _completedSteps.add(4);
    }

    // Step 5 — Nested data: mark complete (optional/skippable for all types)
    _completedSteps.add(5);

    // Step 6 — Media
    if ((p.coverImage?.isNotEmpty ?? false) || p.images.isNotEmpty) {
      _completedSteps.add(6);
    }

    // Step 7 — Booking: always has a persisted value (isBookable defaults false)
    _completedSteps.add(7);

    // Step 8 — Categories
    if (p.categoryLinks.isNotEmpty) {
      _completedSteps.add(8);
    }

    // Step 9 — Validate / Step 10 — Submit
    if (p.status == 'ACTIVE') {
      _completedSteps.add(9);
      _completedSteps.add(10);
    }

    debugPrint('[Wizard/infer] Completed steps for existing place: $_completedSteps');
  }

  // ── Maps validation "missing" field names → wizard step indices ──────────
  //
  // Used to highlight which progress-bar segments are invalid after the
  // backend validation endpoint returns missing field names.
  static const Map<String, int> _fieldToStep = {
    'description':         1,
    'shortDescription':    1,
    'address':             2,
    'location':            2,
    'coordinates':         2,
    'latitude':            2,
    'longitude':           2,
    'contact':             3,
    'phone':               3,
    'email':               3,
    'attributes':          4,
    'cover':               6,
    'image':               6,
    'media':               6,
    'categor':             8,
  };

  /// Steps that the backend says are incomplete (from the latest validation).
  Set<int> get _invalidSteps {
    if (_validationResult == null || _validationResult!.isValid) return {};
    final result = <int>{};
    for (final field in _validationResult!.missing) {
      final lower = field.toLowerCase();
      _fieldToStep.forEach((key, step) {
        if (lower.contains(key)) result.add(step);
      });
    }
    return result;
  }

  /// Steps 1-8 that are not yet saved (shown in the incomplete strip).
  List<int> get _incompleteStepIndices {
    if (_place == null) return [];
    final invalid = _invalidSteps;
    final result = <int>[];
    for (var i = 1; i <= 8; i++) {
      if (!_completedSteps.contains(i) || invalid.contains(i)) {
        result.add(i);
      }
    }
    return result;
  }

  @override
  void dispose() {
    _nameCtrl.dispose(); _shortDescCtrl.dispose(); _descCtrl.dispose();
    _areaCtrl.dispose(); _addressCtrl.dispose(); _latCtrl.dispose();
    _lngCtrl.dispose(); _phoneCtrl.dispose(); _emailCtrl.dispose();
    _websiteCtrl.dispose(); _coverImageCtrl.dispose();
    _checkInCtrl.dispose(); _checkOutCtrl.dispose(); _starRatingCtrl.dispose();
    _amenitiesCtrl.dispose(); _cuisineCtrl.dispose(); _seatingCapCtrl.dispose();
    _openingHoursCtrl.dispose(); _minPriceCtrl.dispose(); _maxPriceCtrl.dispose();
    for (final c in _imageUrlCtrls) { c.dispose(); }
    // _galleryBytes / _galleryUploading / _galleryProgress are plain lists —
    // no extra dispose needed; they GC with the state.
    super.dispose();
  }

  // ── Category type helpers ────────────────────────────────────────────────

  bool get _isAccommodationType {
    final slug = _primaryCategorySlug ?? '';
    return slug.contains('accommodation') || slug.contains('hotel') ||
        slug.contains('resort') || slug.contains('lodge');
  }

  bool get _isDiningType {
    final slug = _primaryCategorySlug ?? '';
    return slug.contains('dining') || slug.contains('restaurant') ||
        slug.contains('food') || slug.contains('cafe');
  }

  bool get _isEntertainmentType {
    final slug = _primaryCategorySlug ?? '';
    return slug.contains('entertainment') || slug.contains('event') ||
        slug.contains('show') || slug.contains('cinema');
  }

  bool get _isCulturalType {
    final slug = _primaryCategorySlug ?? '';
    return slug.contains('museum') || slug.contains('cultural') ||
        slug.contains('heritage') || slug.contains('art');
  }

  String get _nestedDataLabel {
    if (_isAccommodationType) return 'Rooms';
    if (_isDiningType) return 'Menu';
    if (_isEntertainmentType) return 'Shows';
    if (_isCulturalType) return 'Exhibitions';
    return 'Details';
  }

  // ── Step 7: cover image upload ────────────────────────────────────────────

  Future<void> _pickAndUploadCoverImage() async {
    // Use the pre-cached FirebaseStorage instance captured in initState().
    //
    // CRITICAL — do NOT call FirebaseStorage.instance inside an async function
    // on Flutter Web. DDC compiles the entire async body (even lines before the
    // first `await`) into an `_asyncStartSync` JS trampoline where
    // firebase_core_web cannot resolve the Dart-side Firebase registry.
    // See the _storage field declaration for the full explanation.
    final storage = _storage;
    if (storage == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Firebase Storage is unavailable. Check Firebase initialisation.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;

    final ext = (file.extension ?? 'jpg').toLowerCase();
    final contentType = _mimeFor(ext);
    final nameSlug = _nameSlug();
    final ts = DateTime.now().millisecondsSinceEpoch;
    final storagePath = 'place-covers/$nameSlug-$ts.$ext';

    setState(() {
      _coverImageBytes = bytes;
      _uploadingCover = true;
      _coverUploadProgress = 0.0;
    });

    try {
      final ref = storage.ref(storagePath);
      final task = ref.putData(bytes, SettableMetadata(contentType: contentType));
      task.snapshotEvents.listen((s) {
        if (mounted && s.totalBytes > 0) {
          setState(() => _coverUploadProgress = s.bytesTransferred / s.totalBytes);
        }
      });
      await task;
      final url = await ref.getDownloadURL();
      if (mounted) {
        setState(() {
          _coverImageCtrl.text = url;
          _uploadingCover = false;
          _coverUploadProgress = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _uploadingCover = false;
          _coverImageBytes = null;
          _coverUploadProgress = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Cover upload failed: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Step 7: gallery image upload (per-slot) ───────────────────────────────

  Future<void> _pickAndUploadGalleryImage(int index) async {
    // Use the pre-cached FirebaseStorage instance captured in initState().
    // See _pickAndUploadCoverImage and the _storage field for the explanation.
    final storage = _storage;
    if (storage == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text(
              'Firebase Storage is unavailable. Check Firebase initialisation.'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }

    final result = await FilePicker.platform.pickFiles(
      type: FileType.image,
      withData: true,
    );
    if (result == null || result.files.isEmpty) return;

    final file = result.files.single;
    final bytes = file.bytes;
    if (bytes == null) return;

    final ext = (file.extension ?? 'jpg').toLowerCase();
    final contentType = _mimeFor(ext);
    final nameSlug = _nameSlug();
    final ts = DateTime.now().millisecondsSinceEpoch;
    // index+1 so filenames start at 1 to match the gallery ordering
    final storagePath = 'place-gallery/$nameSlug-${index + 1}-$ts.$ext';

    setState(() {
      _galleryBytes[index] = bytes;
      _galleryUploading[index] = true;
      _galleryProgress[index] = 0.0;
    });

    try {
      final ref = storage.ref(storagePath);
      final task = ref.putData(bytes, SettableMetadata(contentType: contentType));
      task.snapshotEvents.listen((s) {
        if (mounted && s.totalBytes > 0) {
          setState(() => _galleryProgress[index] = s.bytesTransferred / s.totalBytes);
        }
      });
      await task;
      final url = await ref.getDownloadURL();
      if (mounted) {
        setState(() {
          _imageUrlCtrls[index].text = url;
          _galleryUploading[index] = false;
          _galleryProgress[index] = 1.0;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _galleryUploading[index] = false;
          _galleryBytes[index] = null;
          _galleryProgress[index] = 0.0;
        });
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('Gallery image upload failed: $e'),
          backgroundColor: Colors.red.shade700,
          behavior: SnackBarBehavior.floating,
        ));
      }
    }
  }

  // ── Gallery slot management (keeps parallel lists in sync) ────────────────

  void _addGallerySlot() {
    setState(() {
      _imageUrlCtrls.add(TextEditingController());
      _galleryBytes.add(null);
      _galleryUploading.add(false);
      _galleryProgress.add(0.0);
    });
  }

  void _removeGallerySlot(int index) {
    _imageUrlCtrls[index].dispose();
    setState(() {
      _imageUrlCtrls.removeAt(index);
      _galleryBytes.removeAt(index);
      _galleryUploading.removeAt(index);
      _galleryProgress.removeAt(index);
    });
  }

  // ── Helpers ───────────────────────────────────────────────────────────────

  /// URL-safe slug derived from the place name — used in storage paths.
  String _nameSlug() {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return 'place';
    return name
        .toLowerCase()
        .replaceAll(RegExp(r'[^a-z0-9\s]'), '')
        .trim()
        .replaceAll(RegExp(r'\s+'), '-');
  }

  String _mimeFor(String ext) {
    switch (ext) {
      case 'png': return 'image/png';
      case 'webp': return 'image/webp';
      case 'gif': return 'image/gif';
      default: return 'image/jpeg';
    }
  }

  // ── Step execution ───────────────────────────────────────────────────────

  Future<void> _saveCurrentStep() async {
    if (_saving) return;
    setState(() { _saving = true; _stepError = null; });

    debugPrint('🔄 [Wizard] _saveCurrentStep  step=$_step (${_stepLabel(_step)})');

    try {
      switch (_step) {
        case 0:
          await _saveStep1();
          break;
        case 1:
          await _saveStep2();
          break;
        case 2:
          await _saveStep3();
          break;
        case 3:
          await _saveStep4();
          break;
        case 4:
          await _saveStep5();
          break;
        case 5:
          await _saveStep6();
          break;
        case 6:
          await _saveStep7();
          break;
        case 7:
          await _saveStep8();
          break;
        case 8:
          await _saveStep9();
          break;
        case 9:
          await _runValidation();
          break;
        case 10:
          // _submitPlace handles its own _saving reset on both success and
          // failure — success pops the page (mounted→false), failure clears
          // _saving in its own catch block before returning normally.
          await _submitPlace();
          return; // skip the step++ and the finally-reset below
      }

      debugPrint('✅ [Wizard] Step $_step saved — advancing to ${_step + 1}');
      if (mounted && _step < 10) setState(() { _completedSteps.add(_step); _step++; });

    } on AdminApiException catch (e) {
      debugPrint('❌ [Wizard] AdminApiException on step $_step: ${e.message}  (${e.statusCode})');
      if (mounted) setState(() { _stepError = e.message; _saving = false; });
      return; // prevent finally from double-clearing

    } catch (e, st) {
      debugPrint('💥 [Wizard] Unexpected error on step $_step: $e\n$st');
      if (mounted) setState(() { _stepError = e.toString(); _saving = false; });
      return; // prevent finally from double-clearing

    } finally {
      // ── CRITICAL FIX ─────────────────────────────────────────────────────
      // The old guard was `_step <= 9`, but by the time finally runs, `_step`
      // has already been incremented to 10 (after the step-9 validation
      // succeeds).  That made the condition false and _saving was NEVER reset,
      // locking the spinner forever after the validate step.
      //
      // We now reset unconditionally whenever the widget is still mounted.
      // For the submit step (10) we `return` before reaching finally, so this
      // branch only executes for steps 0–9 in the happy path.
      if (mounted) setState(() => _saving = false);
    }
  }

  /// Human-readable label for debug output — mirrors the progress-bar labels.
  static String _stepLabel(int step) {
    const labels = [
      'Draft', 'BasicInfo', 'Location', 'Contact', 'Attributes',
      'NestedData', 'Media', 'Booking', 'Categories', 'Validate', 'Submit'
    ];
    return step >= 0 && step < labels.length ? labels[step] : 'Unknown';
  }

  // ── Free navigation (no save) ───────────────────────────────────────────────
  //
  // Advances the wizard one step without calling any API. The user's form data
  // stays in the controllers and can be saved on any future step or on return.
  //
  // Blocked only on:
  //   • Step 0 with no draft — the place record must exist before steps 1-10
  //     have anything to PATCH against, so the draft step must be completed.
  //   • Step 10 (Submit) — there is no next step to navigate to.
  void _skipToNextStep() {
    if (_saving) return;
    if (_step == 0 && _place == null) return; // must create draft first
    if (_step >= 10) return;
    setState(() {
      _step++;
      _stepError = null;
    });
  }

  // Jump directly to any already-accessible step (used by progress-bar taps).
  // Steps beyond the furthest unlocked step are blocked to avoid confusion.
  void _jumpToStep(int target) {
    if (_saving) return;
    // Step 0 is always accessible.
    // Steps 1–10 require a place to exist (or the target is step 0 itself).
    if (target > 0 && _place == null) return;
    if (target < 0 || target > 10) return;
    setState(() {
      _step = target;
      _stepError = null;
    });
    // When the user jumps directly to the Validate step and we have no result
    // yet, auto-trigger a background validation so the step doesn't show a
    // blank/spinning state.
    if (target == 9 && _validationResult == null) {
      _autoValidate();
    }
  }

  // ── Auto-validation (background, separate from the main save flow) ────────
  //
  // Triggered when the user navigates to step 9 via the progress bar without
  // going through Save & Continue.  Uses a dedicated _validating flag so the
  // main save button is never blocked.
  Future<void> _autoValidate() async {
    if (_place == null || _validating || _saving) return;
    debugPrint('🔍 [Wizard/AutoValidate] Triggering background validation for placeId=${_place!.id}');
    setState(() { _validating = true; _stepError = null; });
    try {
      final result = await widget.apiService.validatePlace(_place!.id);
      debugPrint('   ↳ isValid=${result.isValid}  missing=${result.missing}');
      if (mounted) setState(() { _validationResult = result; _validating = false; });
    } catch (e, st) {
      debugPrint('❌ [Wizard/AutoValidate] Failed: $e\n$st');
      if (mounted) setState(() { _validating = false; });
    }
  }

  Future<void> _saveStep1() async {
    debugPrint('📝 [Wizard/Step1] Creating draft — name="${_nameCtrl.text.trim()}"  cityId=$_selectedCityId  primaryCategory=$_primaryCategorySlug');
    if (_nameCtrl.text.trim().isEmpty) throw AdminApiException(message: 'Name is required');
    if (_selectedCityId == null) throw AdminApiException(message: 'Select a resort city');
    if (_primaryCategorySlug == null) throw AdminApiException(message: 'Select a primary category');
    _place = await widget.apiService.createPlaceDraft(
      name: _nameCtrl.text.trim(),
      cityId: _selectedCityId!,
      primaryCategory: _primaryCategorySlug!,
    );
    debugPrint('✅ [Wizard/Step1] Draft created — placeId=${_place?.id}  status=${_place?.status}');
  }

  Future<void> _saveStep2() async {
    if (_place == null) { debugPrint('⚠️ [Wizard/Step2] Skipped — _place is null'); return; }
    debugPrint('📝 [Wizard/Step2] Saving basic info — placeId=${_place!.id}');
    if (_descCtrl.text.trim().isEmpty) throw AdminApiException(message: 'Description is required');
    _place = await widget.apiService.updatePlaceBasicInfo(_place!.id, {
      'shortDescription': _shortDescCtrl.text.trim(),
      'description': _descCtrl.text.trim(),
      if (_areaCtrl.text.trim().isNotEmpty) 'area': _areaCtrl.text.trim(),
    });
    debugPrint('✅ [Wizard/Step2] Basic info saved — placeId=${_place?.id}');
  }

  Future<void> _saveStep3() async {
    if (_place == null) { debugPrint('⚠️ [Wizard/Step3] Skipped — _place is null'); return; }
    final lat = double.tryParse(_latCtrl.text.trim());
    final lng = double.tryParse(_lngCtrl.text.trim());
    debugPrint('📝 [Wizard/Step3] Saving location — placeId=${_place!.id}  address="${_addressCtrl.text.trim()}"  lat=$lat  lng=$lng');
    _place = await widget.apiService.updatePlaceLocation(_place!.id, {
      if (_addressCtrl.text.trim().isNotEmpty) 'address': _addressCtrl.text.trim(),
      if (lat != null) 'latitude': lat,
      if (lng != null) 'longitude': lng,
      if (_areaCtrl.text.trim().isNotEmpty) 'area': _areaCtrl.text.trim(),
    });
    debugPrint('✅ [Wizard/Step3] Location saved — placeId=${_place?.id}');
  }

  Future<void> _saveStep4() async {
    if (_place == null) { debugPrint('⚠️ [Wizard/Step4] Skipped — _place is null'); return; }
    debugPrint('📝 [Wizard/Step4] Saving contact — placeId=${_place!.id}  phone="${_phoneCtrl.text.trim()}"  email="${_emailCtrl.text.trim()}"');
    _place = await widget.apiService.updatePlaceContact(_place!.id, {
      'contact': {
        if (_phoneCtrl.text.trim().isNotEmpty) 'phone': _phoneCtrl.text.trim(),
        if (_emailCtrl.text.trim().isNotEmpty) 'email': _emailCtrl.text.trim(),
        if (_websiteCtrl.text.trim().isNotEmpty) 'website': _websiteCtrl.text.trim(),
      },
    });
    debugPrint('✅ [Wizard/Step4] Contact saved — placeId=${_place?.id}');
  }

  Future<void> _saveStep5() async {
    if (_place == null) { debugPrint('⚠️ [Wizard/Step5] Skipped — _place is null'); return; }
    final attributes = <String, dynamic>{};
    if (_isAccommodationType) {
      if (_checkInCtrl.text.isNotEmpty) attributes['checkInTime'] = _checkInCtrl.text.trim();
      if (_checkOutCtrl.text.isNotEmpty) attributes['checkOutTime'] = _checkOutCtrl.text.trim();
      if (_starRatingCtrl.text.isNotEmpty) {
        attributes['starRating'] = int.tryParse(_starRatingCtrl.text) ?? 0;
      }
      final amenities = _amenitiesCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (amenities.isNotEmpty) attributes['generalAmenities'] = amenities;
    } else if (_isDiningType) {
      final cuisines = _cuisineCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (cuisines.isNotEmpty) attributes['cuisine'] = cuisines;
      if (_seatingCapCtrl.text.isNotEmpty) {
        attributes['seatingCapacity'] = int.tryParse(_seatingCapCtrl.text) ?? 0;
      }
      if (_openingHoursCtrl.text.isNotEmpty) attributes['openingHoursNote'] = _openingHoursCtrl.text.trim();
    } else {
      // ── Generic fallback ─────────────────────────────────────────────────
      //
      // BUG FIX: _buildStep5 renders _amenitiesCtrl in the generic fallback
      // ("Key Features / Amenities") but the original code only read
      // _amenitiesCtrl inside the _isAccommodationType branch.  Any text the
      // admin entered was discarded and no PATCH was sent, so the backend
      // always reported attributes={} for non-accommodation/dining places.
      //
      // Collect it here under "generalAmenities" — the same key used by the
      // accommodation branch — so the _preloadFromExisting round-trip is lossless.
      final amenities = _amenitiesCtrl.text.split(',').map((s) => s.trim()).where((s) => s.isNotEmpty).toList();
      if (amenities.isNotEmpty) attributes['generalAmenities'] = amenities;
      if (attributes.isEmpty) {
        debugPrint(
          '⚠️ [Wizard/Step5] No attributes collected for primaryCategorySlug="$_primaryCategorySlug". '
          'If this place should have attributes, verify that taxonomy is populated by the backend '
          'so _primaryCategorySlug is correctly restored on re-edit.',
        );
      }
    }
    if (attributes.isNotEmpty) {
      debugPrint('📝 [Wizard/Step5] Saving attributes — placeId=${_place!.id}  keys=${attributes.keys.toList()}');
      _place = await widget.apiService.updatePlaceAttributes(_place!.id, attributes);
      debugPrint('✅ [Wizard/Step5] Attributes saved — placeId=${_place?.id}');
    } else {
      debugPrint('⏭️ [Wizard/Step5] No attributes to save for category "$_primaryCategorySlug" — skipping PATCH');
    }
  }

  Future<void> _saveStep6() async {
    if (_place == null) { debugPrint('⚠️ [Wizard/Step6] Skipped — _place is null'); return; }
    debugPrint('📝 [Wizard/Step6] Saving nested data — placeId=${_place!.id}  type: accommodation=$_isAccommodationType  dining=$_isDiningType  entertainment=$_isEntertainmentType');
    if (_isAccommodationType && _rooms.isNotEmpty) {
      debugPrint('   ↳ POSTing ${_rooms.length} room(s)');
      await widget.apiService.createRooms(_place!.id, _rooms);
      debugPrint('✅ [Wizard/Step6] Rooms saved');
    } else if (_isDiningType) {
      if (_menuSections.isNotEmpty) {
        debugPrint('   ↳ POSTing ${_menuSections.length} menu section(s)');
        await widget.apiService.createMenuSections(_place!.id, _menuSections);
        debugPrint('✅ [Wizard/Step6] Menu sections saved');
      }
      if (_menuItems.isNotEmpty) {
        debugPrint('   ↳ POSTing ${_menuItems.length} menu item(s)');
        await widget.apiService.createMenuItems(_place!.id, _menuItems);
        debugPrint('✅ [Wizard/Step6] Menu items saved');
      }
      if (_menuSections.isEmpty && _menuItems.isEmpty) {
        debugPrint('⏭️ [Wizard/Step6] No menu data to save — skipping');
      }
    } else if (_isEntertainmentType && _shows.isNotEmpty) {
      debugPrint('   ↳ POSTing ${_shows.length} show(s)');
      await widget.apiService.createShows(_place!.id, _shows);
      debugPrint('✅ [Wizard/Step6] Shows saved');
    } else {
      debugPrint('⏭️ [Wizard/Step6] No nested data to save for this category — skipping');
    }
  }

  Future<void> _saveStep7() async {
    if (_place == null) { debugPrint('⚠️ [Wizard/Step7] Skipped — _place is null'); return; }
    final imageList = _imageUrlCtrls
        .asMap()
        .entries
        .where((e) => e.value.text.trim().isNotEmpty)
        .map((e) => PlaceImage(
              url: e.value.text.trim(),
              isPrimary: e.key == 0,
              order: e.key + 1,
            ).toJson())
        .toList();
    final cover = _coverImageCtrl.text.trim().isNotEmpty ? _coverImageCtrl.text.trim() : null;
    debugPrint('📝 [Wizard/Step7] Saving media — placeId=${_place!.id}  cover=${cover != null ? "set" : "null"}  galleryImages=${imageList.length}');
    _place = await widget.apiService.updatePlaceMedia(
      _place!.id,
      coverImage: cover,
      images: imageList,
    );
    debugPrint('✅ [Wizard/Step7] Media saved — placeId=${_place?.id}  coverImage=${_place?.coverImage != null ? "set" : "null"}');
  }

  Future<void> _saveStep8() async {
    if (_place == null) { debugPrint('⚠️ [Wizard/Step8] Skipped — _place is null'); return; }
    debugPrint('📝 [Wizard/Step8] Saving booking — placeId=${_place!.id}  isBookable=$_isBookable  currency=$_currency  unit=$_priceUnit');
    _place = await widget.apiService.updatePlaceBooking(_place!.id, {
      'isBookable': _isBookable,
      if (_isBookable) 'pricing': {
        if (_minPriceCtrl.text.isNotEmpty)
          'min': double.tryParse(_minPriceCtrl.text) ?? 0,
        if (_maxPriceCtrl.text.isNotEmpty)
          'max': double.tryParse(_maxPriceCtrl.text) ?? 0,
        'unit': _priceUnit,
        'currency': _currency,
      },
      if (_isBookable) 'bookingSettings': {
        'cancellationPolicy': _cancellationPolicy,
      },
    });
    debugPrint('✅ [Wizard/Step8] Booking saved — placeId=${_place?.id}  isBookable=${_place?.isBookable}');
  }

  Future<void> _saveStep9() async {
    if (_place == null) { debugPrint('⚠️ [Wizard/Step9] Skipped — _place is null'); return; }
    debugPrint('📝 [Wizard/Step9] Linking categories — placeId=${_place!.id}  selected=${_selectedCategoryIds.length}  ids=$_selectedCategoryIds');
    if (_selectedCategoryIds.isNotEmpty) {
      _place = await widget.apiService.linkPlaceCategories(
          _place!.id, _selectedCategoryIds.toList());
      debugPrint('✅ [Wizard/Step9] Categories linked — placeId=${_place?.id}  categoryLinks=${_place?.categoryLinks.length}');
    } else {
      debugPrint('⏭️ [Wizard/Step9] No categories selected — skipping PUT');
    }
  }

  Future<void> _runValidation() async {
    if (_place == null) { debugPrint('⚠️ [Wizard/Validate] Skipped — _place is null'); return; }
    debugPrint('🔍 [Wizard/Validate] Running GET validation — placeId=${_place!.id}');

    final result = await widget.apiService.validatePlace(_place!.id);

    debugPrint('   ↳ isValid=${result.isValid}  missing=${result.missing.length} field(s)');
    if (result.missing.isNotEmpty) {
      debugPrint('   ↳ Missing: ${result.missing.join(", ")}');
    }

    // FIX: do NOT set _step inside this method. _step is already 9 and
    // _saveCurrentStep will increment it after we return. Setting it to 9
    // here was a no-op at best; at worst it confused state traces.
    if (mounted) setState(() => _validationResult = result);

    if (!result.isValid) {
      debugPrint('❌ [Wizard/Validate] Place is NOT valid — blocking advance to Submit step');
      throw AdminApiException(message: 'Missing required fields — see below');
    }
    debugPrint('✅ [Wizard/Validate] Validation passed — proceeding to Submit step');
  }

  Future<void> _submitPlace() async {
    if (_place == null) { debugPrint('⚠️ [Wizard/Submit] Skipped — _place is null'); return; }

    // NOTE: _saveCurrentStep already set _saving=true before calling us.
    // We do NOT set it again here (was a redundant double-setState).
    debugPrint('🚀 [Wizard/Submit] Submitting place — placeId=${_place!.id}  name="${_place!.name}"');

    try {
      final submitted = await widget.apiService.submitPlace(_place!.id);
      debugPrint('✅ [Wizard/Submit] Place submitted successfully — placeId=${submitted.id}  status=${submitted.status}');
      if (mounted) {
        // Dismiss the spinner before we pop so the user sees the snackbar.
        setState(() => _saving = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('"${submitted.name}" is now ACTIVE'),
          backgroundColor: Colors.green.shade700,
          behavior: SnackBarBehavior.floating,
        ));
        Navigator.of(context).pop(true);
      }
    } on AdminApiException catch (e) {
      debugPrint('❌ [Wizard/Submit] AdminApiException — ${e.statusCode}: ${e.message}');
      if (mounted) setState(() { _stepError = e.message; _saving = false; });
    } catch (e, st) {
      debugPrint('💥 [Wizard/Submit] Unexpected error — $e\n$st');
      if (mounted) setState(() { _stepError = 'Submission failed: $e'; _saving = false; });
    }
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0E1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF111827),
        foregroundColor: Colors.white,
        elevation: 0,
        title: Text(
          widget.existingPlace != null
              ? 'Edit Place — ${widget.existingPlace!.name}'
              : 'Add New Place',
          style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
        ),
        actions: [
          if (_place != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Center(
                child: _PlaceStatusBadge(status: _place!.status),
              ),
            ),
        ],
      ),
      body: Column(
        children: [
          // Progress bar — tapping a segment jumps to that step (no save).
          _StepProgressBar(
            currentStep: _step,
            totalSteps: 11,
            completedSteps: _completedSteps,
            invalidSteps: _invalidSteps,
            onStepTap: _jumpToStep,
          ),

          // Incomplete steps strip — only visible when editing an existing
          // place and at least one data step (1-8) is still missing/invalid.
          if (_place != null && _incompleteStepIndices.isNotEmpty)
            _IncompleteStepsStrip(
              incompleteIndices: _incompleteStepIndices,
              invalidIndices: _invalidSteps,
              onJump: _jumpToStep,
            ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Step header
                  _StepHeader(step: _step, nestedLabel: _nestedDataLabel),
                  const SizedBox(height: 24),

                  // Error banner
                  if (_stepError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.red.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.redAccent.withValues(alpha: 0.4)),
                      ),
                      child: Row(children: [
                        const Icon(Icons.error_outline_rounded,
                            color: Colors.redAccent, size: 16),
                        const SizedBox(width: 10),
                        Expanded(
                            child: Text(_stepError!,
                                style: const TextStyle(color: Colors.redAccent, fontSize: 13))),
                      ]),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Step content
                  _buildStepContent(),
                ],
              ),
            ),
          ),

          // Bottom navigation
          _WizardBottomBar(
            step: _step,
            totalSteps: 11,
            saving: _saving,
            hasPlace: _place != null,
            onBack: _step > 0 ? () => setState(() { _step--; _stepError = null; }) : null,
            // Skip: free forward navigation without saving.
            // Unavailable on step 0 (draft not yet created) and the last step.
            onSkip: (_step == 0 && _place == null) || _step == 10
                ? null
                : _skipToNextStep,
            onContinue: _saveCurrentStep,
            onSaveExit: _place != null
                ? () => Navigator.of(context).pop(false)
                : null,
          ),
        ],
      ),
    );
  }

  Widget _buildStepContent() {
    switch (_step) {
      case 0: return _buildStep1();
      case 1: return _buildStep2();
      case 2: return _buildStep3();
      case 3: return _buildStep4();
      case 4: return _buildStep5();
      case 5: return _buildStep6();
      case 6: return _buildStep7();
      case 7: return _buildStep8();
      case 8: return _buildStep9();
      case 9: return _buildStep10();
      case 10: return _buildStep11();
      default: return const SizedBox.shrink();
    }
  }

  // ── Step 1 — Create draft ─────────────────────────────────────────────────
  Widget _buildStep1() {
    // Root categories only as primary category options
    final rootCats = widget.categories.where((c) => c.isRoot).toList();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AdminField(ctrl: _nameCtrl, label: 'Place Name', hint: 'e.g. Serena Beach Resort & Spa', required: true),

        const SizedBox(height: 4),
        const Text('Resort City',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 8),
        _AdminDropdown<String>(
          value: _selectedCityId,
          hint: 'Select the city this place is in',
          items: widget.cities.map((c) => DropdownMenuItem(value: c.id, child: Text(c.name))).toList(),
          onChanged: (v) => setState(() => _selectedCityId = v),
        ),
        const SizedBox(height: 16),

        const Text('Primary Category',
            style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        const Text('Used to determine what kind of nested data this place supports.',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 8),
        _AdminDropdown<String>(
          value: _primaryCategorySlug,
          hint: 'Select primary category',
          items: rootCats
              .map((c) => DropdownMenuItem(
                    value: c.slug,
                    child: Row(children: [
                      if (c.icon != null)
                        Text(c.icon!, style: const TextStyle(fontSize: 16)),
                      if (c.icon != null) const SizedBox(width: 8),
                      Text(c.name),
                    ]),
                  ))
              .toList(),
          onChanged: (v) => setState(() => _primaryCategorySlug = v),
        ),
      ],
    );
  }

  // ── Step 2 — Basic info ───────────────────────────────────────────────────
  Widget _buildStep2() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminField(ctrl: _shortDescCtrl, label: 'Short Description',
              hint: 'One sentence summary (max 300 chars)', maxLines: 2),
          AdminField(ctrl: _descCtrl, label: 'Full Description',
              hint: 'Detailed description of this place (min 100 chars)',
              maxLines: 5, required: true),
          AdminField(ctrl: _areaCtrl, label: 'Area / Neighbourhood',
              hint: 'e.g. Shanzu, Westlands'),
        ],
      );

  // ── Step 3 — Location ─────────────────────────────────────────────────────
  Widget _buildStep3() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminField(ctrl: _addressCtrl, label: 'Full Address',
              hint: 'e.g. Shanzu Beach Road, Mombasa', maxLines: 2),
          Row(children: [
            Expanded(
              child: AdminField(ctrl: _latCtrl, label: 'Latitude',
                  hint: 'e.g. -3.9875', keyboardType: TextInputType.number),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AdminField(ctrl: _lngCtrl, label: 'Longitude',
                  hint: 'e.g. 39.7392', keyboardType: TextInputType.number),
            ),
          ]),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.white12),
            ),
            child: const Row(children: [
              Icon(Icons.info_outline_rounded, color: Colors.white38, size: 14),
              SizedBox(width: 8),
              Expanded(child: Text(
                  'Use Google Maps to find accurate coordinates. Right-click any location → "What\'s here?" to see lat/lng.',
                  style: TextStyle(color: Colors.white38, fontSize: 11))),
            ]),
          ),
        ],
      );

  // ── Step 4 — Contact ──────────────────────────────────────────────────────
  Widget _buildStep4() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AdminField(ctrl: _phoneCtrl, label: 'Phone Number',
              hint: '+254722123456', keyboardType: TextInputType.phone),
          AdminField(ctrl: _emailCtrl, label: 'Email Address',
              hint: 'reservations@example.co.ke', keyboardType: TextInputType.emailAddress),
          AdminField(ctrl: _websiteCtrl, label: 'Website URL',
              hint: 'https://www.example.co.ke', keyboardType: TextInputType.url),
        ],
      );

  // ── Step 5 — Attributes ───────────────────────────────────────────────────
  Widget _buildStep5() {
    if (_isAccommodationType) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(child: AdminField(ctrl: _checkInCtrl, label: 'Check-in Time', hint: '14:00')),
          const SizedBox(width: 12),
          Expanded(child: AdminField(ctrl: _checkOutCtrl, label: 'Check-out Time', hint: '11:00')),
        ]),
        AdminField(ctrl: _starRatingCtrl, label: 'Star Rating',
            hint: '4', keyboardType: TextInputType.number,
            helperText: 'Enter 1–5'),
        AdminField(ctrl: _amenitiesCtrl, label: 'General Amenities',
            hint: 'Pool, Spa, Restaurant, Beach Access, WiFi',
            helperText: 'Comma-separated list', maxLines: 3),
      ]);
    }
    if (_isDiningType) {
      return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        AdminField(ctrl: _cuisineCtrl, label: 'Cuisine Types',
            hint: 'Seafood, Italian, Swahili',
            helperText: 'Comma-separated'),
        AdminField(ctrl: _seatingCapCtrl, label: 'Seating Capacity',
            hint: '120', keyboardType: TextInputType.number),
        AdminField(ctrl: _openingHoursCtrl, label: 'Opening Hours',
            hint: 'Mon–Fri: 11:00–23:00, Sat–Sun: 11:00–00:00', maxLines: 2),
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      AdminField(ctrl: _amenitiesCtrl, label: 'Key Features / Amenities',
          hint: 'Free Parking, WiFi, Accessible',
          helperText: 'Comma-separated list', maxLines: 3),
      const SizedBox(height: 8),
      Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: const Text(
            'Additional attributes specific to this category type can be added after creation.',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      ),
    ]);
  }

  // ── Step 6 — Nested data ──────────────────────────────────────────────────
  Widget _buildStep6() {
    if (_isAccommodationType) return _buildRoomsEditor();
    if (_isDiningType) return _buildMenuEditor();
    if (_isEntertainmentType) return _buildShowsEditor();
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: const Color(0xFF111827),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(children: [
          const Icon(Icons.layers_outlined, color: Colors.white24, size: 40),
          const SizedBox(height: 12),
          const Text('No nested data for this category type',
              style: TextStyle(color: Colors.white54, fontSize: 14)),
          const SizedBox(height: 8),
          const Text(
              'This step is optional for the selected category. Tap Continue.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
              textAlign: TextAlign.center),
        ]),
      ),
    ]);
  }

  Widget _buildRoomsEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Expanded(child: Text('Rooms',
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600))),
          TextButton.icon(
            onPressed: _showAddRoomDialog,
            icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF14FFEC)),
            label: const Text('Add Room', style: TextStyle(color: Color(0xFF14FFEC), fontSize: 13)),
          ),
        ]),
        const SizedBox(height: 8),
        if (_rooms.isEmpty)
          _EmptyNestedState(label: 'No rooms added yet', onAdd: _showAddRoomDialog)
        else
          ..._rooms.asMap().entries.map((e) => _NestedItemRow(
                title: e.value['name'] as String? ?? 'Room ${e.key + 1}',
                subtitle: '${e.value['roomType'] ?? ''} · KES ${e.value['basePrice'] ?? 0}',
                onDelete: () => setState(() => _rooms.removeAt(e.key)),
              )),
      ],
    );
  }

  void _showAddRoomDialog() {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    final guestsCtrl = TextEditingController(text: '2');
    String roomType = 'DOUBLE';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111827),
          title: const Text('Add Room', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            _SimpleField(ctrl: nameCtrl, label: 'Room Name', hint: 'Deluxe Ocean View Room'),
            const SizedBox(height: 12),
            const Text('Room Type', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 4),
            _AdminDropdown<String>(
              value: roomType,
              items: ['SINGLE', 'DOUBLE', 'TWIN', 'SUITE', 'FAMILY', 'PENTHOUSE', 'VILLA']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setSt(() => roomType = v ?? 'DOUBLE'),
            ),
            const SizedBox(height: 12),
            _SimpleField(ctrl: guestsCtrl, label: 'Max Guests', hint: '2',
                keyboardType: TextInputType.number),
            _SimpleField(ctrl: priceCtrl, label: 'Base Price (KES)', hint: '15000',
                keyboardType: TextInputType.number),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF2196F3)),
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty || priceCtrl.text.trim().isEmpty) return;
                setState(() {
                  _rooms.add({
                    'name': nameCtrl.text.trim(),
                    'roomType': roomType,
                    'maxGuests': int.tryParse(guestsCtrl.text) ?? 2,
                    'maxAdults': int.tryParse(guestsCtrl.text) ?? 2,
                    'maxChildren': 1,
                    'beds': [{'bedType': 'DOUBLE', 'quantity': 1}],
                    'amenities': ['WiFi', 'Air Conditioning'],
                    'basePrice': double.tryParse(priceCtrl.text) ?? 0,
                    'currency': 'KES',
                    'sortOrder': _rooms.length + 1,
                  });
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add Room'),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildMenuEditor() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          const Expanded(child: Text('Menu Items',
              style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600))),
          TextButton.icon(
            onPressed: _showAddMenuItemDialog,
            icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF14FFEC)),
            label: const Text('Add Item', style: TextStyle(color: Color(0xFF14FFEC), fontSize: 13)),
          ),
        ]),
        const SizedBox(height: 8),
        if (_menuItems.isEmpty)
          _EmptyNestedState(label: 'No menu items added yet', onAdd: _showAddMenuItemDialog)
        else
          ..._menuItems.asMap().entries.map((e) => _NestedItemRow(
                title: e.value['name'] as String? ?? 'Item ${e.key + 1}',
                subtitle: '${e.value['mealType'] ?? ''} · KES ${e.value['price'] ?? 0}',
                onDelete: () => setState(() => _menuItems.removeAt(e.key)),
              )),
      ],
    );
  }

  void _showAddMenuItemDialog() {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    String mealType = 'LUNCH';

    showDialog(
      context: context,
      builder: (_) => StatefulBuilder(builder: (ctx, setSt) {
        return AlertDialog(
          backgroundColor: const Color(0xFF111827),
          title: const Text('Add Menu Item', style: TextStyle(color: Colors.white)),
          content: SingleChildScrollView(child: Column(mainAxisSize: MainAxisSize.min, children: [
            _SimpleField(ctrl: nameCtrl, label: 'Item Name', hint: 'Grilled Lobster'),
            const SizedBox(height: 12),
            const Text('Meal Type', style: TextStyle(color: Colors.white54, fontSize: 12)),
            const SizedBox(height: 4),
            _AdminDropdown<String>(
              value: mealType,
              items: ['BREAKFAST', 'LUNCH', 'DINNER', 'BRUNCH', 'SNACK', 'DESSERT', 'BEVERAGE']
                  .map((t) => DropdownMenuItem(value: t, child: Text(t)))
                  .toList(),
              onChanged: (v) => setSt(() => mealType = v ?? 'LUNCH'),
            ),
            const SizedBox(height: 12),
            _SimpleField(ctrl: priceCtrl, label: 'Price (KES)', hint: '1500',
                keyboardType: TextInputType.number),
          ])),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFF50057)),
              onPressed: () {
                if (nameCtrl.text.trim().isEmpty || priceCtrl.text.trim().isEmpty) return;
                setState(() {
                  _menuItems.add({
                    'name': nameCtrl.text.trim(),
                    'mealType': mealType,
                    'price': double.tryParse(priceCtrl.text) ?? 0,
                    'currency': 'KES',
                    'isAvailable': true,
                    'sortOrder': _menuItems.length + 1,
                  });
                });
                Navigator.pop(ctx);
              },
              child: const Text('Add Item'),
            ),
          ],
        );
      }),
    );
  }

  Widget _buildShowsEditor() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('Shows / Events',
                style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w600))),
            TextButton.icon(
              onPressed: () => setState(() => _shows.add({
                    'name': 'New Show',
                    'category': 'CONCERT',
                    'durationMinutes': 90,
                    'ticketPricing': {'standard': 1000},
                  })),
              icon: const Icon(Icons.add_rounded, size: 16, color: Color(0xFF14FFEC)),
              label: const Text('Add Show', style: TextStyle(color: Color(0xFF14FFEC), fontSize: 13)),
            ),
          ]),
          if (_shows.isEmpty)
            _EmptyNestedState(label: 'No shows added', onAdd: null)
          else
            ..._shows.asMap().entries.map((e) => _NestedItemRow(
                  title: e.value['name'] as String? ?? 'Show ${e.key + 1}',
                  subtitle: '${e.value['category'] ?? ''} · ${e.value['durationMinutes']} min',
                  onDelete: () => setState(() => _shows.removeAt(e.key)),
                )),
        ],
      );

  // ── Step 7 — Media ────────────────────────────────────────────────────────
  Widget _buildStep7() {
    final anyUploading = _uploadingCover || _galleryUploading.any((v) => v);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Cover Image ──────────────────────────────────────────────────
        const Text('Cover Image',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        const Text(
            'Main image shown on place cards. Upload a photo or paste a URL.',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 10),

        // Preview + upload zone
        _ImageUploadTile(
          imageBytes: _coverImageBytes,
          existingUrl: _coverImageCtrl.text,
          uploading: _uploadingCover,
          uploadProgress: _coverUploadProgress,
          label: 'Cover Photo',
          onPickTap: (_saving || anyUploading) ? null : _pickAndUploadCoverImage,
        ),

        const SizedBox(height: 8),

        // URL field — autofilled after upload; editable as fallback
        _SimpleField(
          ctrl: _coverImageCtrl,
          label: 'Cover Image URL',
          hint: 'Auto-filled after upload — or paste a URL directly',
          keyboardType: TextInputType.url,
        ),

        const SizedBox(height: 20),

        // ── Gallery Images ───────────────────────────────────────────────
        const Text('Gallery Images',
            style: TextStyle(
                color: Colors.white70,
                fontSize: 13,
                fontWeight: FontWeight.w500)),
        const SizedBox(height: 4),
        const Text(
            'Upload additional photos — the first slot is the primary gallery image.',
            style: TextStyle(color: Colors.white38, fontSize: 11)),
        const SizedBox(height: 10),

        // Gallery slots
        ..._imageUrlCtrls.asMap().entries.map((entry) {
          final i = entry.key;
          return Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      i == 0 ? 'Image 1 — Primary' : 'Image ${i + 1}',
                      style: const TextStyle(
                          color: Colors.white54, fontSize: 12),
                    ),
                    const Spacer(),
                    // Remove button — only shown when more than one slot
                    if (_imageUrlCtrls.length > 1)
                      GestureDetector(
                        onTap: (_saving || _galleryUploading[i])
                            ? null
                            : () => _removeGallerySlot(i),
                        child: const Icon(Icons.remove_circle_rounded,
                            color: Colors.redAccent, size: 18),
                      ),
                  ],
                ),
                const SizedBox(height: 6),

                _ImageUploadTile(
                  imageBytes: _galleryBytes[i],
                  existingUrl: _imageUrlCtrls[i].text,
                  uploading: _galleryUploading[i],
                  uploadProgress: _galleryProgress[i],
                  label: i == 0 ? 'Primary Gallery Photo' : 'Gallery Photo ${i + 1}',
                  onPickTap: (_saving || anyUploading)
                      ? null
                      : () => _pickAndUploadGalleryImage(i),
                ),

                const SizedBox(height: 6),

                _SimpleField(
                  ctrl: _imageUrlCtrls[i],
                  label: 'Image URL',
                  hint: 'Auto-filled after upload — or paste a URL directly',
                  keyboardType: TextInputType.url,
                ),
              ],
            ),
          );
        }),

        // Add another slot
        TextButton.icon(
          onPressed: (_saving || anyUploading) ? null : _addGallerySlot,
          icon: Icon(
            Icons.add_photo_alternate_outlined,
            size: 16,
            color: (_saving || anyUploading)
                ? Colors.white24
                : const Color(0xFF14FFEC),
          ),
          label: Text(
            'Add another image',
            style: TextStyle(
              fontSize: 13,
              color: (_saving || anyUploading)
                  ? Colors.white24
                  : const Color(0xFF14FFEC),
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 8 — Booking ──────────────────────────────────────────────────────
  Widget _buildStep8() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            const Expanded(child: Text('Enable Booking',
                style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500))),
            Switch(
              value: _isBookable,
              activeThumbColor: Colors.greenAccent,
              onChanged: (v) => setState(() => _isBookable = v),
            ),
          ]),
          if (_isBookable) ...[
            const Divider(color: Colors.white12, height: 24),
            const Text('Pricing',
                style: TextStyle(color: Colors.white54, fontSize: 12, letterSpacing: 1)),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: AdminField(ctrl: _minPriceCtrl, label: 'Min Price',
                  hint: '5000', keyboardType: TextInputType.number)),
              const SizedBox(width: 12),
              Expanded(child: AdminField(ctrl: _maxPriceCtrl, label: 'Max Price',
                  hint: '50000', keyboardType: TextInputType.number)),
            ]),
            Row(children: [
              Expanded(child: _LabeledDropdown(
                label: 'Price Unit',
                value: _priceUnit,
                items: const ['night', 'hour', 'person', 'session'],
                onChanged: (v) => setState(() => _priceUnit = v ?? 'night'),
              )),
              const SizedBox(width: 12),
              Expanded(child: _LabeledDropdown(
                label: 'Currency',
                value: _currency,
                items: const ['KES', 'USD', 'EUR', 'GBP'],
                onChanged: (v) => setState(() => _currency = v ?? 'KES'),
              )),
            ]),
            const SizedBox(height: 8),
            _LabeledDropdown(
              label: 'Cancellation Policy',
              value: _cancellationPolicy,
              items: const ['flexible', 'moderate', 'strict'],
              onChanged: (v) => setState(() => _cancellationPolicy = v ?? 'flexible'),
            ),
          ],
        ],
      );

  // ── Step 9 — Categories multi-select ─────────────────────────────────────
  Widget _buildStep9() {
    final roots = widget.categories.where((c) => c.isRoot).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFF0D1117),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: const Color(0xFF2196F3).withValues(alpha: 0.3)),
          ),
          child: const Row(children: [
            Icon(Icons.info_outline_rounded, color: Color(0xFF2196F3), size: 14),
            SizedBox(width: 8),
            Expanded(child: Text(
                'Select every category this place offers. A hotel that offers accommodation AND dining AND wellness should have all three selected.',
                style: TextStyle(color: Colors.white54, fontSize: 12, height: 1.4))),
          ]),
        ),
        const SizedBox(height: 20),

        ...roots.map((root) {
          final childrenOfRoot = widget.categories
              .where((c) => c.parentId == root.id)
              .toList();
          final allIds = [root.id, ...childrenOfRoot.map((c) => c.id)];
          final anySelected = allIds.any((id) => _selectedCategoryIds.contains(id));

          return Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(
                  color: anySelected
                      ? const Color(0xFF2196F3).withValues(alpha: 0.4)
                      : Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Root category toggle
                Row(children: [
                  if (root.icon != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: Text(root.icon!, style: const TextStyle(fontSize: 16)),
                    ),
                  Expanded(
                    child: Text(root.name,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 14)),
                  ),
                  Checkbox(
                    value: _selectedCategoryIds.contains(root.id),
                    activeColor: const Color(0xFF2196F3),
                    checkColor: Colors.white,
                    onChanged: (v) => setState(() {
                      if (v == true) {
                        _selectedCategoryIds.add(root.id);
                      } else {
                        _selectedCategoryIds.remove(root.id);
                      }
                    }),
                  ),
                ]),
                // Child categories
                if (childrenOfRoot.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  ...childrenOfRoot.map((child) => Row(children: [
                        const SizedBox(width: 24),
                        const Icon(Icons.subdirectory_arrow_right_rounded,
                            color: Colors.white24, size: 14),
                        const SizedBox(width: 4),
                        Expanded(
                            child: Text(child.name,
                                style: const TextStyle(color: Colors.white54, fontSize: 13))),
                        Checkbox(
                          value: _selectedCategoryIds.contains(child.id),
                          activeColor: const Color(0xFF2196F3),
                          checkColor: Colors.white,
                          onChanged: (v) => setState(() {
                            if (v == true) {
                              _selectedCategoryIds.add(child.id);
                            } else {
                              _selectedCategoryIds.remove(child.id);
                            }
                          }),
                        ),
                      ])),
                ],
              ],
            ),
          );
        }),

        if (_selectedCategoryIds.isNotEmpty) ...[
          const SizedBox(height: 8),
          Text('${_selectedCategoryIds.length} categor${_selectedCategoryIds.length == 1 ? 'y' : 'ies'} selected',
              style: const TextStyle(color: Color(0xFF14FFEC), fontSize: 12)),
        ],
      ],
    );
  }

  // ── Step 10 — Validate ───────────────────────────────────────────────────
  //
  // Three states:
  //   1. _validating == true      → spinner with "Checking…" label
  //   2. _validationResult == null (and not validating) → prompt to run check
  //   3. result available         → full results with re-run + jump-to-step actions
  Widget _buildStep10() {
    // ── 1. Background validation in progress ─────────────────────────────
    if (_validating) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 40, height: 40,
              child: CircularProgressIndicator(
                  strokeWidth: 3, color: Color(0xFF14FFEC)),
            ),
            const SizedBox(height: 16),
            const Text('Checking required fields…',
                style: TextStyle(color: Colors.white54, fontSize: 13)),
          ],
        ),
      );
    }

    // ── 2. No result yet — show a "Run Validation" prompt ────────────────
    if (_validationResult == null) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(children: [
              const Icon(Icons.fact_check_rounded,
                  color: Color(0xFF14FFEC), size: 44),
              const SizedBox(height: 14),
              const Text('Ready to validate?',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 8),
              const Text(
                'This checks that all required fields are filled in before you submit the place.',
                style: TextStyle(
                    color: Colors.white54, fontSize: 13, height: 1.5),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: (_saving || _validating) ? null : _autoValidate,
                  icon: const Icon(Icons.play_arrow_rounded, size: 18),
                  label: const Text('Run Validation',
                      style: TextStyle(
                          fontWeight: FontWeight.w600, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF14FFEC),
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ]),
          ),
        ],
      );
    }

    // ── 3. Results available ─────────────────────────────────────────────
    final result = _validationResult!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Status banner ────────────────────────────────────────────────
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: result.isValid
                ? Colors.green.withValues(alpha: 0.1)
                : Colors.orange.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
                color: result.isValid
                    ? Colors.greenAccent.withValues(alpha: 0.35)
                    : Colors.orangeAccent.withValues(alpha: 0.35)),
          ),
          child: Row(children: [
            Icon(
              result.isValid
                  ? Icons.check_circle_rounded
                  : Icons.warning_amber_rounded,
              color: result.isValid ? Colors.greenAccent : Colors.orangeAccent,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                result.isValid
                    ? 'All required fields are complete. Ready to submit!'
                    : 'Some required fields are missing. Tap a field below to jump to that step.',
                style: TextStyle(
                    color: result.isValid
                        ? Colors.greenAccent
                        : Colors.orangeAccent,
                    fontSize: 13,
                    fontWeight: FontWeight.w500),
              ),
            ),
          ]),
        ),

        // ── Missing fields — each row is a tappable jump link ────────────
        if (result.missing.isNotEmpty) ...[
          const SizedBox(height: 16),
          const Text('MISSING FIELDS',
              style: TextStyle(
                  color: Colors.white38,
                  fontSize: 10,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          ...result.missing.map((m) {
            // Resolve a jump target for this field name (may be null)
            int? target;
            final lower = m.toLowerCase();
            _fieldToStep.forEach((key, step) {
              if (lower.contains(key)) target ??= step;
            });
            return GestureDetector(
              onTap: target != null ? () => _jumpToStep(target!) : null,
              child: Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.06),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                      color: Colors.orangeAccent.withValues(alpha: 0.2)),
                ),
                child: Row(children: [
                  const Icon(Icons.remove_circle_outline_rounded,
                      color: Colors.orangeAccent, size: 15),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(m,
                        style: const TextStyle(
                            color: Colors.white70, fontSize: 13)),
                  ),
                  if (target != null) ...[
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.orangeAccent.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Text(
                          'Step ${target! + 1}',
                          style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 10,
                              fontWeight: FontWeight.w600),
                        ),
                        const SizedBox(width: 3),
                        const Icon(Icons.arrow_forward_rounded,
                            size: 10, color: Colors.orangeAccent),
                      ]),
                    ),
                  ],
                ]),
              ),
            );
          }),
        ],

        // ── Re-run button ─────────────────────────────────────────────────
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: (_saving || _validating)
                ? null
                : () {
                    setState(() => _validationResult = null);
                    _autoValidate();
                  },
            icon: const Icon(Icons.refresh_rounded, size: 16),
            label: const Text('Re-run Validation',
                style: TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: const Color(0xFF14FFEC),
              side: BorderSide(
                color: (_saving || _validating)
                    ? Colors.white12
                    : const Color(0xFF14FFEC).withValues(alpha: 0.4),
              ),
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
            ),
          ),
        ),
      ],
    );
  }

  // ── Step 11 — Submit ─────────────────────────────────────────────────────
  Widget _buildStep11() => Column(
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: const Color(0xFF111827),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(children: [
              const Icon(Icons.rocket_launch_rounded,
                  color: Color(0xFF14FFEC), size: 48),
              const SizedBox(height: 16),
              Text(_place?.name ?? '',
                  style: const TextStyle(
                      color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  textAlign: TextAlign.center),
              const SizedBox(height: 8),
              const Text(
                  'Tapping "Submit & Activate" will change this place from PENDING to ACTIVE, making it visible in the user-facing app.',
                  style: TextStyle(color: Colors.white54, fontSize: 13, height: 1.5),
                  textAlign: TextAlign.center),
              if (_place != null) ...[
                const SizedBox(height: 20),
                Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  _SummaryPill(
                      icon: Icons.location_on_rounded,
                      label: _place!.cityName.isNotEmpty ? _place!.cityName : 'City set'),
                  const SizedBox(width: 8),
                  _SummaryPill(
                      icon: Icons.category_rounded,
                      label: '${_selectedCategoryIds.length} categories'),
                  const SizedBox(width: 8),
                  _SummaryPill(
                      icon: Icons.photo_rounded,
                      label: _place!.hasMedia ? 'Has media' : 'No media'),
                ]),
              ],
            ]),
          ),
        ],
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// Wizard sub-widgets
// ─────────────────────────────────────────────────────────────────────────────

class _StepProgressBar extends StatelessWidget {
  final int currentStep;
  final int totalSteps;
  final Set<int> completedSteps;
  final Set<int> invalidSteps;
  /// Called when the user taps a step segment. Null = tapping is disabled.
  final void Function(int step)? onStepTap;

  const _StepProgressBar({
    required this.currentStep,
    required this.totalSteps,
    required this.completedSteps,
    required this.invalidSteps,
    this.onStepTap,
  });

  @override
  Widget build(BuildContext context) {
    const labels = [
      'Draft', 'Info', 'Location', 'Contact', 'Attrs', 'Data',
      'Media', 'Booking', 'Categories', 'Validate', 'Submit'
    ];

    return Container(
      color: const Color(0xFF111827),
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
      child: Column(children: [
        // ── Segmented progress bar with dot indicators ────────────────────
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: List.generate(totalSteps, (i) {
            final isCurrent  = i == currentStep;
            final isSaved    = completedSteps.contains(i);
            final isInvalid  = invalidSteps.contains(i);
            // A step is accessible if it is saved, invalid (has been visited),
            // or is the current step.
            final isAccessible = isSaved || isInvalid || isCurrent;

            // Bar colour priority: current > invalid > saved > untouched
            final Color barColor;
            if (isCurrent) {
              barColor = const Color(0xFF14FFEC);
            } else if (isInvalid) {
              barColor = Colors.orangeAccent.withValues(alpha: 0.8);
            } else if (isSaved) {
              barColor = const Color(0xFF14FFEC).withValues(alpha: 0.45);
            } else {
              barColor = Colors.white12;
            }

            // Dot indicator below the bar
            Widget dot;
            if (isCurrent) {
              dot = const SizedBox(width: 4, height: 4);
            } else if (isInvalid) {
              dot = Container(
                width: 5, height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.orangeAccent.withValues(alpha: 0.9),
                ),
              );
            } else if (isSaved) {
              dot = Container(
                width: 5, height: 5,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF14FFEC).withValues(alpha: 0.6),
                ),
              );
            } else {
              dot = const SizedBox(width: 5, height: 5);
            }

            return Expanded(
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: GestureDetector(
                    onTap: (onStepTap != null && isAccessible)
                        ? () => onStepTap!(i)
                        : null,
                    behavior: HitTestBehavior.opaque,
                    child: Column(children: [
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 280),
                          height: isCurrent ? 4 : 3,
                          decoration: BoxDecoration(
                            color: barColor,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      // Dot sits directly below the bar
                      Center(child: dot),
                    ]),
                  ),
                ),
                if (i < totalSteps - 1) const SizedBox(width: 2),
              ]),
            );
          }),
        ),

        const SizedBox(height: 4),

        // ── Step label row ───────────────────────────────────────────────
        Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
          Text(
            'Step ${currentStep + 1} of $totalSteps',
            style: const TextStyle(color: Colors.white38, fontSize: 11),
          ),
          Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.touch_app_rounded,
                size: 10, color: Colors.white24),
            const SizedBox(width: 4),
            const Text('Tap a segment to jump',
                style: TextStyle(color: Colors.white24, fontSize: 10)),
            const SizedBox(width: 8),
            Text(
              labels[currentStep],
              style: const TextStyle(
                  color: Color(0xFF14FFEC),
                  fontSize: 11,
                  fontWeight: FontWeight.w600),
            ),
          ]),
        ]),

        // ── Legend ───────────────────────────────────────────────────────
        if (completedSteps.isNotEmpty || invalidSteps.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (completedSteps.isNotEmpty) ...[
                  Container(width: 6, height: 6, decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFF14FFEC).withValues(alpha: 0.6),
                  )),
                  const SizedBox(width: 4),
                  const Text('Saved', style: TextStyle(color: Colors.white24, fontSize: 9)),
                  const SizedBox(width: 12),
                ],
                if (invalidSteps.isNotEmpty) ...[
                  Container(width: 6, height: 6, decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.orangeAccent.withValues(alpha: 0.9),
                  )),
                  const SizedBox(width: 4),
                  const Text('Needs attention', style: TextStyle(color: Colors.white24, fontSize: 9)),
                ],
              ],
            ),
          ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// _IncompleteStepsStrip
//
// A compact, horizontally-scrollable strip of chips shown below the progress
// bar whenever the editing user has steps that are not yet saved or have been
// flagged as invalid by the backend validation.
//
// Each chip is tappable and jumps directly to the relevant step.
// ─────────────────────────────────────────────────────────────────────────────

class _IncompleteStepsStrip extends StatelessWidget {
  final List<int> incompleteIndices;
  final Set<int> invalidIndices;
  final void Function(int step) onJump;

  const _IncompleteStepsStrip({
    required this.incompleteIndices,
    required this.invalidIndices,
    required this.onJump,
  });

  static const _stepNames = [
    'Draft', 'Basic Info', 'Location', 'Contact', 'Attributes',
    'Nested Data', 'Media', 'Booking', 'Categories', 'Validate', 'Submit',
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF0D1117),
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 8),
      child: Row(
        children: [
          // Label
          const Icon(Icons.warning_amber_rounded,
              size: 13, color: Colors.orangeAccent),
          const SizedBox(width: 6),
          const Text(
            'Incomplete:',
            style: TextStyle(
                color: Colors.orangeAccent,
                fontSize: 11,
                fontWeight: FontWeight.w600),
          ),
          const SizedBox(width: 8),
          // Scrollable chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: incompleteIndices.map((stepIdx) {
                  final isInvalid = invalidIndices.contains(stepIdx);
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: GestureDetector(
                      onTap: () => onJump(stepIdx),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 4),
                        decoration: BoxDecoration(
                          color: isInvalid
                              ? Colors.orangeAccent.withValues(alpha: 0.12)
                              : Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: isInvalid
                                ? Colors.orangeAccent.withValues(alpha: 0.45)
                                : Colors.white24,
                          ),
                        ),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(
                            _stepNames[stepIdx],
                            style: TextStyle(
                              fontSize: 11,
                              color: isInvalid
                                  ? Colors.orangeAccent
                                  : Colors.white54,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          const SizedBox(width: 4),
                          Icon(
                            Icons.arrow_forward_ios_rounded,
                            size: 9,
                            color:
                                isInvalid ? Colors.orangeAccent : Colors.white38,
                          ),
                        ]),
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StepHeader extends StatelessWidget {
  final int step;
  final String nestedLabel;
  const _StepHeader({required this.step, required this.nestedLabel});

  static const _titles = [
    'Create Draft', 'Basic Information', 'Location', 'Contact Details',
    'Attributes', '', 'Media & Images', 'Booking & Pricing',
    'Link Categories', 'Validate', 'Submit & Activate'
  ];
  static const _subs = [
    'Set the name, city, and primary category',
    'Add a description and area information',
    'Set address and GPS coordinates',
    'Add phone, email, and website',
    'Add category-specific details',
    '',
    'Add cover photo and gallery images',
    'Configure pricing and booking options',
    'Select all applicable service categories',
    'Check required fields are complete',
    'Make this place live in the app'
  ];

  @override
  Widget build(BuildContext context) {
    final title = step == 5 ? nestedLabel : _titles[step];
    final sub = step == 5 ? 'Add ${nestedLabel.toLowerCase()} for this place (optional)' : _subs[step];
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text(title,
          style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold)),
      const SizedBox(height: 4),
      Text(sub, style: const TextStyle(color: Colors.white38, fontSize: 13)),
    ]);
  }
}

class _WizardBottomBar extends StatelessWidget {
  final int step;
  final int totalSteps;
  final bool saving;
  final bool hasPlace;
  final VoidCallback? onBack;
  /// Navigate forward without saving. Null when not applicable (step 0 without
  /// a draft, or the final Submit step).
  final VoidCallback? onSkip;
  final VoidCallback onContinue;
  final VoidCallback? onSaveExit;

  const _WizardBottomBar({
    required this.step,
    required this.totalSteps,
    required this.saving,
    required this.hasPlace,
    this.onBack,
    this.onSkip,
    required this.onContinue,
    this.onSaveExit,
  });

  @override
  Widget build(BuildContext context) {
    final isLast = step == totalSteps - 1;

    // ── Left-side actions: Back + Save & Exit ─────────────────────────────
    final leftActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (onBack != null)
          OutlinedButton.icon(
            onPressed: saving ? null : onBack,
            icon: const Icon(Icons.arrow_back_rounded, size: 15),
            label: const Text('Back'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.white54,
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(9)),
            ),
          ),
        if (onSaveExit != null) ...[
          const SizedBox(width: 6),
          TextButton(
            onPressed: saving ? null : onSaveExit,
            style: TextButton.styleFrom(
              foregroundColor: Colors.white38,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            ),
            child: const Text('Save & Exit', style: TextStyle(fontSize: 13)),
          ),
        ],
      ],
    );

    // ── Right-side actions: Next (skip) + Save & Continue ─────────────────
    final rightActions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // "Next →" — free forward navigation without saving.
        // Shown as a ghost outlined button so it reads as clearly secondary
        // to "Save & Continue". Tooltip clarifies it doesn't save.
        if (onSkip != null) ...[
          Tooltip(
            message: 'Move to next step without saving',
            child: OutlinedButton.icon(
              onPressed: saving ? null : onSkip,
              icon: const Icon(Icons.arrow_forward_rounded, size: 15),
              label: const Text('Next'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white38,
                side: BorderSide(
                  color: saving ? Colors.white12 : Colors.white24,
                ),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(9)),
              ),
            ),
          ),
          const SizedBox(width: 8),
        ],

        // "Save & Continue" — saves current step then advances.
        ElevatedButton.icon(
          onPressed: saving ? null : onContinue,
          icon: saving
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white))
              : Icon(
                  isLast
                      ? Icons.rocket_launch_rounded
                      : Icons.save_rounded,
                  size: 15),
          label: Text(
            saving
                ? 'Saving…'
                : isLast
                    ? 'Submit & Activate'
                    : 'Save & Continue',
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor:
                isLast ? Colors.greenAccent.shade700 : const Color(0xFF14FFEC),
            foregroundColor: Colors.black,
            padding:
                const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(9)),
          ),
        ),
      ],
    );

    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      decoration: BoxDecoration(
        color: const Color(0xFF111827),
        border: Border(
            top: BorderSide(color: Colors.white.withValues(alpha: 0.07))),
      ),
      // Use LayoutBuilder so the bar adapts gracefully on narrow screens —
      // if there isn't enough width for a single row, stack the two groups.
      child: LayoutBuilder(builder: (context, constraints) {
        // Estimate minimum width needed for both groups side-by-side.
        // Back(~80) + SaveExit(~85) + gap + Next(~80) + SaveContinue(~145) ≈ 420
        final canFitSingleRow = constraints.maxWidth >= 420;

        if (canFitSingleRow) {
          return Row(children: [
            leftActions,
            const Spacer(),
            rightActions,
          ]);
        }

        // Narrow: stack left actions on top, right actions below right-aligned.
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [leftActions]),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [rightActions],
            ),
          ],
        );
      }),
    );
  }
}

class _AdminDropdown<T> extends StatelessWidget {
  final T? value;
  final String? hint;
  final List<DropdownMenuItem<T>> items;
  final ValueChanged<T?> onChanged;

  const _AdminDropdown({this.value, this.hint, required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12),
        ),
        child: DropdownButton<T>(
          value: value,
          isExpanded: true,
          dropdownColor: const Color(0xFF1F2937),
          style: const TextStyle(color: Colors.white70, fontSize: 14),
          underline: const SizedBox.shrink(),
          hint: hint != null
              ? Text(hint!, style: const TextStyle(color: Colors.white24, fontSize: 13))
              : null,
          onChanged: onChanged,
          items: items,
        ),
      );
}

class _LabeledDropdown extends StatelessWidget {
  final String label;
  final String value;
  final List<String> items;
  final ValueChanged<String?> onChanged;
  const _LabeledDropdown({required this.label, required this.value,
      required this.items, required this.onChanged});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w500)),
          const SizedBox(height: 8),
          _AdminDropdown<String>(
            value: value,
            items: items.map((i) => DropdownMenuItem(value: i, child: Text(i))).toList(),
            onChanged: onChanged,
          ),
          const SizedBox(height: 16),
        ],
      );
}

class _SimpleField extends StatelessWidget {
  final TextEditingController ctrl;
  final String label;
  final String hint;
  final TextInputType? keyboardType;
  const _SimpleField({required this.ctrl, required this.label, required this.hint,
      this.keyboardType});

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
          const SizedBox(height: 6),
          TextFormField(
            controller: ctrl,
            keyboardType: keyboardType,
            style: const TextStyle(color: Colors.white, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
              filled: true,
              fillColor: const Color(0xFF0D1117),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12)),
              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12)),
              focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFF14FFEC))),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
        ],
      );
}

class _NestedItemRow extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback onDelete;
  const _NestedItemRow({required this.title, required this.subtitle, required this.onDelete});

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: const Color(0xFF0D1117),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(children: [
          const Icon(Icons.drag_handle_rounded, color: Colors.white24, size: 16),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
            Text(subtitle, style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ])),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Colors.redAccent, size: 16),
            onPressed: onDelete,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 28, minHeight: 28),
          ),
        ]),
      );
}

class _EmptyNestedState extends StatelessWidget {
  final String label;
  final VoidCallback? onAdd;
  const _EmptyNestedState({required this.label, this.onAdd});

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.02),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12, style: BorderStyle.solid),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text(label, style: const TextStyle(color: Colors.white38, fontSize: 13)),
          if (onAdd != null) ...[
            const SizedBox(height: 8),
            TextButton(
              onPressed: onAdd,
              child: const Text('+ Add one now', style: TextStyle(color: Color(0xFF14FFEC), fontSize: 13)),
            ),
          ],
        ]),
      );
}

class _PlaceStatusBadge extends StatelessWidget {
  final String status;
  const _PlaceStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    Color color;
    switch (status) {
      case 'ACTIVE': color = Colors.greenAccent; break;
      case 'SUSPENDED': color = Colors.orangeAccent; break;
      case 'ARCHIVED': color = Colors.grey; break;
      default: color = Colors.blueAccent; // PENDING
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(status,
          style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
    );
  }
}

class _SummaryPill extends StatelessWidget {
  final IconData icon;
  final String label;
  const _SummaryPill({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.white12),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12, color: const Color(0xFF14FFEC)),
          const SizedBox(width: 5),
          Text(label, style: const TextStyle(color: Colors.white54, fontSize: 11)),
        ]),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _ImageUploadTile
//
// Reusable upload tile used by both the cover image and each gallery slot in
// Step 7. Renders a 16:9 image preview (from bytes or URL), an upload progress
// bar while uploading, and a pick/change button when idle.
// ─────────────────────────────────────────────────────────────────────────────

class _ImageUploadTile extends StatelessWidget {
  final Uint8List? imageBytes;
  final String existingUrl;
  final bool uploading;
  final double uploadProgress;
  final String label;
  final VoidCallback? onPickTap;

  const _ImageUploadTile({
    required this.imageBytes,
    required this.existingUrl,
    required this.uploading,
    required this.uploadProgress,
    required this.label,
    required this.onPickTap,
  });

  bool get _hasPreview =>
      imageBytes != null || existingUrl.trim().isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D1117),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: uploading
              ? const Color(0xFF14FFEC).withValues(alpha: 0.4)
              : Colors.white12,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── 16:9 preview ──────────────────────────────────────────────
          if (_hasPreview)
            AspectRatio(
              aspectRatio: 16 / 9,
              child: _buildPreview(),
            ),

          // ── Upload progress ───────────────────────────────────────────
          if (uploading)
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: uploadProgress,
                      minHeight: 5,
                      backgroundColor: Colors.white12,
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF14FFEC)),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    'Uploading… ${(uploadProgress * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                ],
              ),
            ),

          // ── Pick / change button ──────────────────────────────────────
          if (!uploading)
            Padding(
              padding: const EdgeInsets.all(8),
              child: OutlinedButton.icon(
                onPressed: onPickTap,
                icon: Icon(
                  _hasPreview
                      ? Icons.change_circle_rounded
                      : Icons.upload_file_rounded,
                  size: 15,
                  color: onPickTap != null
                      ? const Color(0xFF14FFEC)
                      : Colors.white24,
                ),
                label: Text(
                  _hasPreview ? 'Change $label' : 'Upload $label',
                  style: TextStyle(
                    fontSize: 12,
                    color: onPickTap != null
                        ? const Color(0xFF14FFEC)
                        : Colors.white24,
                  ),
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 9),
                  side: BorderSide(
                    color: onPickTap != null
                        ? const Color(0xFF14FFEC).withValues(alpha: 0.5)
                        : Colors.white12,
                  ),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(7)),
                ),
              ),
            ),

          if (uploading) const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _buildPreview() {
    if (imageBytes != null) {
      return Image.memory(
        imageBytes!,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    if (existingUrl.trim().isNotEmpty) {
      return Image.network(
        existingUrl.trim(),
        fit: BoxFit.cover,
        loadingBuilder: (_, child, progress) => progress == null
            ? child
            : Container(
                color: Colors.white.withValues(alpha: 0.03),
                child: Center(
                  child: CircularProgressIndicator(
                    value: progress.expectedTotalBytes != null
                        ? progress.cumulativeBytesLoaded /
                            progress.expectedTotalBytes!
                        : null,
                    color: const Color(0xFF14FFEC),
                    strokeWidth: 2,
                  ),
                ),
              ),
        errorBuilder: (_, __, ___) => _placeholder(),
      );
    }
    return const SizedBox.shrink();
  }

  Widget _placeholder() => Container(
        color: Colors.white.withValues(alpha: 0.03),
        child: const Center(
          child: Icon(Icons.broken_image_rounded,
              color: Colors.white24, size: 36),
        ),
      );
}