import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:palmnazi/constants/tourism_labels.dart';
import 'package:palmnazi/screens/account_screen.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/screens/my_bookings_screen.dart';
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/services/auth_state_controller.dart';
import 'package:palmnazi/widgets/notification_bell.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PalmnaziNavBar
//
// The single top-navigation widget for the whole app, replacing the four
// near-duplicate `_buildTopNav()`/`_navBar()` implementations that used to
// live in landing_page.dart, resort_city_screen.dart, category_screen.dart,
// and place_details_screen.dart — one of which (resort_city_screen) hardcoded
// "Sign In / Get Started" with no auth check at all. This widget reads
// sign-in state from AuthStateScope, so every screen using it reacts to a
// login/logout immediately instead of only refreshing after a manual
// navigation round-trip.
//
// Two visual modes:
//   - hero (default): translucent bar that darkens as `heroOpacity` rises —
//     for screens with a full-bleed background image (landing, resort city,
//     category, place details).
//   - compact: opaque bar for plain content screens (my bookings, favorites,
//     account, about) — same nav links and auth slot, no hero blending.
//
// `showBack` renders a back button instead of the nav-link row (used by deep
// screens like place details / resort city, matching their prior behavior).
// `links` lets a screen supply its own set of nav actions (e.g. landing_page
// scrolls to a section instead of navigating away); omit for the default
// "Destinations / My Bookings / Blog" set with no-op destinations, which a
// screen can override individually via the named callbacks.
// ─────────────────────────────────────────────────────────────────────────────
class PalmnaziNavBar extends StatelessWidget implements PreferredSizeWidget {
  final bool compact;
  final bool showBack;
  final double heroOpacity;
  final Widget? trailing;
  final String? title;
  final VoidCallback? onDestinationsTap;
  final VoidCallback? onCategoriesTap;
  final VoidCallback? onBlogTap;

