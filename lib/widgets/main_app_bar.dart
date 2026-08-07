import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:palmnazi/constants/tourism_labels.dart';
import 'package:palmnazi/screens/account_screen.dart';
import 'package:palmnazi/screens/auth_screen.dart';
import 'package:palmnazi/screens/my_bookings_screen.dart';
import 'package:palmnazi/services/app_strings.dart';
import 'package:palmnazi/services/auth_state_controller.dart';
import 'package:palmnazi/theme/rc_palette.dart';
import 'package:palmnazi/widgets/notification_bell.dart';

// ─────────────────────────────────────────────────────────────────────────────
// PalmnaziNavBar
//
// The single top-navigation widget for the whole app — a direct extraction of
// landing_page.dart's own nav bar (`_navBar`/`_brand`/`_signInButton`/
// `_showMobileMenu`/etc.), which is the app's one canonical nav design. Every
// other screen that used to hand-roll its own translucent bar (resort city,
// category, place details) or a plain Material AppBar (my bookings, favorites,
// about, booking, service detail) now renders this instead, so the whole app
// visibly matches landing page — not a fourth, divergent design.
//
// Reads sign-in state from AuthStateScope reactively, so every screen using
// this reacts to a login/logout immediately.
//
// Two visual modes:
//   - hero (default): translucent bar that darkens as `heroOpacity` rises —
//     for screens with a full-bleed background image.
//   - compact: opaque RC.navy bar for plain content screens — same auth
//     slot/bell, a back button instead of nav links, and an optional `title`.
//
// `showBack` renders a back button instead of the nav-link row (deep screens).
// The nav-link callbacks are all optional — a screen only wires the ones it
// has a destination for; "My Bookings" and the auth slot are always shown
// (their own sign-in gate is handled internally, matching landing page).
// `onLogoTap` is landing page's admin-quick-access shortcut on the brand mark
// — omitted (logo just isn't tappable) on every other screen.
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
  final VoidCallback? onSearchTap;
  final VoidCallback? onLogoTap;

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
    this.onSearchTap,
    this.onLogoTap,
  });

  @override
  Size get preferredSize => const Size.fromHeight(64);

  @override
  Widget build(BuildContext context) {
    final auth = AuthStateScope.of(context);
    final w = MediaQuery.of(context).size.width;
    final isMobile = w < 600;
    final opacity = compact ? 1.0 : heroOpacity;

    final content = Padding(
      padding:
          EdgeInsets.symmetric(horizontal: isMobile ? 16 : 28, vertical: 10),
      child: Row(
        children: [
          if (showBack) ...[
            _BackButton(onTap: () => Navigator.pop(context)),
            const SizedBox(width: 10),
          ],
          _brand(),
          if (title != null) ...[
            const SizedBox(width: 14),
            Container(
                width: 1,
                height: 20,
                color: RC.textMute.withValues(alpha: 0.3)),
            const SizedBox(width: 14),
            Flexible(
              child: Text(
                title!,
                style: TextStyle(
                  color: RC.textPri,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
          const Spacer(),
          if (trailing != null) ...[
            Flexible(child: trailing!),
            const SizedBox(width: 10),
          ],
          if (!showBack && !isMobile) ...[
            if (onDestinationsTap != null)
              _RcNavLink(
                  label: context.tr('nav_destinations'),
                  onTap: onDestinationsTap!),
            if (onCategoriesTap != null)
              _RcNavLink(
                  label: TourismLabels.categoryPlural, onTap: onCategoriesTap!),
            if (onBlogTap != null)
              _RcNavLink(label: context.tr('nav_blog'), onTap: onBlogTap!),
            _RcNavLink(
                label: 'My Bookings', onTap: () => _goToBookings(context)),
            const SizedBox(width: 8),
          ],
          if (auth.isSignedIn) ...[
            const NotificationBell(),
            SizedBox(width: isMobile ? 4 : 6),
          ],
          if (!showBack && isMobile) ...[
            _authSlotMobile(context, auth),
            const SizedBox(width: 4),
            _menuIconButton(context, auth),
          ] else if (!isMobile)
            _authSlot(context, auth),
        ],
      ),
    );

    return SizedBox(
      height: preferredSize.height,
      child: Container(
        decoration: BoxDecoration(
          color: compact ? RC.navy : null,
          border: compact
              ? null
              : Border(
                  bottom: BorderSide(
                      color: RC.gold.withValues(alpha: opacity * 0.18)),
                ),
        ),
        child: compact
            ? SafeArea(bottom: false, child: content)
            : ClipRect(
                child: BackdropFilter(
                  filter: ImageFilter.blur(
                    sigmaX: 10 * opacity,
                    sigmaY: 10 * opacity,
                  ),
                  child: Container(
                    decoration: BoxDecoration(
                      color: RC.navy.withValues(
                          alpha: opacity > 0.1 ? 0.92 * opacity : 0),
                    ),
                    child: SafeArea(bottom: false, child: content),
                  ),
                ),
              ),
      ),
    );
  }

  Widget _brand() {
    final logo = _logoImage();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      onLogoTap != null ? GestureDetector(onTap: onLogoTap, child: logo) : logo,
      const SizedBox(width: 10),
      ShaderMask(
        shaderCallback: (b) =>
            LinearGradient(colors: [RC.gold, RC.textPri]).createShader(b),
        child: const Text(
          'PALMNAZI RC',
          style: TextStyle(
            color: Colors.white,
            fontSize: 17,
            fontWeight: FontWeight.bold,
            letterSpacing: 2,
          ),
        ),
      ),
    ]);
  }

  Widget _logoImage() => ClipOval(
        child: Image.asset(
          'assets/images/logo.png',
          width: 34,
          height: 34,
          fit: BoxFit.cover,
          errorBuilder: (_, __, ___) => Container(
            width: 34,
            height: 34,
            decoration: const BoxDecoration(
                gradient: RC.tealGrad, shape: BoxShape.circle),
            child: const Icon(Icons.travel_explore_rounded,
                color: Colors.white, size: 18),
          ),
        ),
      );

  void _goToBookings(BuildContext context) {
    if (!AuthStateScope.of(context).isSignedIn) {
      Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AuthScreen(isLogin: true)));
      return;
    }
    Navigator.push(
        context, MaterialPageRoute(builder: (_) => const MyBookingsScreen()));
  }

  Widget _authSlot(BuildContext context, AuthStateController auth) {
    if (auth.isSignedIn) {
      return GestureDetector(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const AccountScreen())),
        child: _avatarCircle(),
      );
    }
    return TextButton(
      onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AuthScreen(isLogin: true))),
      style: TextButton.styleFrom(
        foregroundColor: RC.textSec,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      ),
      child:
          Text(context.tr('nav_sign_in'), style: const TextStyle(fontSize: 13)),
    );
  }

  Widget _authSlotMobile(BuildContext context, AuthStateController auth) {
    if (auth.isSignedIn) {
      return GestureDetector(
        onTap: () => Navigator.push(
            context, MaterialPageRoute(builder: (_) => const AccountScreen())),
        child: _avatarCircle(),
      );
    }
    return IconButton(
      icon: Icon(Icons.login_rounded, color: RC.textSec, size: 22),
      onPressed: () => Navigator.push(context,
          MaterialPageRoute(builder: (_) => const AuthScreen(isLogin: true))),
      splashRadius: 20,
      tooltip: context.tr('nav_sign_in'),
    );
  }

  Widget _avatarCircle() => Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
              colors: [Color(0xFF14FFEC), Color(0xFF0D7377)]),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF14FFEC).withValues(alpha: 0.28),
              blurRadius: 10,
            ),
          ],
        ),
        child: const Icon(Icons.person_rounded, color: Colors.white, size: 18),
      );

  Widget _menuIconButton(BuildContext context, AuthStateController auth) =>
      IconButton(
        icon: Icon(Icons.menu_rounded, color: RC.textSec, size: 22),
        onPressed: () => _showMobileMenu(context, auth),
        splashRadius: 20,
        tooltip: 'Menu',
      );

  void _showMobileMenu(BuildContext context, AuthStateController auth) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: RC.deepBlue,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                    color: RC.textMute, borderRadius: BorderRadius.circular(2)),
              ),
              const SizedBox(height: 16),
              if (onDestinationsTap != null)
                _mobileMenuItem(sheetContext, Icons.location_city_outlined,
                    sheetContext.tr('nav_destinations'), onDestinationsTap!),
              if (onCategoriesTap != null)
                _mobileMenuItem(sheetContext, Icons.category_outlined,
                    TourismLabels.categoryPlural, onCategoriesTap!),
              if (onBlogTap != null)
                _mobileMenuItem(sheetContext, Icons.article_outlined,
                    sheetContext.tr('nav_blog'), onBlogTap!),
              if (onSearchTap != null)
                _mobileMenuItem(sheetContext, Icons.search_rounded,
                    sheetContext.tr('nav_search'), onSearchTap!),
              _mobileMenuItem(sheetContext, Icons.calendar_month_rounded,
                  'My Bookings', () => _goToBookings(sheetContext)),
              const Divider(color: Color(0xFF1A3550), height: 24),
              if (auth.isSignedIn)
                _mobileMenuItem(
                    sheetContext,
                    Icons.person_rounded,
                    sheetContext.tr('nav_my_account'),
                    () => Navigator.push(
                        sheetContext,
                        MaterialPageRoute(
                            builder: (_) => const AccountScreen())))
              else
                _mobileMenuItem(
                    sheetContext,
                    Icons.login_rounded,
                    sheetContext.tr('nav_sign_in'),
                    () => Navigator.push(
                        sheetContext,
                        MaterialPageRoute(
                            builder: (_) => const AuthScreen(isLogin: true)))),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mobileMenuItem(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    return ListTile(
      leading: Icon(icon, color: RC.teal, size: 20),
      title: Text(label, style: TextStyle(color: RC.textSec, fontSize: 14)),
      onTap: () {
        Navigator.pop(context);
        onTap();
      },
      dense: true,
    );
  }
}

