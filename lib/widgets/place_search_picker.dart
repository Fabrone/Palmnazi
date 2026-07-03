import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:palmnazi/services/api_client.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PlaceSearchPicker
//
// A modal, live-search picker over the existing (frozen) /api/places search
// endpoint. Used wherever a real Place — not free text — needs to be linked:
// the admin-request submission form (account_screen.dart) and MainAdmin's
// "reassign place" action (admin_role_requests_screen.dart). Only ACTIVE
// places are offered, since a place-scoped Admin should manage a place that
// tourists can actually see.
// ─────────────────────────────────────────────────────────────────────────────

class PickedPlace {
  final String id;
  final String name;
  final String cityId;
  final String cityName;

  const PickedPlace({
    required this.id,
    required this.name,
    required this.cityId,
    required this.cityName,
  });
}

/// Opens the picker as a modal bottom sheet; returns the selection, or null
/// if the sheet was dismissed without picking anything.
Future<PickedPlace?> showPlaceSearchPicker(BuildContext context) {
  return showModalBottomSheet<PickedPlace>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _PlaceSearchSheet(),
  );
}

class _PlaceSearchSheet extends StatefulWidget {
  const _PlaceSearchSheet();

  @override
  State<_PlaceSearchSheet> createState() => _PlaceSearchSheetState();
}

class _PlaceSearchSheetState extends State<_PlaceSearchSheet> {
  final _ctrl = TextEditingController();
  Timer? _debounce;
  bool _loading = false;
  bool _searched = false;
  List<PickedPlace> _results = [];

  static const _timeout = Duration(seconds: 15);

  @override
  void dispose() {
    _debounce?.cancel();
    _ctrl.dispose();
    super.dispose();
  }

  void _onChanged(String raw) {
    _debounce?.cancel();
    final q = raw.trim();
    if (q.isEmpty) {
      setState(() {
        _results = [];
        _searched = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _search(q));
  }

  Future<void> _search(String q) async {
    setState(() => _loading = true);
    try {
      final uri = Uri.parse(ApiEndpoints.url(
          '/api/places?search=${Uri.encodeQueryComponent(q)}&status=ACTIVE&limit=20'));
      final resp = await http.get(uri).timeout(_timeout);
      if (resp.statusCode != 200) {
        if (mounted) {
          setState(() {
            _loading = false;
            _searched = true;
            _results = [];
          });
        }
        return;
      }
      final body = jsonDecode(resp.body) as Map<String, dynamic>;
      final data = body['data'];
      final List<dynamic> raw = data is List
          ? data
          : (data is Map
              ? (data['places'] as List<dynamic>? ?? const [])
              : const []);
      final places = raw
          .whereType<Map<String, dynamic>>()
          .map((p) {
            final city = p['city'] as Map<String, dynamic>?;
            return PickedPlace(
              id: p['id'] as String? ?? '',
              name: p['name'] as String? ?? '',
              cityId: city?['id'] as String? ?? (p['cityId'] as String? ?? ''),
              cityName: city?['name'] as String? ?? '',
            );
          })
          .where((p) => p.id.isNotEmpty)
          .toList();
      if (mounted) {
        setState(() {
          _results = places;
          _loading = false;
          _searched = true;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _searched = true;
          _results = [];
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding:
          EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Container(
        constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75),
        decoration: const BoxDecoration(
          color: Color(0xFF111827),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                    color: Colors.white24,
                    borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 16),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Select a Place',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
            ),
            const SizedBox(height: 4),
            const Align(
              alignment: Alignment.centerLeft,
              child: Text('Search for the place you manage or want to manage.',
                  style: TextStyle(color: Colors.white38, fontSize: 12)),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _ctrl,
              autofocus: true,
              onChanged: _onChanged,
              style: const TextStyle(color: Colors.white, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Search by place name…',
                hintStyle: const TextStyle(color: Colors.white38, fontSize: 13),
                prefixIcon: const Icon(Icons.search_rounded,
                    color: Color(0xFF14FFEC), size: 18),
                filled: true,
                fillColor: Colors.white.withValues(alpha: 0.06),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 14),
              ),
            ),
            const SizedBox(height: 12),
            Flexible(child: _buildResults()),
          ],
        ),
      ),
    );
  }

  Widget _buildResults() {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(
            child: CircularProgressIndicator(
                color: Color(0xFF14FFEC), strokeWidth: 2)),
      );
    }
    if (!_searched) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('Start typing to find a place.',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }
    if (_results.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 24),
        child: Text('No matching places found.',
            style: TextStyle(color: Colors.white38, fontSize: 12)),
      );
    }
    return ListView.separated(
      shrinkWrap: true,
      itemCount: _results.length,
      separatorBuilder: (_, __) =>
          Divider(color: Colors.white.withValues(alpha: 0.06), height: 1),
      itemBuilder: (_, i) {
        final p = _results[i];
        return ListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(p.name,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
          subtitle: p.cityName.isNotEmpty
              ? Text(p.cityName,
                  style: const TextStyle(color: Colors.white38, fontSize: 11))
              : null,
          trailing: const Icon(Icons.chevron_right_rounded,
              color: Colors.white38, size: 18),
          onTap: () => Navigator.of(context).pop(p),
        );
      },
    );
  }
}