  const PalmnaziNavBar({
    super.key,
    this.compact = false,
    this.showBack = false,
    this.heroOpacity = 1.0,
    this.trailing,
    this.title,
    this.onDestinationsTap,
    this.onCategoriesTap,
    this.onBlogTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  static const _aquaBright = Color(0xFF00E5FF);
  static const _aqua = Color(0xFF00B8D4);
  static const _deepNavy = Color(0xFF071829);

  @override
  Widget build(BuildContext context) {
    final auth = AuthStateScope.of(context);
    final isMobile = MediaQuery.of(context).size.width < 720;

    final barColor = compact
        ? _deepNavy
        : Color.lerp(_deepNavy.withValues(alpha: 0.30),
            _deepNavy.withValues(alpha: 0.92), heroOpacity)!;

    final content = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          if (showBack) ...[
            _NavCircleButton(
              icon: Icons.arrow_back,
              onTap: () => Navigator.pop(context),
            ),
            const SizedBox(width: 10),
          ],
          _brand(),
          if (title != null) ...[
            const SizedBox(width: 14),
            Container(width: 1, height: 20, color: Colors.white24),
            const SizedBox(width: 14),
            Flexible(
              child: Text(
                title!,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          if (!showBack && !isMobile) ...[
            const SizedBox(width: 28),
            _navLink(
                context, context.tr('nav_destinations'), onDestinationsTap),
            _navLink(context, TourismLabels.categoryPlural, onCategoriesTap),
            _navLink(context, context.tr('nav_blog'), onBlogTap),
            _navLink(context, 'My Bookings', () => _goToBookings(context)),
          ],
          const Spacer(),
          if (trailing != null) ...[
            Flexible(child: trailing!),
            const SizedBox(width: 10),
          ],
          if (auth.isSignedIn) ...[
            const NotificationBell(),
            const SizedBox(width: 6),
          ],
          if (!showBack && isMobile)
            _NavCircleButton(
              icon: Icons.menu_rounded,
              onTap: () => _showMobileMenu(context),
              tooltip: 'Menu',
            ),
          const SizedBox(width: 6),
          _authSlot(context, auth, isMobile),
        ],
      ),
    );

    return SizedBox(
      height: preferredSize.height,
      child: Container(
        decoration: BoxDecoration(
          color: compact ? barColor : null,
          gradient: compact
              ? null
              : LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [barColor, Colors.transparent],
                ),
        ),
        child: compact
            ? SafeArea(bottom: false, child: content)
            : ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 10 * heroOpacity,
                    sigmaY: 10 * heroOpacity,
                  ),
                  child: SafeArea(bottom: false, child: content),
                ),
              ),
      ),
    );
  }

  Widget _brand() => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: const LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [_aquaBright, _aqua],
            ),
            boxShadow: [
              BoxShadow(color: _aqua.withValues(alpha: 0.50), blurRadius: 10),
            ],
          ),
          child: const Icon(Icons.landscape, color: Colors.white, size: 18),
        ),
        const SizedBox(width: 10),
        ShaderMask(
          shaderCallback: (b) =>
              const LinearGradient(colors: [_aquaBright, Colors.white])
                  .createShader(b),
          child: const Text(
            'PALMNAZI',
            style: TextStyle(
              color: Colors.white,
              fontSize: 17,
              fontWeight: FontWeight.bold,
              letterSpacing: 2,
            ),
          ),
        ),
      ]);

  Widget _navLink(BuildContext context, String label, VoidCallback? onTap) {
    if (onTap == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6),
      child: TextButton(
        onPressed: onTap,
        style: TextButton.styleFrom(
          foregroundColor: Colors.white70,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        ),
        child: Text(label,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ),
    );
  }

  void _showMobileMenu(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _deepNavy,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 8),
            if (onDestinationsTap != null)
              _mobileMenuTile(sheetContext, Icons.explore_rounded,
                  sheetContext.tr('nav_destinations'), onDestinationsTap!),
            if (onCategoriesTap != null)
              _mobileMenuTile(sheetContext, Icons.category_rounded,
                  TourismLabels.categoryPlural, onCategoriesTap!),
            if (onBlogTap != null)
              _mobileMenuTile(sheetContext, Icons.article_rounded,
                  sheetContext.tr('nav_blog'), onBlogTap!),
            _mobileMenuTile(sheetContext, Icons.calendar_month_rounded,
                'My Bookings', () => _goToBookings(sheetContext)),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  Widget _mobileMenuTile(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: Colors.white70),
      title: Text(label, style: const TextStyle(color: Colors.white)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
    );
  }

  void _goToBookings(BuildContext context) {
    if (!AuthStateScope.of(context).isSignedIn) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AuthScreen(isLogin: true)));
      return;
    }
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const MyBookingsScreen()));
  }

  Widget _authSlot(
      BuildContext context, AuthStateController auth, bool isMobile) {
    if (auth.isSignedIn) {
      return GestureDetector(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const AccountScreen())),
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient:
                const LinearGradient(colors: [_aquaBright, Color(0xFF0D7377)]),
            boxShadow: [
              BoxShadow(
                  color: _aquaBright.withValues(alpha: 0.28), blurRadius: 10),
            ],
          ),
          child:
              const Icon(Icons.person_rounded, color: Colors.white, size: 18),
        ),
      );
    }
    if (isMobile) {
      return IconButton(
        icon: const Icon(Icons.login_rounded, color: Colors.white70, size: 22),
        tooltip: context.tr('nav_sign_in'),
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AuthScreen(isLogin: true))),
      );
    }
    return Row(mainAxisSize: MainAxisSize.min, children: [
      TextButton(
        onPressed: () => Navigator.push(context,
            MaterialPageRoute(builder: (_) => const AuthScreen(isLogin: true))),
        style: TextButton.styleFrom(foregroundColor: Colors.white70),
        child: Text(context.tr('nav_sign_in'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w500)),
      ),
      const SizedBox(width: 4),
      ElevatedButton(
        onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(
                builder: (_) => const AuthScreen(isLogin: false))),
        style: ElevatedButton.styleFrom(
          backgroundColor: _aquaBright,
          foregroundColor: _deepNavy,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          elevation: 4,
          shadowColor: _aqua.withValues(alpha: 0.50),
        ),
        child: Text(context.tr('nav_get_started'),
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
      ),
    ]);
  }
}

class _NavCircleButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const _NavCircleButton(
      {required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    final btn = GestureDetector(
      onTap: onTap,
      child: Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.white.withValues(alpha: 0.15),
          border: Border.all(color: Colors.white.withValues(alpha: 0.30)),
        ),
        child: Icon(icon, color: Colors.white, size: 18),
      ),
    );
    return tooltip == null ? btn : Tooltip(message: tooltip!, child: btn);
  }
}