class _BackButton extends StatelessWidget {
  final VoidCallback onTap;
  const _BackButton({required this.onTap});

  @override
  Widget build(BuildContext context) => GestureDetector(
        onTap: onTap,
        child: Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: RC.overlay(0.15),
            border: Border.all(color: RC.overlay(0.30)),
          ),
          child: Icon(Icons.arrow_back, color: RC.textPri, size: 18),
        ),
      );
}

// ─────────────────────────────────────────────────────────────────────────────
// _RcNavLink — landing page's hover-animated nav link, extracted verbatim so
// every screen's desktop nav row matches exactly.
// ─────────────────────────────────────────────────────────────────────────────
class _RcNavLink extends StatefulWidget {
  final String label;
  final VoidCallback onTap;
  const _RcNavLink({required this.label, required this.onTap});

  @override
  State<_RcNavLink> createState() => _RcNavLinkState();
}

class _RcNavLinkState extends State<_RcNavLink> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        behavior: HitTestBehavior.opaque,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: _hovered ? RC.gold.withValues(alpha: 0.08) : null,
            borderRadius: BorderRadius.circular(8),
            border: Border(
              bottom: BorderSide(
                color: _hovered
                    ? RC.gold.withValues(alpha: 0.85)
                    : Colors.transparent,
                width: 2,
              ),
            ),
          ),
          child: Text(
            widget.label,
            style: TextStyle(
              fontSize: 13,
              color: _hovered ? RC.textPri : RC.textSec,
              fontWeight: _hovered ? FontWeight.w600 : FontWeight.w400,
            ),
          ),
        ),
      ),
    );
  }
}
