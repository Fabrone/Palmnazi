import 'package:flutter/material.dart';
import 'package:palmnazi/services/app_settings_controller.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AppStrings
//
// Lightweight English/Swahili dictionary — deliberately NOT flutter gen-l10n/
// ARB, since this app has no existing intl codegen pipeline. Every UI string
// gets a semantic key here; screens look it up via `context.tr(key)`, which
// reads the active language from AppSettingsScope. Falls back to the English
// value (or the raw key, so a missing translation is visible rather than
// crashing) when a key or language is unmatched.
//
// This dictionary currently covers the Settings section and Account screen —
// the first screens wired up for full bilingual support. Extend the maps
// below when converting additional screens; the lookup pattern doesn't
// change.
// ─────────────────────────────────────────────────────────────────────────────
abstract final class AppStrings {
  static const Map<String, String> _en = {
    // Settings section
    'settings_title': 'Settings',
    'settings_appearance': 'APPEARANCE',
    'settings_theme': 'Theme',
    'settings_theme_dark': 'Dark',
    'settings_theme_light': 'Light',
    'settings_theme_system': 'System Default',
    'settings_font': 'Font Style',
    'settings_font_subtitle': 'Choose how text is displayed across the app',
    'settings_language': 'LANGUAGE',
    'settings_language_label': 'App Language',
    'settings_language_english': 'English',
    'settings_language_swahili': 'Kiswahili',

    // Account screen
    'my_account': 'My Account',
    'account_bookings_section': 'BOOKINGS',
    'account_my_bookings': 'My Bookings',
    'account_my_bookings_sub': 'View and manage your booking requests',
    'account_my_queries': 'My Questions',
    'account_my_queries_sub': 'Questions you\'ve asked about places',
    'account_my_favorites': 'My Favorites',
    'account_my_favorites_sub': 'Places you\'ve saved',
    'account_place_admin_panel': 'Place Admin Panel',
    'account_place_admin_panel_sub':
        'Manage bookings, queries and details for your place',
    'account_admin_console': 'Admin Console',
    'account_admin_console_sub':
        'Full system management — places, bookings, reports',
    'account_security_section': 'SECURITY',
    'account_phone_mfa': 'Phone Two-Factor Auth',
    'account_phone_mfa_enabled_sub':
        'Enabled — an SMS code is required at each sign-in',
    'account_phone_mfa_disabled_sub':
        'Disabled — adds a phone SMS verification step at sign-in',
    'account_admin_access_section': 'ADMIN ACCESS',
    'account_sign_out': 'Sign Out',

    // Auth screen
    'auth_tab_login': 'Login',
    'auth_tab_signup': 'Sign Up',
    'auth_tab_magic_link': 'Magic Link',
    'auth_field_email': 'Email',
    'auth_field_password': 'Password',
    'auth_field_confirm_password': 'Confirm Password',
    'auth_btn_login': 'Login',
    'auth_btn_create_account': 'Create Account',
    'auth_btn_continue_google': 'Continue with Google',
    'auth_forgot_password': 'Forgot Password?',
    'auth_reset_code_link': 'Have a reset code? Set new password →',
    'auth_err_password_required': 'Please enter your password',
    'auth_err_confirm_password_required': 'Please confirm your password',
    'auth_err_passwords_mismatch': 'Passwords do not match',

    // Landing page — nav / footer / section chrome
    'nav_destinations': 'Destinations',
    'nav_blog': 'Blog',
    'nav_search': 'Search',
    'nav_sign_in': 'Sign In',
    'nav_my_account': 'My Account',
    'nav_careers': 'Careers',
    'footer_explore': 'Explore',
    'footer_contact': 'Contact',
    'footer_tagline':
        'Discover Africa\'s most beautiful resort\ndestinations and unforgettable experiences.',
    'footer_made_with_love': 'Made with ❤ for every kind of traveller',
    'section_explore_resort_cities': 'EXPLORE RESORT CITIES',
    'section_featured': 'Featured',
    'section_open': 'Open',
    'section_load_more': 'Load More',
    'section_under_maintenance': 'Under Maintenance',
    'section_admin_sign_in': 'Admin sign in',
    'empty_destinations_error': 'Could not load destinations',
    'empty_destinations_none': 'No destinations available yet',

    // Contact screen
    'contact_page_title': 'Contact Us',
    'contact_success_title': 'Message sent',
    'contact_success_body':
        "Thanks for reaching out — we'll get back to you as soon as we can.",
    'contact_back_button': 'Back',
    'contact_hero_heading': 'Get in Touch',
    'contact_hero_body':
        "Questions about a booking, a place you'd like to see added, or "
            "just feedback — send us a message and we'll reply by email.",
    'contact_field_name': 'Your Name',
    'contact_error_name_required': 'Enter your name',
    'contact_field_email': 'Your Email',
    'contact_error_email_required': 'Enter your email',
    'contact_error_email_invalid': 'Enter a valid email',
    'contact_field_message': 'Message',
    'contact_error_message_required': 'Enter a message',
    'contact_send_button': 'Send Message',
    'contact_email_directly_prefix': 'Or email us directly at',
    'contact_error_send_failed':
        'Could not send your message. Please try again.',
    'contact_error_email_app': 'Could not open your email app.',

    // About screen
    'about_page_title': 'About Us',

    // Careers screen
    'careers_page_title': 'Careers',
    'careers_not_hiring_heading': "We're not actively hiring right now",
    'careers_not_hiring_body':
        "But we're always excited to hear from people who care about "
            'building a great travel platform. Drop us a note and tell us '
            "what you'd love to work on — we keep every message on file "
            'for when a role opens up.',

    // Static info screen (Privacy Policy / Terms of Service / Cookie Policy)
    'static_info_last_updated_prefix': 'Last updated:',

    // Shared chrome — reused across resort city / category / place screens
    'common_tap_to_retry': 'Tap to retry',
    'nav_get_started': 'Get Started',
    'footer_about': 'About',
    'footer_privacy': 'Privacy',
    'footer_terms': 'Terms',

    // Resort city screen
    'resort_city_footer_copyright':
        '© 2026 Palmnazi Resort Cities. All rights reserved.',
    'resort_city_explore_pill': 'Explore',

    // Shared dialog chrome
    'common_cancel': 'Cancel',
    'common_send': 'Send',

    // Place details screen
    'place_details_dialog_signin_title': 'Sign in required',
    'place_details_dialog_signin_favorites_body':
        'You need an account to save favorites. Sign in (or create one), then come back to this place to continue.',
    'place_details_dialog_signin_booking_body':
        'You need an account to request a booking. Sign in (or create one), then come back to this place to continue.',
    'place_details_dialog_signin_question_body':
        'You need an account to ask a question. Sign in (or create one), then come back to this place to continue.',
    'place_details_ask_question_hint': 'What would you like to know?',
    'place_details_question_sent': 'Your question has been sent.',
    'place_details_loading_full_details': 'Loading full details…',
    'place_details_error_load_details':
        'Could not load full details. Tap to retry.',
    'place_details_quick_action_call': 'Call',
    'place_details_quick_action_directions': 'Directions',
    'place_details_quick_action_website': 'Website',
    'place_details_quick_action_share': 'Share',
    'place_details_error_dialer': 'Could not open the dialer.',
    'place_details_error_maps': 'Could not open maps.',
    'place_details_error_website_invalid':
        'This website address looks invalid.',
    'place_details_error_website': 'Could not open the website.',
    'place_details_error_share': 'Could not open the share sheet.',
    'place_details_error_favorites':
        'Could not update favorites. Please try again.',
    'place_details_section_about': 'About',
    'place_details_section_gallery': 'Gallery',
    'place_details_section_features': 'Features & Amenities',
    'place_details_section_artifacts': 'Artifacts',
    'place_details_section_payment_methods': 'Accepted Payment Methods',
    'place_details_section_contact': 'Contact Information',
    'place_details_contact_address': 'Address',
    'place_details_contact_area': 'Area',
    'place_details_contact_phone': 'Phone',
    'place_details_contact_email': 'Email',
    'place_details_section_booking_pricing': 'Booking & Pricing',
    'place_details_info_price': 'Price',
    'place_details_info_advance_notice': 'Advance notice',
    'place_details_info_min_stay': 'Min stay',
    'place_details_info_max_stay': 'Max stay',
    'place_details_info_cancellation': 'Cancellation',
    'place_details_button_book_now': 'Book Now',
    'place_details_button_enquire': 'Enquire',
    'place_details_tooltip_ask_question': 'Ask a Question',
    'place_details_tooltip_remove_favorite': 'Remove from favorites',
    'place_details_tooltip_add_favorite': 'Add to favorites',
    'place_details_bookable_badge': 'Bookable',
    'place_details_untitled': 'Untitled',
    'place_details_search_prefix': 'Search',

    // Category screen
    'category_subcat_all': 'All',

    // Shared chrome
    'common_done': 'Done',

    // Booking screen
    'booking_error_signin': 'You must be signed in to book.',
    'booking_error_select_checkout': 'Select a check-out date.',
    'booking_error_conflict_suffix':
        'is already booked for that date. Pick a different date or option.',
    'booking_success_title': 'Booking requested',
    'booking_success_prefix': 'Your booking request for',
    'booking_success_suffix':
        'has been sent. You\'ll see its status under My Bookings.',
    'booking_success_reference_label': 'BOOKING REFERENCE',
    'booking_success_copy_reference': 'Copy full reference',
    'booking_success_reference_copied': 'Booking reference copied.',
    'booking_success_reference_hint':
        'Show this reference at the front desk — staff can look it up to confirm exactly what you booked.',
    'booking_button_view_my_bookings': 'View My Bookings',
    'booking_appbar_prefix': 'Book',
    'booking_select_prefix': 'Select a',
    'booking_select_option': 'Select an option',
    'booking_section_checkin_checkout': 'Check-in / Check-out',
    'booking_section_preferred_date': 'Preferred Date',
    'booking_label_checkin': 'Check-in',
    'booking_label_checkout': 'Check-out',
    'booking_label_date': 'Date',
    'booking_section_guests': 'Number of Guests',
    'booking_estimated_total': 'Estimated Total',
    'booking_estimate_disclaimer':
        'Estimate only — the final amount is confirmed by the place.',
    'booking_section_payment_method': 'Payment Method',
    'booking_section_special_requests': 'Special Requests (optional)',
    'booking_notes_hint': 'Any special requirements…',
    'booking_button_request': 'Request Booking',
    'booking_option_prefix': 'Option',
    'booking_label_select': 'Select',

    // Shared chrome
    'common_ok': 'OK',

    // My Bookings screen
    'my_bookings_signin_required': 'Sign in to view your bookings.',
    'my_bookings_error_load_prefix': 'Could not load bookings:',
    'my_bookings_empty':
        'No bookings yet. Find a place you love and tap "Book Now".',
    'my_bookings_reference_prefix': 'Ref',
    'my_bookings_dialog_cancel_unavailable_title': 'Cancellation not available',
    'my_bookings_dialog_cancel_title': 'Cancel booking?',
    'my_bookings_dialog_cancel_body': 'This cannot be undone.',
    'my_bookings_button_keep': 'Keep it',
    'my_bookings_button_cancel_booking': 'Cancel booking',
    'my_bookings_mpesa_receipt_prefix': 'Paid via M-Pesa — receipt',
    'my_bookings_estimate_suffix': '(estimate)',

    // My Favorites screen
    'my_favorites_signin_required': 'Sign in to view your favorites.',
    'my_favorites_error_load_prefix': 'Could not load favorites:',
    'my_favorites_empty':
        'No favorites yet. Tap the heart icon on any listing to save it here.',
    'my_favorites_place_unavailable': 'This place is no longer available.',

    // My Queries screen
    'my_queries_signin_required': 'Sign in to view your questions.',
    'my_queries_error_load_prefix': 'Could not load questions:',
    'my_queries_empty':
        'No questions yet. Tap "Enquire" on a place to ask one.',
    'my_queries_status_answered': 'ANSWERED',
    'my_queries_status_pending': 'PENDING',

    // Blog post detail screen
    'blog_detail_title': 'Story',
    'blog_detail_not_found': 'This story could not be found.',
    'blog_detail_error_post_comment':
        'Could not post your comment. Please try again.',
    'blog_detail_loading': 'Loading…',
    'blog_detail_author_bio':
        'Writes stories for Palmnazi Resort Cities — guides, '
            'features and updates about resort destinations across '
            'the platform.',
    'blog_detail_sponsored_by_prefix': 'Sponsored by',
    'blog_detail_sponsored': 'Sponsored',
    'blog_detail_related_heading': 'Related to This Story',
    'blog_detail_comments_heading': 'Comments',
    'blog_detail_comment_hint': 'Share your thoughts…',
    'blog_detail_no_comments': 'Be the first to comment.',
    'blog_detail_no_content': 'This story has no content yet.',

    // Payment simulation screen
    'payment_sim_appbar_title_prefix': 'Pay with',
    'payment_sim_stage_sending': 'Sending STK push to your phone…',
    'payment_sim_error_invalid_phone': 'Enter a valid Safaricom number.',
    'payment_sim_mpesa_not_completed': 'The M-Pesa request was not completed.',
    'payment_sim_btn_send_stk': 'Send STK Push',
    'payment_sim_btn_pay_now': 'Pay Now',
    'payment_sim_btn_continue_paypal': 'Continue to PayPal',
    'payment_sim_btn_made_transfer': "I've Made the Transfer",
    'payment_sim_btn_confirm_cash': 'Confirm — Pay on Arrival',
    'payment_sim_btn_confirm_payment': 'Confirm Payment',
    'payment_sim_note_sandbox_mode':
        "Sandbox mode — this sends a real Daraja STK push request, but Safaricom's own test harness resolves it automatically. No real phone or money is involved.",
    'payment_sim_label_mpesa_phone': 'M-Pesa Phone Number',
    'payment_sim_hint_phone': '07XX XXX XXX',
    'payment_sim_note_stk_prefix':
        'An STK push will be sent to this number for',
    'payment_sim_note_stk_suffix':
        '(sandbox shortcode is used under the hood).',
    'payment_sim_paybill_label': 'Paybill',
    'payment_sim_configured_paybill': 'the configured paybill',
    'payment_sim_label_card_details': 'Card Details',
    'payment_sim_hint_card_number': 'Card Number',
    'payment_sim_hint_expiry': 'MM/YY',
    'payment_sim_hint_cvv': 'CVV',
    'payment_sim_note_card_demo':
        'Card payments are not yet processed by a live gateway — this is a demo flow only. Card details are never sent anywhere.',
    'payment_sim_note_paypal_prefix':
        'You would be redirected to PayPal to sign in and approve payment to',
    'payment_sim_configured_merchant': 'the configured merchant account',
    'payment_sim_label_transfer_instructions': 'Transfer Instructions',
    'payment_sim_field_bank': 'Bank',
    'payment_sim_field_account_number': 'Account Number',
    'payment_sim_field_account_name': 'Account Name',
    'payment_sim_not_configured': 'Not yet configured',
    'payment_sim_note_cash_prefix': 'Pay in cash directly at',
    'payment_sim_note_cash_suffix': 'upon arrival.',
    'payment_sim_note_other_prefix': 'Payment will be arranged directly with',
    'payment_sim_processing_card': 'Processing card payment…',
    'payment_sim_processing_paypal': 'Redirecting to PayPal…',
    'payment_sim_processing_bank': 'Recording your transfer…',
    'payment_sim_processing_cash': 'Confirming arrangement…',
    'payment_sim_processing_default': 'Processing…',
    'payment_sim_waiting_instructions':
        'Check your phone and enter your M-Pesa PIN to complete this payment.',
    'payment_sim_sent_to_prefix': 'Sent to',
    'payment_sim_btn_check_now': "I've entered my PIN — check now",
    'payment_sim_btn_cancel_back': 'Cancel and go back',
    'payment_sim_success_title': 'M-Pesa payment received',
    'payment_sim_receipt_prefix': 'Receipt:',
    'payment_sim_sandbox_transaction_note':
        "Sandbox transaction — this ran against Safaricom's Daraja test environment. No real money moved.",
    'payment_sim_btn_continue': 'Continue',
    'payment_sim_failed_title': 'Payment not completed',
    'payment_sim_failed_default_message':
        'The M-Pesa request was cancelled or timed out.',
    'payment_sim_btn_try_again': 'Try Again',
    'payment_sim_btn_back_out': 'Back out of booking',
    'payment_sim_done_title': 'Payment flow complete (simulated)',
    'payment_sim_demo_note':
        'This is a demonstration only. No real money has moved and no live payment gateway was contacted.',
    'payment_sim_completion_card_prefix':
        'In a live integration, this card would be charged',
    'payment_sim_completion_card_via': 'via',
    'payment_sim_configured_card_gateway': 'the configured card gateway',
    'payment_sim_card_gateway_not_configured':
        'a card gateway (not yet configured)',
    'payment_sim_completion_paypal_prefix':
        'In a live integration, you would have approved a',
    'payment_sim_completion_paypal_middle': 'payment on PayPal to',
    'payment_sim_completion_bank_prefix':
        'Your booking will be held pending manual confirmation that',
    'payment_sim_completion_bank_suffix':
        'was transferred to the account shown.',
    'payment_sim_completion_cash_prefix':
        'Your booking is recorded — please pay',
    'payment_sim_completion_cash_middle': 'in cash at',
    'payment_sim_completion_default_prefix':
        'Your booking is recorded — payment arrangements for',
    'payment_sim_completion_default_middle': 'will be confirmed directly with',

    // Reset password screen
    'reset_password_loading_message': 'Resetting your password…',
    'reset_password_title': 'Create New Password',
    'reset_password_subtitle':
        'Enter the reset code from your email\nand choose a strong new password.',
    'reset_password_label_reset_code': 'Reset Code',
    'reset_password_hint_reset_code': 'Paste your reset code here',
    'reset_password_err_code_required':
        'Please enter the reset code from your email',
    'reset_password_err_code_short':
        'Reset code appears too short — please check your email',
    'reset_password_hint_box_text':
        'Open the reset email we sent you and copy the full '
            'reset code, then paste it in the field above.',
    'reset_password_label_new_password': 'New Password',
    'reset_password_hint_new_password': 'Enter new password',
    'reset_password_err_password_required': 'Please enter a new password',
    'reset_password_err_password_length':
        'Password must be at least 8 characters',
    'reset_password_hint_confirm_password': 'Re-enter new password',
    'reset_password_btn_submit': 'Reset Password',
    'reset_password_back_to_login': 'Back to Login',
    'reset_password_success_title': 'Password Reset!',
    'reset_password_success_body':
        'Your password has been updated successfully.\n'
            'You can now log in with your new password.',
    'reset_password_strength_weak': 'Weak',
    'reset_password_strength_fair': 'Fair',
    'reset_password_strength_good': 'Good',
    'reset_password_strength_strong': 'Strong',
    'reset_password_strength_prefix': 'Strength:',

    // widgets/parallax_header
    'widget_parallax_header_brand': 'PALMNAZI',
    'widget_parallax_header_subtitle': 'RESORT CITIES',
    'widget_parallax_header_tagline':
        'Discover Kenya\'s Most Exquisite Resort Destinations',
    'widget_parallax_header_cta': 'Explore Destinations',
    'widget_parallax_header_scroll_hint': 'Scroll to discover more',

    // widgets/channel_showcase
    'widget_channel_showcase_title': 'Explore Our Channels',
    'widget_channel_showcase_subtitle':
        'Browse through our carefully curated categories to find exactly what you\'re looking for',
    'widget_channel_showcase_tap_hint': 'Tap to explore',

    // widgets/feature_carousel
    'widget_feature_carousel_title': 'What We Offer',
    'widget_feature_carousel_subtitle':
        'Explore curated services for an unforgettable resort experience',
    'widget_feature_carousel_explore_cta': 'Explore',
    'widget_feature_carousel_accommodation_title': 'Premium Accommodation',
    'widget_feature_carousel_accommodation_desc':
        'Experience world-class hospitality in Kenya\'s finest resort cities. From luxurious beachfront villas to serene mountain lodges, discover handpicked accommodations that offer exceptional comfort, breathtaking views, and personalized service.',
    'widget_feature_carousel_dining_title': 'Exquisite Dining',
    'widget_feature_carousel_dining_desc':
        'Embark on a culinary adventure through Kenya with our curated collection of world-class restaurants and authentic local eateries. From fresh ocean catches to traditional Kenyan delicacies, savor dishes crafted with passion.',
    'widget_feature_carousel_events_title': 'Cultural Events',
    'widget_feature_carousel_events_desc':
        'Immerse yourself in vibrant cultural celebrations, music festivals, and traditional ceremonies. Connect with local communities, witness age-old traditions, and participate in events that unite people across cultures.',
    'widget_feature_carousel_shopping_title': 'Artisan Shopping',
    'widget_feature_carousel_shopping_desc':
        'Discover authentic Kenyan craftsmanship at vibrant local markets and boutique shops. Find one-of-a-kind souvenirs, handcrafted jewelry, traditional textiles, and contemporary art that tells a meaningful story.',
    'widget_feature_carousel_adventure_title': 'Adventure & Nature',
    'widget_feature_carousel_adventure_desc':
        'Explore breathtaking landscapes from pristine beaches to majestic mountains. Engage in safari adventures, mountain hiking, water sports, and unforgettable wildlife encounters through sustainable tourism.',

    // widgets/stats_counter
    'widget_stats_counter_resort_cities': 'Resort Cities',
    'widget_stats_counter_businesses': 'Businesses',
    'widget_stats_counter_happy_visitors': 'Happy Visitors',
    'widget_stats_counter_average_rating': 'Average Rating',

    // widgets/place_card
    'widget_place_card_reviews_suffix': 'reviews',
    'widget_place_card_view_details': 'View Details',
    'widget_place_card_open': 'Open',
    'widget_place_card_closed': 'Closed',

    // widgets/place_search_picker
    'widget_place_search_picker_title': 'Select a Place',
    'widget_place_search_picker_subtitle':
        'Search for the place you manage or want to manage.',
    'widget_place_search_picker_hint': 'Search by place name…',
    'widget_place_search_picker_prompt': 'Start typing to find a place.',
    'widget_place_search_picker_empty': 'No matching places found.',

    // Shared admin widgets
    'common_retry': 'Retry',

    // Admin contact messages screen
    'admin_contact_messages_error_load_prefix': 'Could not load messages:',
    'admin_contact_messages_empty_title': 'No messages yet',
    'admin_contact_messages_empty_body':
        'Submissions from the landing page\'s "Contact Us" form will '
            'show up here.',
    'admin_contact_messages_copy_email_tooltip': 'Copy email',
    'admin_contact_messages_email_copied': 'Email copied',

    // Admin bookings screen
    'admin_bookings_page_title': 'Bookings',
    'admin_bookings_page_subtitle':
        'Requests submitted by tourists from the place pages',
    'admin_bookings_empty_title': 'No bookings',
    'admin_bookings_empty_body_all':
        'Bookings submitted by tourists will show up here.',
    'admin_bookings_empty_filtered_prefix': 'No',
    'admin_bookings_empty_filtered_suffix': 'bookings.',
    'admin_bookings_guest_singular': 'guest',
    'admin_bookings_guest_plural': 'guests',
    'admin_bookings_reference_prefix': 'Ref',
    'admin_bookings_cancellation_suffix': 'cancellation',
    'admin_bookings_btn_confirm': 'Confirm',
    'admin_bookings_btn_mark_completed': 'Mark Completed',

    // Shared admin dialog chrome
    'common_delete': 'Delete',
    'common_add': 'Add',
    'common_save': 'Save',

    // Admin payment methods screen
    'admin_payment_methods_add_button': 'Add Payment Method',
    'admin_payment_methods_page_title': 'Payment Methods',
    'admin_payment_methods_page_subtitle':
        'Configure the payment options places can accept',
    'admin_payment_methods_empty_title': 'No payment methods yet',
    'admin_payment_methods_empty_body':
        'Add the payment options places can accept, e.g. M-Pesa, Card, or Cash on Arrival.',
    'admin_payment_methods_delete_confirm_prefix': 'Delete',
    'admin_payment_methods_delete_confirm_body':
        'Places that accept this payment method will no longer show it as an option. This cannot be undone.',
    'admin_payment_methods_edit_title': 'Edit Payment Method',
    'admin_payment_methods_error_name_required': 'Name is required',
    'admin_payment_methods_error_save_failed_prefix': 'Save failed:',
    'admin_payment_methods_field_name': 'Name',
    'admin_payment_methods_hint_name_example': 'e.g. M-Pesa',
    'admin_payment_methods_field_type': 'Type',
    'admin_payment_methods_field_description': 'Description',
    'admin_payment_methods_hint_description':
        'Optional note shown to admins, e.g. "Paybill 123456"',
    'admin_payment_methods_field_icon': 'Icon (emoji)',
    'admin_payment_methods_hint_icon': 'e.g. 📱',
    'admin_payment_methods_field_sort_order': 'Sort Order',
    'admin_payment_methods_gateway_config_title':
        'Gateway Configuration (placeholder)',
    'admin_payment_methods_gateway_config_note':
        'These fields are stored for reference only — no real gateway is wired up yet. Fill them in once this method is ready for actual integration.',
    'admin_payment_methods_field_active': 'Active',

    // Admin audit log screen
    'admin_audit_log_csv_header_timestamp': 'Timestamp',
    'admin_audit_log_csv_header_admin': 'Admin',
    'admin_audit_log_csv_header_action': 'Action',
    'admin_audit_log_csv_header_module': 'Module',
    'admin_audit_log_csv_header_target': 'Target',
    'admin_audit_log_csv_header_details': 'Details',
    'admin_audit_log_export_success_prefix': 'Exported',
    'admin_audit_log_export_success_suffix': 'row(s).',
    'admin_audit_log_error_load_prefix': 'Could not load audit log:',
    'admin_audit_log_filter_all_prefix': 'All',
    'admin_audit_log_export_button': 'Export CSV',
    'admin_audit_log_empty_title': 'No activity yet',
    'admin_audit_log_empty_body':
        'Admin actions (creating/editing/deleting places, '
            'cities, categories, roles, blog posts) will show '
            'up here as they happen.',

    // Admin static pages screen
    'admin_static_pages_label_about': 'About Us',
    'admin_static_pages_label_privacy': 'Privacy Policy',
    'admin_static_pages_label_terms': 'Terms of Service',
    'admin_static_pages_label_cookie': 'Cookie Policy',
    'admin_static_pages_not_edited_yet':
        'Not edited yet — showing built-in default copy',
    'admin_static_pages_last_edited_by_prefix': 'Last edited by',
    'admin_static_pages_unknown_editor': 'unknown',
    'admin_static_pages_edit_button': 'Edit',
    'admin_static_pages_edit_title_prefix': 'Edit',
    'admin_static_pages_error_save_failed_prefix': 'Could not save:',
    'admin_static_pages_field_page_title': 'Page Title',
    'admin_static_pages_field_subtitle': 'Subtitle / Tagline',
    'admin_static_pages_subtitle_helper': 'Optional — used on About Us only',
    'admin_static_pages_field_last_updated': 'Last Updated Label',
    'admin_static_pages_hint_last_updated': 'e.g. July 2026',
    'admin_static_pages_sections_heading': 'Sections',
    'admin_static_pages_section_prefix': 'Section',
    'admin_static_pages_field_heading': 'Heading',
    'admin_static_pages_heading_helper': 'Leave blank for a plain paragraph',
    'admin_static_pages_field_body': 'Body',
    'admin_static_pages_add_section': 'Add section',
    'admin_static_pages_saving': 'Saving…',
    'admin_static_pages_save_page': 'Save Page',

    // Admin settings screen
    'admin_settings_audit_target_system_settings': 'System Settings',
    'admin_settings_saved_success': 'Settings saved.',
    'admin_settings_error_save_failed_prefix': 'Could not save settings:',
    'admin_settings_maintenance_confirm_title': 'Enable Maintenance Mode?',
    'admin_settings_maintenance_confirm_body':
        'Tourists will see a maintenance notice instead of the landing page '
            'until this is turned off again. Admins are unaffected.',
    'admin_settings_btn_enable': 'Enable',
    'admin_settings_audit_enabled': 'Enabled',
    'admin_settings_audit_disabled': 'Disabled',
    'admin_settings_maintenance_enabled': 'Maintenance mode enabled.',
    'admin_settings_maintenance_disabled': 'Maintenance mode disabled.',
    'admin_settings_error_maintenance_update_failed_prefix':
        'Could not update maintenance mode:',
    'admin_settings_audit_target_maintenance_mode': 'Maintenance Mode',
    'admin_settings_export_success_prefix': 'Exported',
    'admin_settings_export_success_suffix':
        'document(s) across every Firestore collection. Places/Cities/Categories/Bookings-config live in the backend database and are not covered by this export.',
    'admin_settings_error_export_failed_prefix': 'Export failed:',
    'admin_settings_section_contact_title': 'Public Contact Info',
    'admin_settings_section_contact_subtitle':
        'Shown in the landing page footer and contact screens.',
    'admin_settings_field_contact_email': 'Contact Email',
    'admin_settings_field_contact_phone': 'Contact Phone',
    'admin_settings_section_footer_links_title': 'Footer Links',
    'admin_settings_section_footer_links_subtitle':
        'Extra links shown in the landing page footer.',
    'admin_settings_field_link_label': 'Label',
    'admin_settings_hint_link_label': 'e.g. Terms of Service',
    'admin_settings_field_link_url': 'URL',
    'admin_settings_add_link': 'Add link',
    'admin_settings_section_maintenance_title': 'Maintenance Mode',
    'admin_settings_section_maintenance_subtitle':
        'When on, tourists see a maintenance notice instead of '
            'the landing page. Admins can still sign in and manage '
            'the platform as normal.',
    'admin_settings_maintenance_on': 'Maintenance mode is ON',
    'admin_settings_maintenance_off': 'Maintenance mode is OFF',
    'admin_settings_field_maintenance_message': 'Maintenance Message',
    'admin_settings_hint_maintenance_message':
        "We'll be back shortly — thanks for your patience.",
    'admin_settings_section_export_title': 'Data Export',
    'admin_settings_section_export_subtitle':
        'Downloads every Firestore-backed collection (Users, '
            'Favorites, Bookings, Admin Requests, Payment Methods, '
            'Place details, Place Queries, City details, Category '
            'details, Settings, Static Pages, Audit Log) as one '
            'JSON file. Places, Cities, Categories and Bookings '
            'configuration live in the backend database — a real '
            'backup of that data needs DB-level tooling on the '
            'hosting side, not this button.',
    'admin_settings_exporting': 'Exporting…',
    'admin_settings_export_button': 'Export Firestore Data',
    'admin_settings_saving': 'Saving…',
    'admin_settings_save_button': 'Save Settings',

    // Admin reports screen
    'admin_reports_csv_header_section': 'Section',
    'admin_reports_csv_header_label': 'Label',
    'admin_reports_csv_header_value': 'Value',
    'admin_reports_csv_section_bookings': 'Bookings',
    'admin_reports_csv_label_total': 'Total',
    'admin_reports_csv_label_pending': 'Pending',
    'admin_reports_csv_label_confirmed': 'Confirmed',
    'admin_reports_csv_label_completed': 'Completed',
    'admin_reports_csv_label_cancelled': 'Cancelled',
    'admin_reports_csv_label_estimated_revenue': 'Estimated Revenue',
    'admin_reports_csv_section_visitor_traffic': 'Visitor Traffic',
    'admin_reports_csv_label_total_page_views': 'Total Page Views (30d)',
    'admin_reports_csv_section_businesses_per_city': 'Businesses per City',
    'admin_reports_csv_section_businesses_per_channel':
        'Businesses per Channel',
    'admin_reports_page_title': 'Reports',
    'admin_reports_export_button': 'Export CSV',
    'admin_reports_bookings_heading': 'Bookings — System Wide',
    'admin_reports_bookings_subtitle':
        'Live totals across every place on the platform.',
    'admin_reports_stat_total_bookings': 'Total Bookings',
    'admin_reports_stat_paid_via_mpesa': 'Paid via M-Pesa',
    'admin_reports_stat_simulated_payments': 'Simulated Payments',
    'admin_reports_top_places_heading': 'Top Places by Bookings',
    'admin_reports_no_bookings_yet': 'No bookings yet.',
    'admin_reports_booking_singular': 'booking',
    'admin_reports_booking_plural': 'bookings',
    'admin_reports_visitor_traffic_heading': 'Visitor Traffic — Last 30 Days',
    'admin_reports_visitor_traffic_subtitle':
        'Landing page loads, tracked by this app (a separate '
            'copy is also sent to Google Analytics — GA4 data '
            'itself isn\'t readable back from the app).',
    'admin_reports_traffic_not_enough':
        'Not enough traffic history yet — check back after a few days.',
    'admin_reports_no_cities_yet': 'No resort cities yet.',
    'admin_reports_place_singular': 'place',
    'admin_reports_place_plural': 'places',
    'admin_reports_no_categories_yet': 'No categories yet.',

    // Admin categories screen
    'admin_categories_page_title': 'Categories',
    'admin_categories_page_subtitle':
        'Global service categories — shared across all cities',
    'admin_categories_add_button': 'Add Category',
    'admin_categories_search_hint': 'Search categories…',
    'admin_categories_filter_active': 'Active',
    'admin_categories_filter_inactive': 'Inactive',
    'admin_categories_empty_title': 'No categories yet',
    'admin_categories_empty_body':
        'Create your first category like Accommodation, Dining, or Wellness.',
    'admin_categories_add_first_button': 'Add First Category',
    'admin_categories_snack_created': 'Category created',
    'admin_categories_snack_updated': 'Category updated',
    'admin_categories_snack_subcategory_added_prefix': 'Subcategory added to',
    'admin_categories_snack_subcategory_updated': 'Subcategory updated',
    'admin_categories_snack_deleted_prefix': 'Deleted',
    'admin_categories_snack_delete_failed_prefix': 'Delete failed:',
    'admin_categories_delete_confirm_title_prefix': 'Delete',
    'admin_categories_delete_confirm_body_default':
        'This action cannot be undone.',
    'admin_categories_delete_confirm_body_has_children':
        'This will also delete all subcategories. Use cascade delete.',
    'admin_categories_delete_confirm_body_has_links_prefix':
        'This category is linked to',
    'admin_categories_delete_confirm_body_has_links_suffix':
        'place(s). Remove links first.',
    'admin_categories_menu_edit': 'Edit',
    'admin_categories_menu_deactivate': 'Deactivate',
    'admin_categories_menu_activate': 'Activate',
    'admin_categories_status_active': 'Active',
    'admin_categories_status_inactive': 'Inactive',
    'admin_categories_count_subcats': 'subcats',
    'admin_categories_count_places': 'places',
    'admin_categories_add_subcategory_prefix': 'Add subcategory to',
    'admin_categories_dialog_edit_category': 'Edit Category',
    'admin_categories_dialog_edit_subcategory': 'Edit Subcategory',
    'admin_categories_dialog_add_category': 'Add Category',
    'admin_categories_dialog_add_subcategory': 'Add Subcategory',
    'admin_categories_field_category_type': 'Category Type',
    'admin_categories_root_category_label': 'Root category (top level)',
    'admin_categories_subcategory_of_prefix': 'Subcategory of:',
    'admin_categories_field_name': 'Category Name',
    'admin_categories_hint_name': 'e.g. Accommodation',
    'admin_categories_field_slug': 'Slug',
    'admin_categories_hint_slug': 'e.g. accommodation',
    'admin_categories_helper_slug':
        'Auto-generated from name. Lowercase, hyphens only.',
    'admin_categories_hint_icon': '🏨',
    'admin_categories_helper_icon': 'Paste a single emoji character',
    'admin_categories_field_description': 'Description',
    'admin_categories_hint_description': 'Brief description of this category',
    'admin_categories_field_sort_order': 'Sort Order',
    'admin_categories_helper_sort_order': 'Lower numbers appear first',
    'admin_categories_field_tags': 'Tags',
    'admin_categories_hint_tags': 'e.g. beachfront, family-friendly, budget',
    'admin_categories_helper_tags':
        'Comma-separated — used for search/filtering',
    'admin_categories_field_visible_in': 'Visible In',
    'admin_categories_visible_all_cities': 'All resort cities (default)',
    'admin_categories_visible_selected_suffix': 'selected city/cities',

    // Admin place map picker
    'admin_place_map_picker_title': 'Select Location on Map',
    'admin_place_map_picker_tooltip_normal': 'Normal Map',
    'admin_place_map_picker_tooltip_satellite': 'Satellite',
    'admin_place_map_picker_resolving': 'RESOLVING…',
    'admin_place_map_picker_confirm': 'CONFIRM',
    'admin_place_map_picker_search_hint':
        'Search for a place, hotel, restaurant, area…',
    'admin_place_map_picker_no_results':
        'No results found. Try a different name, or tap directly on the map.',
    'admin_place_map_picker_resolving_address': 'Resolving address…',
    'admin_place_map_picker_bottom_hint':
        'Tap anywhere on the map to drop a pin. Drag the pin to fine-tune. '
            'Search above to find named places. Tap ✕ on the info bar above '
            'to clear a mis-placed pin.',
    'admin_place_map_picker_snack_select_first':
        'Tap the map or search to select a location first.',
    'admin_place_map_picker_snack_still_resolving':
        'Still resolving the address for this pin — one moment.',
    'admin_place_map_picker_tooltip_clear_pin': 'Clear pin',
    'admin_place_map_picker_crash_title': 'Map Preview Unavailable',
    'admin_place_map_picker_crash_default_message':
        'The map service is unavailable.',
    'admin_place_map_picker_crash_fallback_note':
        'Good news: search above and Confirm still work without it — only '
            'tap-to-drop-pin and drag-to-adjust need the visual map.',
    'admin_place_map_picker_close_manual': 'Close & Enter Manually',
    'admin_place_map_picker_watchdog_message':
        'The visual map preview isn\'t loading — this usually means the '
            'Maps service isn\'t fully activated for this app yet.',

    // Admin places screen
    'admin_places_add_button': 'Add Place',
    'admin_places_page_title': 'Places',
    'admin_places_subtitle_all': 'All places across all cities',
    'admin_places_subtitle_filtered_prefix': 'Filtered by:',
    'admin_places_delete_confirm_active_body':
        'This place is currently ACTIVE. Deleting it will remove it from '
            'the app. This cannot be undone.',
    'admin_places_snack_deleted_prefix': 'Deleted',
    'admin_places_snack_delete_failed_prefix': 'Delete failed:',
    'admin_places_snack_featured_suffix': 'is now featured',
    'admin_places_snack_unfeatured_suffix': 'unfeatured',
    'admin_places_snack_update_failed_prefix': 'Could not update:',
    'admin_places_snack_loading_data': 'Loading data…',
    'admin_places_search_hint_narrow': 'Search places…',
    'admin_places_search_hint_wide': 'Search by name, city, or address…',
    'admin_places_status_active': 'Active',
    'admin_places_status_pending': 'Pending',
    'admin_places_status_suspended': 'Suspended',
    'admin_places_status_archived': 'Archived',
    'admin_places_empty_title_none': 'No places yet',
    'admin_places_empty_title_no_matches': 'No matches',
    'admin_places_empty_body_none':
        'Create your first place using the wizard.\nFill in basic info, '
            'location, media, and link it to categories.',
    'admin_places_empty_body_no_matches': 'Try a different search or filter.',
    'admin_places_empty_action_add_first': 'Add First Place',
    'admin_places_filter_all_cities': 'All cities',
    'admin_places_filter_all_categories': 'All categories',
    'admin_places_menu_edit_continue': 'Edit / Continue',
    'admin_places_menu_unfeature': 'Unfeature',
    'admin_places_menu_feature': 'Feature on homepage/category',
    'admin_places_completion_suffix': '% complete',
    'admin_places_draft_badge': 'DRAFT',
    'admin_places_continue_button': 'Continue',
    'admin_places_edit_button': 'Edit',

    // Admin blog compose screen
    'admin_blog_compose_title_edit': 'Edit Post',
    'admin_blog_compose_title_new': 'New Blog Post',
    'admin_blog_compose_tab_content': 'Content',
    'admin_blog_compose_tab_meta_seo': 'Meta & SEO',
    'admin_blog_compose_tab_settings': 'Settings',
    'admin_blog_compose_save_draft': 'Save Draft',
    'admin_blog_compose_publish_button': 'Publish',
    'admin_blog_compose_error_title_required': 'Title is required',
    'admin_blog_compose_error_content_min_prefix':
        'Content must be at least 100 characters (currently',
    'admin_blog_compose_error_content_min_suffix': ')',
    'admin_blog_compose_error_scheduled_required':
        'Scheduled date/time is required',
    'admin_blog_compose_snack_updated': 'Post updated successfully',
    'admin_blog_compose_snack_created': 'Post created successfully',
    'admin_blog_compose_field_post_title': 'Post Title',
    'admin_blog_compose_hint_post_title': 'e.g. 10 Best Hotels in Mombasa',
    'admin_blog_compose_field_content': 'Content',
    'admin_blog_compose_rich_text_badge': 'Rich Text',
    'admin_blog_compose_editor_placeholder':
        'Start writing your article here. Use the toolbar above to format '
            'text, add headings, bullet lists, links…',
    'admin_blog_compose_min_characters_note':
        'Minimum 100 characters of actual content.',
    'admin_blog_compose_field_excerpt': 'Excerpt',
    'admin_blog_compose_hint_excerpt': 'Short teaser shown in post listings…',
    'admin_blog_compose_helper_excerpt':
        'Optional — auto-generated if left empty.',
    'admin_blog_compose_field_categories': 'Categories',
    'admin_blog_compose_hint_categories': 'accommodation, dining, wellness',
    'admin_blog_compose_helper_categories': 'Comma-separated category slugs.',
    'admin_blog_compose_field_tags': 'Tags',
    'admin_blog_compose_hint_tags': 'luxury, budget-friendly, family',
    'admin_blog_compose_helper_tags': 'Comma-separated tags.',
    'admin_blog_compose_seo_preview_heading': 'SEO Preview',
    'admin_blog_compose_seo_preview_url': 'resortcities.com › blog',
    'admin_blog_compose_seo_preview_title_placeholder': 'Page title…',
    'admin_blog_compose_seo_preview_desc_placeholder':
        'Meta description will appear here…',
    'admin_blog_compose_field_meta_title': 'Meta Title',
    'admin_blog_compose_hint_meta_title':
        'e.g. 10 Best Hotels in Mombasa — 2026 Guide',
    'admin_blog_compose_helper_meta_title': 'Recommended: 50–60 characters.',
    'admin_blog_compose_field_meta_desc': 'Meta Description',
    'admin_blog_compose_hint_meta_desc':
        'Compelling description for search engines…',
    'admin_blog_compose_helper_meta_desc': 'Recommended: 150–160 characters.',
    'admin_blog_compose_field_featured_image': 'Featured Image URL',
    'admin_blog_compose_hint_featured_image':
        'https://cdn.resortcities.com/images/…',
    'admin_blog_compose_helper_featured_image':
        'Full URL to the post cover image.',
    'admin_blog_compose_image_preview_error': 'Could not load image preview',
    'admin_blog_compose_post_status_label': 'Post Status',
    'admin_blog_compose_field_scheduled': 'Publish Date & Time (ISO 8601)',
    'admin_blog_compose_helper_scheduled': 'Format: YYYY-MM-DDTHH:MM:SSZ',
    'admin_blog_compose_save_scheduled_button': 'Save as Scheduled',
    'admin_blog_compose_field_city_id': 'City ID (optional)',
    'admin_blog_compose_helper_city_id':
        'Associate this post with a specific resort city.',
    'admin_blog_compose_publishing_notes_heading': 'Publishing Notes',
    'admin_blog_compose_publishing_notes_body':
        '• DRAFT — only visible in admin.\n'
            '• PUBLISHED — live immediately on the user app.\n'
            '• SCHEDULED — goes live at the specified date & time.',

    // Admin role requests screen
    'admin_role_requests_error_approve_missing_uid':
        'Cannot approve: user Firebase UID is missing from this request.',
    'admin_role_requests_error_approve_failed':
        'Approval failed. Please try again.',
    'admin_role_requests_snack_approved_as': 'approved as',
    'admin_role_requests_snack_request_from': 'Request from',
    'admin_role_requests_snack_declined_suffix': 'declined.',
    'admin_role_requests_error_deny_failed': 'Action failed. Please try again.',
    'admin_role_requests_error_revoke_missing_uid':
        'Cannot revoke: user Firebase UID is missing.',
    'admin_role_requests_revoke_confirm_title': 'Revoke Admin Role?',
    'admin_role_requests_revoke_confirm_body_prefix': 'This will remove the',
    'admin_role_requests_revoke_confirm_body_middle': 'role from',
    'admin_role_requests_revoke_confirm_body_suffix':
        'and reset their account to Tourist level. They can re-apply at any time.',
    'admin_role_requests_confirm_revoke': 'Revoke',
    'admin_role_requests_snack_role_revoked_prefix': 'Role revoked for',
    'admin_role_requests_error_revoke_failed':
        'Revoke failed. Please try again.',
    'admin_role_requests_delete_confirm_title': 'Delete Request?',
    'admin_role_requests_delete_confirm_body_prefix':
        'This will permanently remove the declined request from',
    'admin_role_requests_delete_confirm_body_suffix': 'This cannot be undone.',
    'admin_role_requests_snack_deleted_suffix': 'deleted.',
    'admin_role_requests_error_delete_failed':
        'Delete failed. Please try again.',
    'admin_role_requests_error_switch_missing_uid':
        'Cannot switch role: user Firebase UID is missing.',
    'admin_role_requests_error_reassign_missing_uid':
        'Cannot reassign: user Firebase UID is missing.',
    'admin_role_requests_tab_pending': 'Pending',
    'admin_role_requests_tab_approved': 'Approved',
    'admin_role_requests_tab_denied': 'Denied',
    'admin_role_requests_stat_total': 'Total',
    'admin_role_requests_approve_sheet_title': 'Approve Request',
    'admin_role_requests_approve_sheet_notice_prefix':
        'Approving will grant the selected role and immediately update',
    'admin_role_requests_approve_sheet_notice_suffix':
        'access across the platform.',
    'admin_role_requests_select_role_to_grant': 'Select Role to Grant',
    'admin_role_requests_role_desc_city_manager':
        'Manages one assigned place — bookings, queries, details. Can '
            'add/edit and delete within that place.',
    'admin_role_requests_role_desc_content_admin':
        'Same one-place scope as City Manager, but can add/edit content '
            'only — cannot delete core data.',
    'admin_role_requests_role_desc_main_admin':
        'Full system access including assigning and revoking every role.',
    'admin_role_requests_approve_as_prefix': 'Approve as',
    'admin_role_requests_switch_sheet_title': 'Switch Role',
    'admin_role_requests_switch_sheet_notice_currently_prefix': 'Currently',
    'admin_role_requests_switch_sheet_notice_suffix':
        'Switching will immediately update',
    'admin_role_requests_switch_sheet_notice_suffix2':
        'access across the platform. If the new role needs a place '
            'assignment and none is on file, you\'ll be asked to pick one '
            'next.',
    'admin_role_requests_select_new_role': 'Select New Role',
    'admin_role_requests_select_different_role': 'Select a different role',
    'admin_role_requests_switch_to_prefix': 'Switch to',
    'admin_role_requests_deny_sheet_title': 'Decline Request',
    'admin_role_requests_deny_sheet_notice_prefix':
        'The user will be notified that their admin request for',
    'admin_role_requests_deny_sheet_notice_suffix': 'has been declined.',
    'admin_role_requests_reason_for_denial': 'Reason for Denial (optional)',
    'admin_role_requests_reason_hint':
        'e.g. Insufficient supporting documentation.',
    'admin_role_requests_btn_decline_request': 'Decline Request',
    'admin_role_requests_status_pending': 'PENDING',
    'admin_role_requests_status_approved': 'APPROVED',
    'admin_role_requests_status_declined': 'DECLINED',
    'admin_role_requests_services_offered': 'SERVICES OFFERED',
    'admin_role_requests_meta_submitted_prefix': 'Submitted:',
    'admin_role_requests_meta_by_prefix': 'By:',
    'admin_role_requests_meta_role_prefix': 'Role:',
    'admin_role_requests_reason_prefix': 'Reason:',
    'admin_role_requests_btn_decline': 'Decline',
    'admin_role_requests_btn_approve': 'Approve',
    'admin_role_requests_btn_reassign_place': 'Reassign Place',
    'admin_role_requests_btn_switch_role': 'Switch Role',
    'admin_role_requests_btn_revoke_role': 'Revoke Role',
    'admin_role_requests_btn_reapprove': 'Re-approve',
    'admin_role_requests_empty_all': 'requests',
    'admin_role_requests_empty_pending': 'pending requests',
    'admin_role_requests_empty_approved': 'approved requests',
    'admin_role_requests_empty_declined': 'declined requests',
    'admin_role_requests_empty_prefix': 'No',
    'admin_role_requests_empty_body': 'They will appear here when submitted.',
    'admin_role_requests_error_load_title': 'Failed to load requests',

    // Admin Dashboard shell
    'admin_dashboard_nav_dashboard': 'Dashboard',
    'admin_dashboard_nav_resort_cities': 'Resort Cities',
    'admin_dashboard_nav_categories': 'Categories',
    'admin_dashboard_nav_places': 'Places',
    'admin_dashboard_nav_blog': 'Blog',
    'admin_dashboard_nav_role_requests': 'Role Requests',
    'admin_dashboard_nav_payment_methods': 'Payment Methods',
    'admin_dashboard_nav_bookings': 'Bookings',
    'admin_dashboard_nav_reports': 'Reports',
    'admin_dashboard_nav_messages': 'Messages',
    'admin_dashboard_nav_settings': 'Settings',
    'admin_dashboard_nav_static_pages': 'Static Pages',
    'admin_dashboard_nav_audit_log': 'Audit Log',
    'admin_dashboard_title_admin_console': 'Admin Console',
    'admin_dashboard_subtitle_overview': 'System overview & quick actions',
    'admin_dashboard_subtitle_resort_cities':
        'Add, edit and remove resort destinations',
    'admin_dashboard_subtitle_categories':
        'Manage global categories and subcategories',
    'admin_dashboard_subtitle_places_filtered_prefix': 'Showing places in',
    'admin_dashboard_subtitle_places': 'Manage listings and places',
    'admin_dashboard_subtitle_blog': 'Create, edit and publish blog articles',
    'admin_dashboard_role_requests_pending_singular':
        'pending request awaiting review',
    'admin_dashboard_role_requests_pending_plural':
        'pending requests awaiting review',
    'admin_dashboard_subtitle_role_requests':
        'Review and manage admin role requests',
    'admin_dashboard_subtitle_payment_methods':
        'Configure the payment options places can accept',
    'admin_dashboard_subtitle_bookings':
        'Review and manage tourist booking requests',
    'admin_dashboard_subtitle_reports': 'System-wide bookings analytics',
    'admin_dashboard_subtitle_messages':
        'Messages submitted through the landing page contact form',
    'admin_dashboard_subtitle_settings':
        'Contact info, footer links, maintenance mode and data export',
    'admin_dashboard_subtitle_static_pages':
        'Edit About Us, Privacy Policy, Terms of Service, Cookie Policy',
    'admin_dashboard_subtitle_audit_log':
        'Every admin action, in order — who did what, and when',
    'admin_dashboard_logo_label': 'Admin',
    'admin_dashboard_place_admin': 'Place Admin',
    'admin_dashboard_place_admin_sub': 'Manage a specific place',
    'admin_dashboard_back_to_app': 'Back to App',
    'admin_dashboard_no_place_title': 'No place assigned yet',
    'admin_dashboard_no_place_body':
        'A MainAdmin needs to link your account to a place before you can manage anything here.',
    'admin_dashboard_active_filters': 'Active filters',
    'admin_dashboard_stat_registered_users': 'Registered Users',
    'admin_dashboard_stat_active_places': 'Active Places',
    'admin_dashboard_stat_pending_drafts': 'Pending Drafts',
    'admin_dashboard_quick_actions': 'Quick Actions',
    'admin_dashboard_qa_add_resort_city': 'Add Resort City',
    'admin_dashboard_qa_add_resort_city_desc':
        'Create a new resort destination',
    'admin_dashboard_qa_add_category': 'Add Category',
    'admin_dashboard_qa_add_category_desc': 'Create a global service category',
    'admin_dashboard_qa_add_place': 'Add Place',
    'admin_dashboard_qa_add_place_desc': 'List a new place or business',
    'admin_dashboard_qa_write_blog': 'Write Blog Post',
    'admin_dashboard_qa_write_blog_desc': 'Publish a new article or guide',
    'admin_dashboard_qa_role_requests_desc': 'Review admin role applications',
    'admin_dashboard_qa_role_requests_pending_suffix':
        'pending • tap to review',
    'admin_dashboard_qa_payment_methods_desc':
        'Configure accepted payment options',
    'admin_dashboard_qa_bookings_desc': 'Review tourist booking requests',
    'admin_dashboard_growth_title': 'Growth — Last 30 Days',
    'admin_dashboard_growth_desc':
        'Active places, resort cities and registered users, sampled '
            'once per day.',
    'admin_dashboard_growth_no_history':
        'Not enough history yet — check back after a few '
            'days of activity to see a trend.',
    'admin_dashboard_legend_active_places': 'Active places',
    'admin_dashboard_legend_resort_cities': 'Resort cities',
    'admin_dashboard_legend_users': 'Users',
    'admin_dashboard_workflow_title': 'Setup Workflow',
    'admin_dashboard_workflow_step1_body':
        'Create each destination city (e.g. Mombasa, Nairobi).',
    'admin_dashboard_workflow_step2_body':
        'Create global categories (Accommodation, Dining, Wellness…).',
    'admin_dashboard_workflow_step3_body':
        'Add each place via the 11-step wizard.',
    'admin_dashboard_workflow_step4_body':
        'Publish articles, guides, and city highlights.',
    'admin_dashboard_workflow_step5_body':
        'Review and approve admin role applications from users.',
    'admin_dashboard_workflow_step6_body':
        'Define which payment options places can accept (M-Pesa, Card, Cash…).',
    'admin_dashboard_workflow_step7_body':
        'Review and confirm booking requests submitted by tourists.',

    // Admin Blog List
    'admin_blog_error_load_post_prefix': 'Could not load post:',
    'admin_blog_loading_post': 'Loading post…',
    'admin_blog_delete_dialog_title': 'Delete Post',
    'admin_blog_delete_dialog_body_prefix': 'How would you like to remove',
    'admin_blog_delete_dialog_body_suffix': '?',
    'admin_blog_archive': 'Archive',
    'admin_blog_permanent': 'Permanent',
    'admin_blog_permanent_delete_title': 'Permanent Delete',
    'admin_blog_permanent_delete_body_prefix': 'This action is',
    'admin_blog_permanent_delete_body_irreversible': 'IRREVERSIBLE',
    'admin_blog_permanent_delete_body_suffix':
        '. The post, all its comments, likes, and view history will be '
            'permanently erased from the database.\n\nAre you absolutely sure?',
    'admin_blog_yes_delete_permanently': 'Yes, Delete Permanently',
    'admin_blog_snack_permanently_deleted_suffix': 'permanently deleted.',
    'admin_blog_snack_archived_suffix': 'archived.',
    'admin_blog_error_delete_prefix': 'Delete failed:',
    'admin_blog_search_hint': 'Search posts… (server-side, all pages)',
    'admin_blog_new_post': 'New Post',
    'admin_blog_filter_all': 'All Posts',
    'admin_blog_filter_published': 'Published',
    'admin_blog_filter_drafts': 'Drafts',
    'admin_blog_filter_scheduled': 'Scheduled',
    'admin_blog_filter_my_drafts': 'My Drafts',
    'admin_blog_untitled': 'Untitled',
    'admin_blog_min_read_suffix': 'm read',
    'admin_blog_comments': 'Comments',
    'admin_blog_promote': 'Promote',
    'admin_blog_edit': 'Edit',
    'admin_blog_promote_dialog_title': 'Promote Post',
    'admin_blog_featured': 'Featured',
    'admin_blog_featured_sub': 'Surfaces first in the blog section',
    'admin_blog_paid_advert': 'Paid Advert',
    'admin_blog_paid_advert_sub': 'Shows a "Sponsored by" badge',
    'admin_blog_sponsor_name': 'Sponsor Name',
    'admin_blog_related_links': 'Related Links',
    'admin_blog_link_a_place': 'Link a Place',
    'admin_blog_saving': 'Saving…',
    'admin_blog_reply_hint': 'Write a reply…',
    'admin_blog_comment_hint': 'Add a comment…',
    'admin_blog_no_comments_yet': 'No comments yet.',
    'admin_blog_be_first_comment': 'Be the first to comment below.',
    'admin_blog_anonymous': 'Anonymous',
    'admin_blog_failed_post_comment': 'Failed to post comment',
    'admin_blog_reply': 'Reply',
    'admin_blog_replying_to_prefix': 'Replying to',
    'admin_blog_empty_no_posts': 'No blog posts yet',
    'admin_blog_empty_no_drafts': 'No drafts yet',
    'admin_blog_empty_hit_new_post':
        'Hit "New Post" to write your first article.',
    'admin_blog_empty_try_filter': 'Try switching the filter above.',
    'admin_blog_write_first_post': 'Write First Post',

    // Admin Resort Cities
    'admin_resort_title': 'Resort Cities',
    'admin_resort_loading': 'Loading…',
    'admin_resort_city_singular': 'city',
    'admin_resort_city_plural': 'cities',
    'admin_resort_total_suffix': 'total',
    'admin_resort_filtered_suffix': 'filtered',
    'admin_resort_add_city': 'Add Resort City',
    'admin_resort_search_hint_narrow': 'Search cities…',
    'admin_resort_search_hint_wide': 'Search by name, country, region or slug…',
    'admin_resort_filter_all': 'All',
    'admin_resort_filter_active': 'Active',
    'admin_resort_filter_inactive': 'Inactive',
    'admin_resort_refresh_tooltip': 'Refresh',
    'admin_resort_failed_load': 'Failed to load cities',
    'admin_resort_empty_title': 'No Resort Cities Yet',
    'admin_resort_empty_body':
        'Add your first resort city to make it available in the app.',
    'admin_resort_add_first_city': 'Add First City',
    'admin_resort_no_match_prefix': 'No cities match',
    'admin_resort_delete_title_prefix': 'Delete',
    'admin_resort_delete_body':
        'This will permanently remove the city and all its places. This '
            'action cannot be undone.',
    'admin_resort_snack_deleted_prefix': 'Deleted',
    'admin_resort_snack_delete_failed': 'Failed to delete city',
    'admin_resort_snack_now_prefix': 'is now',
    'admin_resort_snack_created_suffix': 'Created',
    'admin_resort_snack_updated_suffix': 'Updated',
    'admin_resort_pop_view_places': 'View Places',
    'admin_resort_pop_view_by_category': 'View by Category',
    'admin_resort_pop_edit_city': 'Edit City',
    'admin_resort_pop_set_inactive': 'Set Inactive',
    'admin_resort_pop_set_active': 'Set Active',
    'admin_resort_pop_unfeature_city': 'Unfeature City',
    'admin_resort_pop_feature_city': 'Feature City',
    'admin_resort_pop_set_sort_order': 'Set Sort Order',
    'admin_resort_set_sort_order_title': 'Set Sort Order',
    'admin_resort_set_sort_order_hint': 'Lower numbers show first',
    'admin_resort_edit_city_title': 'Edit Resort City',
    'admin_resort_add_city_title': 'Add Resort City',
    'admin_resort_id_prefix': 'ID:',
    'admin_resort_section_basic_info': 'Basic Information',
    'admin_resort_section_description': 'Description',
    'admin_resort_section_media': 'Media',
    'admin_resort_section_location': 'Location Coordinates',
    'admin_resort_section_visibility': 'Visibility',
    'admin_resort_field_city_name': 'City Name',
    'admin_resort_field_city_name_hint': 'e.g. Nairobi',
    'admin_resort_error_city_name_required': 'City name is required',
    'admin_resort_field_country': 'Country',
    'admin_resort_field_country_hint': 'e.g. Kenya',
    'admin_resort_field_region': 'Region / County',
    'admin_resort_field_region_hint': 'e.g. Coast',
    'admin_resort_error_required': 'Required',
    'admin_resort_field_slug': 'Slug',
    'admin_resort_field_slug_hint': 'e.g. nairobi  (auto-generated from name)',
    'admin_resort_field_slug_helper':
        'URL-safe identifier — lowercase, hyphens only.',
    'admin_resort_error_slug_required': 'Slug is required',
    'admin_resort_error_slug_format':
        'Only lowercase letters, digits and hyphens',
    'admin_resort_field_description': 'Description',
    'admin_resort_field_description_hint':
        'A short description of the city shown to users',
    'admin_resort_error_description_required': 'Description is required',
    'admin_resort_cover_image_label': 'Cover Image',
    'admin_resort_select_upload_image': 'Select & Upload Image',
    'admin_resort_change_image': 'Change Image',
    'admin_resort_uploading_prefix': 'Uploading…',
    'admin_resort_field_cover_image_url': 'Cover Image URL',
    'admin_resort_field_cover_image_url_hint':
        'Auto-filled after upload — or paste a URL directly',
    'admin_resort_cover_image_uploading_helper':
        'Uploading image to Firebase Storage…',
    'admin_resort_cover_image_helper':
        'Select an image above to upload, or enter a URL manually.',
    'admin_resort_error_url_format': 'Must be a full URL starting with http',
    'admin_resort_pick_on_map': 'Pick on Map',
    'admin_resort_map_hint': 'Search by name, tap the map, or drag the pin — '
        'or enter coordinates manually below.',
    'admin_resort_field_latitude': 'Latitude',
    'admin_resort_field_latitude_hint': 'e.g. -1.2921',
    'admin_resort_field_longitude': 'Longitude',
    'admin_resort_field_longitude_hint': 'e.g. 36.8219',
    'admin_resort_error_must_be_number': 'Must be a number',
    'admin_resort_error_lat_range': 'Between -90 and 90',
    'admin_resort_error_lng_range': 'Between -180 and 180',
    'admin_resort_error_valid_number': 'Must be a valid number',
    'admin_resort_active_visible': 'Active / Visible',
    'admin_resort_visible_desc':
        'City is published and visible to browsing users.',
    'admin_resort_hidden_desc': 'City is hidden from browsing users.',
    'admin_resort_save_changes': 'Save Changes',
    'admin_resort_create_city': 'Create City',
    'admin_resort_error_storage_unavailable':
        'Firebase Storage is unavailable. Check Firebase initialisation.',
    'admin_resort_error_image_upload_prefix': 'Image upload failed:',
    'admin_resort_error_unexpected': 'An unexpected error occurred.',
    'admin_resort_active_badge': 'Active',
    'admin_resort_inactive_badge': 'Inactive',
    'admin_resort_stat_places': 'Places',
    'admin_resort_stat_events': 'Events',
    'admin_resort_stat_cats': 'Cats',

    // Admin Place Wizard — navigation chrome (shown on every step)
    'admin_wizard_step_draft': 'Draft',
    'admin_wizard_step_location': 'Location',
    'admin_wizard_step_contact': 'Contact',
    'admin_wizard_step_media': 'Media',
    'admin_wizard_step_booking': 'Booking',
    'admin_wizard_step_categories': 'Categories',
    'admin_wizard_step_validate': 'Validate',
    'admin_wizard_step_submit': 'Submit',
    'admin_wizard_step_basic_info_full': 'Basic Info',
    'admin_wizard_step_info_short': 'Info',
    'admin_wizard_step_attributes_full': 'Attributes',
    'admin_wizard_step_attrs_short': 'Attrs',
    'admin_wizard_step_nested_data_full': 'Nested Data',
    'admin_wizard_step_data_short': 'Data',
    'admin_wizard_title_draft': 'Create Draft',
    'admin_wizard_sub_draft': 'Set the name, city, and primary category',
    'admin_wizard_title_basic_info': 'Basic Information',
    'admin_wizard_sub_basic_info': 'Add a description and area information',
    'admin_wizard_sub_location': 'Set address and GPS coordinates',
    'admin_wizard_title_contact': 'Contact Details',
    'admin_wizard_sub_contact': 'Add phone, email, and website',
    'admin_wizard_sub_attributes': 'Add category-specific details',
    'admin_wizard_title_media': 'Media & Images',
    'admin_wizard_sub_media': 'Add cover photo and gallery images',
    'admin_wizard_title_booking': 'Booking & Pricing',
    'admin_wizard_sub_booking': 'Configure pricing and booking options',
    'admin_wizard_title_categories': 'Link Categories',
    'admin_wizard_sub_categories': 'Select all applicable service categories',
    'admin_wizard_sub_validate': 'Check required fields are complete',
    'admin_wizard_title_submit_activate': 'Submit & Activate',
    'admin_wizard_sub_submit': 'Make this place live in the app',
    'admin_wizard_nested_sub_prefix': 'Add',
    'admin_wizard_nested_sub_suffix': 'for this place (optional)',
    'admin_wizard_btn_back': 'Back',
    'admin_wizard_btn_save_exit': 'Save & Exit',
    'admin_wizard_btn_next': 'Next',
    'admin_wizard_btn_save_continue': 'Save & Continue',
    'admin_wizard_btn_submit_activate': 'Submit & Activate',
    'admin_wizard_saving': 'Saving…',
    'admin_wizard_next_tooltip': 'Move to next step without saving',
    'admin_wizard_step_of_prefix': 'Step',
    'admin_wizard_step_of_middle': 'of',
    'admin_wizard_tap_segment': 'Tap a segment to jump',
    'admin_wizard_saved_legend': 'Saved',
    'admin_wizard_needs_attention': 'Needs attention',
    'admin_wizard_incomplete_prefix': 'Incomplete:',
    // Step 0 — Draft
    'admin_wizard_error_name_required': 'Name is required',
    'admin_wizard_error_select_city': 'Select a resort city',
    'admin_wizard_error_select_category': 'Select a primary category',
    'admin_wizard_field_place_name': 'Place Name',
    'admin_wizard_field_place_name_hint': 'e.g. Serena Beach Resort & Spa',
    'admin_wizard_field_resort_city': 'Resort City',
    'admin_wizard_field_resort_city_hint': 'Select the city this place is in',
    'admin_wizard_field_primary_category': 'Primary Category',
    'admin_wizard_field_primary_category_desc':
        'Used to determine what kind of nested data this place supports.',
    'admin_wizard_field_primary_category_hint': 'Select primary category',
    // Step 10 — Submit
    'admin_wizard_submit_tap_notice':
        'Tapping "Submit & Activate" will change this place from PENDING to '
            'ACTIVE, making it visible in the user-facing app.',
    'admin_wizard_summary_city_set': 'City set',
    'admin_wizard_summary_categories_suffix': 'categories',
    'admin_wizard_summary_has_media': 'Has media',
    'admin_wizard_summary_no_media': 'No media',
    // Common form actions used across the wizard
    'admin_wizard_add_image_url': 'Add Image URL',
    'admin_wizard_remove': 'Remove',
    'admin_wizard_select_upload_image': 'Select & Upload Image',
    'admin_wizard_change_image': 'Change Image',
    // Step 2 — Basic Info
    'admin_wizard_field_short_desc': 'Short Description',
    'admin_wizard_field_short_desc_hint':
        'One sentence summary (max 300 chars)',
    'admin_wizard_field_full_desc': 'Full Description',
    'admin_wizard_field_full_desc_hint':
        'Detailed description of this place (min 100 chars)',
    'admin_wizard_field_area': 'Area / Neighbourhood',
    'admin_wizard_field_area_hint': 'e.g. Shanzu, Westlands',
    // Step 3 — Location
    'admin_wizard_location_selected': 'Location Selected',
    'admin_wizard_pick_on_map': 'Pick on Map',
    'admin_wizard_tap_adjust_pin': 'Tap to adjust the pin position',
    'admin_wizard_open_map_search':
        'Open interactive map to search and pin a location',
    'admin_wizard_adjust_on_map': 'Adjust on Map',
    'admin_wizard_open_map_picker': 'Open Map Picker',
    'admin_wizard_or_enter_manually': 'or enter manually',
    'admin_wizard_field_full_address': 'Full Address',
    'admin_wizard_field_full_address_hint': 'e.g. Shanzu Beach Road, Mombasa',
    'admin_wizard_lat_hint': 'e.g. -3.9875',
    'admin_wizard_lng_hint': 'e.g. 39.7392',
    'admin_wizard_map_tip': 'Tip: Use the Map Picker for precise coordinates. '
        'You can search by place name, tap on the map, or drag the pin.',
    // Step 4 — Contact
    'admin_wizard_field_phone': 'Phone Number',
    'admin_wizard_field_email': 'Email Address',
    'admin_wizard_field_website': 'Website URL',
    // Step 9 — Categories
    'admin_wizard_categories_info':
        'Select every category this place offers. A hotel that offers '
            'accommodation AND dining AND wellness should have all three '
            'selected.',
    'admin_wizard_category_selected_singular': 'category selected',
    'admin_wizard_category_selected_plural': 'categories selected',

    // Place Admin Panel
    'place_admin_panel_back_to_app': 'Back to App',
    'place_admin_panel_tab_overview': 'Overview',
    'place_admin_panel_tab_bookings': 'Bookings',
    'place_admin_panel_tab_details': 'Place Details',
    'place_admin_panel_tab_payments': 'Payment Methods',
    'place_admin_panel_tab_queries': 'Queries',
    'place_admin_panel_bookings_overview': 'Bookings Overview',
    'place_admin_panel_stat_total': 'Total',
    'place_admin_panel_stat_pending': 'Pending',
    'place_admin_panel_stat_confirmed': 'Confirmed',
    'place_admin_panel_stat_completed': 'Completed',
    'place_admin_panel_stat_cancelled': 'Cancelled',
    'place_admin_panel_stat_paid_mpesa': 'Paid via M-Pesa',
    'place_admin_panel_stat_revenue': 'Estimated Revenue',
    'place_admin_panel_edit_title': 'Edit',
    'place_admin_panel_edit_body':
        'Update photos, description, pricing, booking settings and everything else about this place.',
    'place_admin_panel_edit_load_error': 'Could not load place details',
    'place_admin_panel_loading': 'Loading…',
    'place_admin_panel_edit_button': 'Edit Place Details',
    'place_admin_panel_payments_title': 'Accepted Payment Methods',
    'place_admin_panel_payments_subtitle':
        'Choose which of the platform\'s configured payment methods this place accepts.',
    'place_admin_panel_payments_empty_title': 'No payment methods configured',
    'place_admin_panel_payments_empty_body':
        'Ask a MainAdmin to add payment methods in the system-wide catalogue first.',
    'place_admin_panel_payments_updated': 'Payment methods updated.',
    'place_admin_panel_saving': 'Saving…',
    'place_admin_panel_save': 'Save',
    'place_admin_panel_queries_empty_title': 'No questions yet',
    'place_admin_panel_queries_empty_body':
        'Tourist questions about this place will appear here.',
    'place_admin_panel_status_answered': 'ANSWERED',
    'place_admin_panel_status_open': 'OPEN',
    'place_admin_panel_your_reply_prefix': 'Your reply',
    'place_admin_panel_reply_hint': 'Type your reply…',
    'place_admin_panel_reply_button': 'Reply',
    'place_admin_panel_send_reply': 'Send Reply',
    'place_admin_panel_sending': 'Sending…',

    // Place details — room detail chips
    'place_details_room_balcony': 'Balcony',
    'place_details_room_kitchen': 'Kitchen',
    'place_details_room_living_room': 'Living Room',
    'place_details_room_more_amenities': 'more',

    // Place details — menu item detail chips
    'place_details_menu_signature': 'Signature',
    'place_details_menu_chef_special': "Chef's Special",
  };

  static const Map<String, String> _sw = {
    // Settings section
    'settings_title': 'Mipangilio',
    'settings_appearance': 'MUONEKANO',
    'settings_theme': 'Mandhari',
    'settings_theme_dark': 'Giza',
    'settings_theme_light': 'Mwanga',
    'settings_theme_system': 'Chaguo-msingi la Mfumo',
    'settings_font': 'Aina ya Herufi',
    'settings_font_subtitle':
        'Chagua jinsi maandishi yanavyoonekana katika programu',
    'settings_language': 'LUGHA',
    'settings_language_label': 'Lugha ya Programu',
    'settings_language_english': 'Kiingereza',
    'settings_language_swahili': 'Kiswahili',

    // Account screen
    'my_account': 'Akaunti Yangu',
    'account_bookings_section': 'UHIFADHI',
    'account_my_bookings': 'Uhifadhi Wangu',
    'account_my_bookings_sub': 'Angalia na simamia maombi yako ya uhifadhi',
    'account_my_queries': 'Maswali Yangu',
    'account_my_queries_sub': 'Maswali uliyouliza kuhusu maeneo',
    'account_my_favorites': 'Vipendwa Vyangu',
    'account_my_favorites_sub': 'Maeneo uliyoyahifadhi',
    'account_place_admin_panel': 'Dashibodi ya Msimamizi wa Eneo',
    'account_place_admin_panel_sub':
        'Simamia uhifadhi, maswali na maelezo ya eneo lako',
    'account_admin_console': 'Dashibodi ya Msimamizi',
    'account_admin_console_sub':
        'Usimamizi kamili wa mfumo — maeneo, uhifadhi, ripoti',
    'account_security_section': 'USALAMA',
    'account_phone_mfa': 'Uthibitisho wa Hatua Mbili kwa Simu',
    'account_phone_mfa_enabled_sub':
        'Imewashwa — nambari ya SMS inahitajika kila unapoingia',
    'account_phone_mfa_disabled_sub':
        'Imezimwa — huongeza hatua ya uthibitisho wa SMS wakati wa kuingia',
    'account_admin_access_section': 'UFIKIAJI WA USIMAMIZI',
    'account_sign_out': 'Toka Kwenye Akaunti',

    // Auth screen
    'auth_tab_login': 'Ingia',
    'auth_tab_signup': 'Jisajili',
    'auth_tab_magic_link': 'Kiungo Maalum',
    'auth_field_email': 'Barua Pepe',
    'auth_field_password': 'Nywila',
    'auth_field_confirm_password': 'Thibitisha Nywila',
    'auth_btn_login': 'Ingia',
    'auth_btn_create_account': 'Fungua Akaunti',
    'auth_btn_continue_google': 'Endelea na Google',
    'auth_forgot_password': 'Umesahau Nywila?',
    'auth_reset_code_link': 'Una msimbo wa kuweka upya? Weka nywila mpya →',
    'auth_err_password_required': 'Tafadhali weka nywila yako',
    'auth_err_confirm_password_required': 'Tafadhali thibitisha nywila yako',
    'auth_err_passwords_mismatch': 'Nywila hazifanani',

    // Landing page — nav / footer / section chrome
    'nav_destinations': 'Maeneo',
    'nav_blog': 'Blogu',
    'nav_search': 'Tafuta',
    'nav_sign_in': 'Ingia',
    'nav_my_account': 'Akaunti Yangu',
    'nav_careers': 'Nafasi za Kazi',
    'footer_explore': 'Chunguza',
    'footer_contact': 'Wasiliana Nasi',
    'footer_tagline':
        'Gundua maeneo mazuri zaidi ya mapumziko barani\nAfrika na uzoefu usiosahaulika.',
    'footer_made_with_love': 'Imetengenezwa kwa ❤ kwa kila msafiri',
    'section_explore_resort_cities': 'CHUNGUZA MIJI YA MAPUMZIKO',
    'section_featured': 'Yaliyoangaziwa',
    'section_open': 'Wazi',
    'section_load_more': 'Pakia Zaidi',
    'section_under_maintenance': 'Inafanyiwa Matengenezo',
    'section_admin_sign_in': 'Ingia kama Msimamizi',
    'empty_destinations_error': 'Imeshindwa kupakia maeneo',
    'empty_destinations_none': 'Hakuna maeneo bado',

    // Contact screen
    'contact_page_title': 'Wasiliana Nasi',
    'contact_success_title': 'Ujumbe umetumwa',
    'contact_success_body':
        'Asante kwa kuwasiliana nasi — tutakujibu haraka iwezekanavyo.',
    'contact_back_button': 'Rudi',
    'contact_hero_heading': 'Wasiliana Nasi',
    'contact_hero_body':
        'Maswali kuhusu uhifadhi, eneo unalotaka kuongezwa, au maoni tu — '
            'tutumie ujumbe nasi tutakujibu kwa barua pepe.',
    'contact_field_name': 'Jina Lako',
    'contact_error_name_required': 'Weka jina lako',
    'contact_field_email': 'Barua Pepe Yako',
    'contact_error_email_required': 'Weka barua pepe yako',
    'contact_error_email_invalid': 'Weka barua pepe sahihi',
    'contact_field_message': 'Ujumbe',
    'contact_error_message_required': 'Weka ujumbe',
    'contact_send_button': 'Tuma Ujumbe',
    'contact_email_directly_prefix': 'Au tutumie barua pepe moja kwa moja kwa',
    'contact_error_send_failed':
        'Imeshindwa kutuma ujumbe wako. Tafadhali jaribu tena.',
    'contact_error_email_app': 'Imeshindwa kufungua programu ya barua pepe.',

    // About screen
    'about_page_title': 'Kuhusu Sisi',

    // Careers screen
    'careers_page_title': 'Nafasi za Kazi',
    'careers_not_hiring_heading': 'Kwa sasa hatuna nafasi za kazi',
    'careers_not_hiring_body':
        'Lakini daima tunafurahi kusikia kutoka kwa watu wanaojali kuhusu '
            'kujenga jukwaa bora la usafiri. Tutumie ujumbe na tuambie '
            'ungependa kufanya kazi gani — tunahifadhi kila ujumbe kwa '
            'ajili ya wakati nafasi itakapopatikana.',

    // Static info screen (Privacy Policy / Terms of Service / Cookie Policy)
    'static_info_last_updated_prefix': 'Ilisasishwa mara ya mwisho:',

    // Shared chrome — reused across resort city / category / place screens
    'common_tap_to_retry': 'Gusa kujaribu tena',
    'nav_get_started': 'Anza',
    'footer_about': 'Kuhusu',
    'footer_privacy': 'Faragha',
    'footer_terms': 'Masharti',

    // Resort city screen
    'resort_city_footer_copyright':
        '© 2026 Palmnazi Resort Cities. Haki zote zimehifadhiwa.',
    'resort_city_explore_pill': 'Chunguza',

    // Shared dialog chrome
    'common_cancel': 'Ghairi',
    'common_send': 'Tuma',

    // Place details screen
    'place_details_dialog_signin_title': 'Unahitaji kuingia',
    'place_details_dialog_signin_favorites_body':
        'Unahitaji akaunti kuhifadhi vipendwa. Ingia (au fungua akaunti), kisha rudi kwenye eneo hili kuendelea.',
    'place_details_dialog_signin_booking_body':
        'Unahitaji akaunti kuomba uhifadhi. Ingia (au fungua akaunti), kisha rudi kwenye eneo hili kuendelea.',
    'place_details_dialog_signin_question_body':
        'Unahitaji akaunti kuuliza swali. Ingia (au fungua akaunti), kisha rudi kwenye eneo hili kuendelea.',
    'place_details_ask_question_hint': 'Ungependa kujua nini?',
    'place_details_question_sent': 'Swali lako limetumwa.',
    'place_details_loading_full_details': 'Inapakia maelezo kamili…',
    'place_details_error_load_details':
        'Imeshindwa kupakia maelezo kamili. Gusa kujaribu tena.',
    'place_details_quick_action_call': 'Piga Simu',
    'place_details_quick_action_directions': 'Mwelekeo',
    'place_details_quick_action_website': 'Tovuti',
    'place_details_quick_action_share': 'Shiriki',
    'place_details_error_dialer': 'Imeshindwa kufungua simu.',
    'place_details_error_maps': 'Imeshindwa kufungua ramani.',
    'place_details_error_website_invalid':
        'Anwani ya tovuti hii haionekani sahihi.',
    'place_details_error_website': 'Imeshindwa kufungua tovuti.',
    'place_details_error_share': 'Imeshindwa kufungua kishiriki.',
    'place_details_error_favorites':
        'Imeshindwa kusasisha vipendwa. Tafadhali jaribu tena.',
    'place_details_section_about': 'Kuhusu',
    'place_details_section_gallery': 'Picha',
    'place_details_section_features': 'Vipengele na Huduma',
    'place_details_section_artifacts': 'Mabaki',
    'place_details_section_payment_methods': 'Njia za Malipo Zinazokubaliwa',
    'place_details_section_contact': 'Maelezo ya Mawasiliano',
    'place_details_contact_address': 'Anwani',
    'place_details_contact_area': 'Eneo',
    'place_details_contact_phone': 'Simu',
    'place_details_contact_email': 'Barua Pepe',
    'place_details_section_booking_pricing': 'Uhifadhi na Bei',
    'place_details_info_price': 'Bei',
    'place_details_info_advance_notice': 'Taarifa ya awali',
    'place_details_info_min_stay': 'Ukaaji wa chini',
    'place_details_info_max_stay': 'Ukaaji wa juu',
    'place_details_info_cancellation': 'Ughairi',
    'place_details_button_book_now': 'Hifadhi Sasa',
    'place_details_button_enquire': 'Uliza',
    'place_details_tooltip_ask_question': 'Uliza Swali',
    'place_details_tooltip_remove_favorite': 'Ondoa kwenye vipendwa',
    'place_details_tooltip_add_favorite': 'Ongeza kwenye vipendwa',
    'place_details_bookable_badge': 'Inaweza Kuhifadhiwa',
    'place_details_untitled': 'Haina Jina',
    'place_details_search_prefix': 'Tafuta',

    // Category screen
    'category_subcat_all': 'Zote',

    // Shared chrome
    'common_done': 'Imekamilika',

    // Booking screen
    'booking_error_signin': 'Lazima uingie ili kuhifadhi.',
    'booking_error_select_checkout': 'Chagua tarehe ya kuondoka.',
    'booking_error_conflict_suffix':
        'tayari imehifadhiwa kwa tarehe hiyo. Chagua tarehe au chaguo lingine.',
    'booking_success_title': 'Ombi la uhifadhi limetumwa',
    'booking_success_prefix': 'Ombi lako la uhifadhi la',
    'booking_success_suffix':
        'limetumwa. Utaona hali yake chini ya Uhifadhi Wangu.',
    'booking_success_reference_label': 'NAMBA YA KUMBUKUMBU',
    'booking_success_copy_reference': 'Nakili namba kamili',
    'booking_success_reference_copied': 'Namba ya kumbukumbu imenakiliwa.',
    'booking_success_reference_hint':
        'Onyesha namba hii dawati la mbele — wafanyakazi wanaweza kuitumia kuthibitisha ulichohifadhi hasa.',
    'booking_button_view_my_bookings': 'Angalia Uhifadhi Wangu',
    'booking_appbar_prefix': 'Hifadhi',
    'booking_select_prefix': 'Chagua',
    'booking_select_option': 'Chagua chaguo',
    'booking_section_checkin_checkout': 'Kuingia / Kuondoka',
    'booking_section_preferred_date': 'Tarehe Unayopendelea',
    'booking_label_checkin': 'Kuingia',
    'booking_label_checkout': 'Kuondoka',
    'booking_label_date': 'Tarehe',
    'booking_section_guests': 'Idadi ya Wageni',
    'booking_estimated_total': 'Jumla Inayokadiriwa',
    'booking_estimate_disclaimer':
        'Makadirio tu — kiasi cha mwisho kinathibitishwa na eneo husika.',
    'booking_section_payment_method': 'Njia ya Malipo',
    'booking_section_special_requests': 'Maombi Maalum (hiari)',
    'booking_notes_hint': 'Mahitaji yoyote maalum…',
    'booking_button_request': 'Omba Uhifadhi',
    'booking_option_prefix': 'Chaguo',
    'booking_label_select': 'Chagua',

    // Shared chrome
    'common_ok': 'Sawa',

    // My Bookings screen
    'my_bookings_signin_required': 'Ingia ili kuona uhifadhi wako.',
    'my_bookings_error_load_prefix': 'Imeshindwa kupakia uhifadhi:',
    'my_bookings_empty':
        'Hakuna uhifadhi bado. Tafuta eneo unalolipenda na ugonge "Hifadhi Sasa".',
    'my_bookings_reference_prefix': 'Namba',
    'my_bookings_dialog_cancel_unavailable_title': 'Ughairi haupatikani',
    'my_bookings_dialog_cancel_title': 'Ghairi uhifadhi?',
    'my_bookings_dialog_cancel_body': 'Hatua hii haiwezi kutenduliwa.',
    'my_bookings_button_keep': 'Acha ilivyo',
    'my_bookings_button_cancel_booking': 'Ghairi uhifadhi',
    'my_bookings_mpesa_receipt_prefix': 'Imelipwa kwa M-Pesa — risiti',
    'my_bookings_estimate_suffix': '(makadirio)',

    // My Favorites screen
    'my_favorites_signin_required': 'Ingia ili kuona vipendwa vyako.',
    'my_favorites_error_load_prefix': 'Imeshindwa kupakia vipendwa:',
    'my_favorites_empty':
        'Hakuna vipendwa bado. Gusa aikoni ya moyo kwenye orodha yoyote ili kuihifadhi hapa.',
    'my_favorites_place_unavailable': 'Eneo hili halipatikani tena.',

    // My Queries screen
    'my_queries_signin_required': 'Ingia ili kuona maswali yako.',
    'my_queries_error_load_prefix': 'Imeshindwa kupakia maswali:',
    'my_queries_empty':
        'Hakuna maswali bado. Gusa "Uliza" kwenye eneo ili kuuliza swali.',
    'my_queries_status_answered': 'IMEJIBIWA',
    'my_queries_status_pending': 'INASUBIRI',

    // Blog post detail screen
    'blog_detail_title': 'Hadithi',
    'blog_detail_not_found': 'Hadithi hii haikupatikana.',
    'blog_detail_error_post_comment':
        'Imeshindwa kuchapisha maoni yako. Tafadhali jaribu tena.',
    'blog_detail_loading': 'Inapakia…',
    'blog_detail_author_bio':
        'Anaandika hadithi za Palmnazi Resort Cities — miongozo, '
            'makala na masasisho kuhusu maeneo ya mapumziko kwenye '
            'jukwaa.',
    'blog_detail_sponsored_by_prefix': 'Imedhaminiwa na',
    'blog_detail_sponsored': 'Imedhaminiwa',
    'blog_detail_related_heading': 'Yanayohusiana na Hadithi Hii',
    'blog_detail_comments_heading': 'Maoni',
    'blog_detail_comment_hint': 'Shiriki mawazo yako…',
    'blog_detail_no_comments': 'Kuwa wa kwanza kutoa maoni.',
    'blog_detail_no_content': 'Hadithi hii haina maudhui bado.',

    // Payment simulation screen
    'payment_sim_appbar_title_prefix': 'Lipa kwa',
    'payment_sim_stage_sending': 'Inatuma ombi la STK kwenye simu yako…',
    'payment_sim_error_invalid_phone': 'Weka nambari sahihi ya Safaricom.',
    'payment_sim_mpesa_not_completed': 'Ombi la M-Pesa halikukamilika.',
    'payment_sim_btn_send_stk': 'Tuma STK Push',
    'payment_sim_btn_pay_now': 'Lipa Sasa',
    'payment_sim_btn_continue_paypal': 'Endelea na PayPal',
    'payment_sim_btn_made_transfer': 'Nimeshafanya Uhamisho',
    'payment_sim_btn_confirm_cash': 'Thibitisha — Lipa Ukiwasili',
    'payment_sim_btn_confirm_payment': 'Thibitisha Malipo',
    'payment_sim_note_sandbox_mode':
        'Hali ya majaribio — hii inatuma ombi halisi la Daraja STK push, lakini mfumo wa majaribio wa Safaricom unalitatua kiotomatiki. Hakuna simu wala pesa halisi zinazohusika.',
    'payment_sim_label_mpesa_phone': 'Nambari ya Simu ya M-Pesa',
    'payment_sim_hint_phone': '07XX XXX XXX',
    'payment_sim_note_stk_prefix':
        'Ombi la STK litatumwa kwenye nambari hii kwa',
    'payment_sim_note_stk_suffix':
        '(nambari fupi ya majaribio inatumika chinichini).',
    'payment_sim_paybill_label': 'Paybill',
    'payment_sim_configured_paybill': 'paybill iliyowekwa',
    'payment_sim_label_card_details': 'Maelezo ya Kadi',
    'payment_sim_hint_card_number': 'Nambari ya Kadi',
    'payment_sim_hint_expiry': 'MM/YY',
    'payment_sim_hint_cvv': 'CVV',
    'payment_sim_note_card_demo':
        'Malipo ya kadi bado hayajashughulikiwa na lango halisi — huu ni mfumo wa maonyesho tu. Maelezo ya kadi hayatumwi popote.',
    'payment_sim_note_paypal_prefix':
        'Ungeelekezwa kwa PayPal kuingia na kuidhinisha malipo kwa',
    'payment_sim_configured_merchant': 'akaunti ya mfanyabiashara iliyowekwa',
    'payment_sim_label_transfer_instructions': 'Maelekezo ya Uhamisho',
    'payment_sim_field_bank': 'Benki',
    'payment_sim_field_account_number': 'Nambari ya Akaunti',
    'payment_sim_field_account_name': 'Jina la Akaunti',
    'payment_sim_not_configured': 'Bado haijawekwa',
    'payment_sim_note_cash_prefix': 'Lipa kwa fedha taslimu moja kwa moja',
    'payment_sim_note_cash_suffix': 'ukiwasili.',
    'payment_sim_note_other_prefix': 'Malipo yatapangwa moja kwa moja na',
    'payment_sim_processing_card': 'Inashughulikia malipo ya kadi…',
    'payment_sim_processing_paypal': 'Inaelekeza kwa PayPal…',
    'payment_sim_processing_bank': 'Inarekodi uhamisho wako…',
    'payment_sim_processing_cash': 'Inathibitisha mpango…',
    'payment_sim_processing_default': 'Inashughulikia…',
    'payment_sim_waiting_instructions':
        'Angalia simu yako na uweke PIN yako ya M-Pesa kukamilisha malipo haya.',
    'payment_sim_sent_to_prefix': 'Imetumwa kwa',
    'payment_sim_btn_check_now': 'Nimeshaweka PIN yangu — angalia sasa',
    'payment_sim_btn_cancel_back': 'Ghairi na urudi nyuma',
    'payment_sim_success_title': 'Malipo ya M-Pesa yamepokelewa',
    'payment_sim_receipt_prefix': 'Risiti:',
    'payment_sim_sandbox_transaction_note':
        'Muamala wa majaribio — huu ulifanyika kwenye mazingira ya majaribio ya Daraja ya Safaricom. Hakuna pesa halisi zilizohamishwa.',
    'payment_sim_btn_continue': 'Endelea',
    'payment_sim_failed_title': 'Malipo hayakukamilika',
    'payment_sim_failed_default_message':
        'Ombi la M-Pesa lilighairiwa au muda uliisha.',
    'payment_sim_btn_try_again': 'Jaribu Tena',
    'payment_sim_btn_back_out': 'Rudi nyuma kutoka kwenye uhifadhi',
    'payment_sim_done_title': 'Mchakato wa malipo umekamilika (majaribio)',
    'payment_sim_demo_note':
        'Huu ni onyesho tu. Hakuna pesa halisi zilizohamishwa na hakuna lango halisi la malipo lililowasiliana.',
    'payment_sim_completion_card_prefix':
        'Katika muunganisho halisi, kadi hii ingetozwa',
    'payment_sim_completion_card_via': 'kupitia',
    'payment_sim_configured_card_gateway': 'lango la kadi lililowekwa',
    'payment_sim_card_gateway_not_configured':
        'lango la kadi (bado halijawekwa)',
    'payment_sim_completion_paypal_prefix':
        'Katika muunganisho halisi, ungeidhinisha malipo ya',
    'payment_sim_completion_paypal_middle': 'kwenye PayPal kwa',
    'payment_sim_completion_bank_prefix':
        'Uhifadhi wako utashikiliwa ukisubiri uthibitisho wa mkono kwamba',
    'payment_sim_completion_bank_suffix':
        'ulihamishwa kwenye akaunti iliyoonyeshwa.',
    'payment_sim_completion_cash_prefix':
        'Uhifadhi wako umerekodiwa — tafadhali lipa',
    'payment_sim_completion_cash_middle': 'kwa fedha taslimu',
    'payment_sim_completion_default_prefix':
        'Uhifadhi wako umerekodiwa — mipango ya malipo ya',
    'payment_sim_completion_default_middle': 'itathibitishwa moja kwa moja na',

    // Reset password screen
    'reset_password_loading_message': 'Inaweka upya nywila yako…',
    'reset_password_title': 'Tengeneza Nywila Mpya',
    'reset_password_subtitle':
        'Weka msimbo wa kuweka upya kutoka barua pepe yako\nna uchague nywila mpya imara.',
    'reset_password_label_reset_code': 'Msimbo wa Kuweka Upya',
    'reset_password_hint_reset_code': 'Bandika msimbo wako wa kuweka upya',
    'reset_password_err_code_required':
        'Tafadhali weka msimbo wa kuweka upya kutoka barua pepe yako',
    'reset_password_err_code_short':
        'Msimbo wa kuweka upya unaonekana mfupi sana — tafadhali angalia barua pepe yako',
    'reset_password_hint_box_text':
        'Fungua barua pepe ya kuweka upya tuliyokutumia na unakili msimbo '
            'kamili wa kuweka upya, kisha ubandike kwenye sehemu iliyo juu.',
    'reset_password_label_new_password': 'Nywila Mpya',
    'reset_password_hint_new_password': 'Weka nywila mpya',
    'reset_password_err_password_required': 'Tafadhali weka nywila mpya',
    'reset_password_err_password_length':
        'Nywila lazima iwe na herufi 8 au zaidi',
    'reset_password_hint_confirm_password': 'Weka tena nywila mpya',
    'reset_password_btn_submit': 'Weka Upya Nywila',
    'reset_password_back_to_login': 'Rudi Kuingia',
    'reset_password_success_title': 'Nywila Imewekwa Upya!',
    'reset_password_success_body': 'Nywila yako imesasishwa kwa mafanikio.\n'
        'Sasa unaweza kuingia kwa nywila yako mpya.',
    'reset_password_strength_weak': 'Dhaifu',
    'reset_password_strength_fair': 'Wastani',
    'reset_password_strength_good': 'Nzuri',
    'reset_password_strength_strong': 'Imara',
    'reset_password_strength_prefix': 'Nguvu:',

    // widgets/parallax_header
    'widget_parallax_header_brand': 'PALMNAZI',
    'widget_parallax_header_subtitle': 'MIJI YA MAPUMZIKO',
    'widget_parallax_header_tagline':
        'Gundua Maeneo Bora Zaidi ya Mapumziko nchini Kenya',
    'widget_parallax_header_cta': 'Gundua Maeneo',
    'widget_parallax_header_scroll_hint': 'Tembeza chini kugundua zaidi',

    // widgets/channel_showcase
    'widget_channel_showcase_title': 'Gundua Njia Zetu',
    'widget_channel_showcase_subtitle':
        'Vinjari kategoria zetu zilizoteuliwa kwa makini ili kupata hasa unachotafuta',
    'widget_channel_showcase_tap_hint': 'Gusa kuchunguza',

    // widgets/feature_carousel
    'widget_feature_carousel_title': 'Tunachotoa',
    'widget_feature_carousel_subtitle':
        'Vinjari huduma zetu zilizoteuliwa kwa uzoefu wa kipekee wa mapumziko',
    'widget_feature_carousel_explore_cta': 'Gundua',
    'widget_feature_carousel_accommodation_title': 'Malazi ya Hali ya Juu',
    'widget_feature_carousel_accommodation_desc':
        'Furahia ukarimu wa hadhi ya kimataifa katika miji bora zaidi ya mapumziko nchini Kenya. Kutoka villa za kifahari za pwani hadi nyumba za utulivu za milimani, gundua malazi yaliyoteuliwa yanayotoa faraja ya kipekee, mandhari ya kuvutia, na huduma ya kibinafsi.',
    'widget_feature_carousel_dining_title': 'Milo Mizuri',
    'widget_feature_carousel_dining_desc':
        'Anza safari ya vyakula kupitia Kenya na mkusanyiko wetu wa mikahawa ya hadhi ya kimataifa na maeneo ya asili ya vyakula. Kutoka samaki wabichi wa baharini hadi vyakula vya asili vya Kikenya, onja milo iliyoandaliwa kwa shauku.',
    'widget_feature_carousel_events_title': 'Matukio ya Kiutamaduni',
    'widget_feature_carousel_events_desc':
        'Jiingize katika sherehe za kitamaduni zenye uchangamfu, tamasha za muziki, na mila za asili. Ungana na jamii za wenyeji, shuhudia mila za zamani, na shiriki matukio yanayounganisha watu kutoka tamaduni mbalimbali.',
    'widget_feature_carousel_shopping_title': 'Ununuzi wa Kazi za Mikono',
    'widget_feature_carousel_shopping_desc':
        'Gundua ustadi halisi wa Kikenya katika masoko ya wenyeji na maduka madogo. Pata zawadi za kipekee, vito vya mikono, nguo za asili, na sanaa ya kisasa inayosimulia hadithi yenye maana.',
    'widget_feature_carousel_adventure_title': 'Matukio na Asili',
    'widget_feature_carousel_adventure_desc':
        'Gundua mandhari ya kuvutia kutoka fukwe safi hadi milima mikubwa. Shiriki katika matukio ya safari, kupanda milima, michezo ya majini, na mikutano ya kipekee na wanyamapori kupitia utalii endelevu.',

    // widgets/stats_counter
    'widget_stats_counter_resort_cities': 'Miji ya Mapumziko',
    'widget_stats_counter_businesses': 'Biashara',
    'widget_stats_counter_happy_visitors': 'Wageni Wenye Furaha',
    'widget_stats_counter_average_rating': 'Wastani wa Ukadiriaji',

    // widgets/place_card
    'widget_place_card_reviews_suffix': 'hakiki',
    'widget_place_card_view_details': 'Tazama Maelezo',
    'widget_place_card_open': 'Wazi',
    'widget_place_card_closed': 'Imefungwa',

    // widgets/place_search_picker
    'widget_place_search_picker_title': 'Chagua Mahali',
    'widget_place_search_picker_subtitle':
        'Tafuta mahali unapoyasimamia au unayotaka kuyasimamia.',
    'widget_place_search_picker_hint': 'Tafuta kwa jina la mahali…',
    'widget_place_search_picker_prompt': 'Anza kuandika kupata mahali.',
    'widget_place_search_picker_empty':
        'Hakuna mahali yanayolingana yaliyopatikana.',

    // Shared admin widgets
    'common_retry': 'Jaribu tena',

    // Admin contact messages screen
    'admin_contact_messages_error_load_prefix': 'Imeshindwa kupakia ujumbe:',
    'admin_contact_messages_empty_title': 'Hakuna ujumbe bado',
    'admin_contact_messages_empty_body':
        'Ujumbe uliotumwa kupitia fomu ya "Wasiliana Nasi" ya ukurasa wa '
            'mwanzo utaonekana hapa.',
    'admin_contact_messages_copy_email_tooltip': 'Nakili barua pepe',
    'admin_contact_messages_email_copied': 'Barua pepe imenakiliwa',

    // Admin bookings screen
    'admin_bookings_page_title': 'Uhifadhi',
    'admin_bookings_page_subtitle':
        'Maombi yaliyotumwa na watalii kutoka kwenye kurasa za maeneo',
    'admin_bookings_empty_title': 'Hakuna uhifadhi',
    'admin_bookings_empty_body_all':
        'Uhifadhi uliotumwa na watalii utaonekana hapa.',
    'admin_bookings_empty_filtered_prefix': 'Hakuna',
    'admin_bookings_empty_filtered_suffix': 'uhifadhi.',
    'admin_bookings_guest_singular': 'mgeni',
    'admin_bookings_guest_plural': 'wageni',
    'admin_bookings_reference_prefix': 'Namba',
    'admin_bookings_cancellation_suffix': 'ughairi',
    'admin_bookings_btn_confirm': 'Thibitisha',
    'admin_bookings_btn_mark_completed': 'Weka Imekamilika',

    // Shared admin dialog chrome
    'common_delete': 'Futa',
    'common_add': 'Ongeza',
    'common_save': 'Hifadhi',

    // Admin payment methods screen
    'admin_payment_methods_add_button': 'Ongeza Njia ya Malipo',
    'admin_payment_methods_page_title': 'Njia za Malipo',
    'admin_payment_methods_page_subtitle':
        'Sanidi njia za malipo ambazo maeneo yanaweza kukubali',
    'admin_payment_methods_empty_title': 'Hakuna njia za malipo bado',
    'admin_payment_methods_empty_body':
        'Ongeza njia za malipo ambazo maeneo yanaweza kukubali, k.m. M-Pesa, Kadi, au Malipo Ukiwasili.',
    'admin_payment_methods_delete_confirm_prefix': 'Futa',
    'admin_payment_methods_delete_confirm_body':
        'Maeneo yanayokubali njia hii ya malipo hayataonyesha tena kama chaguo. Hatua hii haiwezi kutenduliwa.',
    'admin_payment_methods_edit_title': 'Hariri Njia ya Malipo',
    'admin_payment_methods_error_name_required': 'Jina linahitajika',
    'admin_payment_methods_error_save_failed_prefix': 'Imeshindwa kuhifadhi:',
    'admin_payment_methods_field_name': 'Jina',
    'admin_payment_methods_hint_name_example': 'k.m. M-Pesa',
    'admin_payment_methods_field_type': 'Aina',
    'admin_payment_methods_field_description': 'Maelezo',
    'admin_payment_methods_hint_description':
        'Kidokezo cha hiari kinachoonyeshwa kwa wasimamizi, k.m. "Paybill 123456"',
    'admin_payment_methods_field_icon': 'Aikoni (emoji)',
    'admin_payment_methods_hint_icon': 'k.m. 📱',
    'admin_payment_methods_field_sort_order': 'Mpangilio wa Mfuatano',
    'admin_payment_methods_gateway_config_title': 'Usanidi wa Lango (kiolezo)',
    'admin_payment_methods_gateway_config_note':
        'Sehemu hizi zinahifadhiwa kwa marejeleo tu — hakuna lango halisi lililounganishwa bado. Zijaze mara njia hii itakapokuwa tayari kwa muunganisho halisi.',
    'admin_payment_methods_field_active': 'Inatumika',

    // Admin audit log screen
    'admin_audit_log_csv_header_timestamp': 'Muda',
    'admin_audit_log_csv_header_admin': 'Msimamizi',
    'admin_audit_log_csv_header_action': 'Kitendo',
    'admin_audit_log_csv_header_module': 'Moduli',
    'admin_audit_log_csv_header_target': 'Lengo',
    'admin_audit_log_csv_header_details': 'Maelezo',
    'admin_audit_log_export_success_prefix': 'Imesafirisha',
    'admin_audit_log_export_success_suffix': 'safu.',
    'admin_audit_log_error_load_prefix':
        'Imeshindwa kupakia kumbukumbu ya ukaguzi:',
    'admin_audit_log_filter_all_prefix': 'Zote',
    'admin_audit_log_export_button': 'Safirisha CSV',
    'admin_audit_log_empty_title': 'Hakuna shughuli bado',
    'admin_audit_log_empty_body':
        'Vitendo vya wasimamizi (kutengeneza/kuhariri/kufuta maeneo, '
            'miji, kategoria, majukumu, machapisho ya blogu) vitaonekana '
            'hapa vinapotokea.',

    // Admin static pages screen
    'admin_static_pages_label_about': 'Kuhusu Sisi',
    'admin_static_pages_label_privacy': 'Sera ya Faragha',
    'admin_static_pages_label_terms': 'Masharti ya Huduma',
    'admin_static_pages_label_cookie': 'Sera ya Kuki',
    'admin_static_pages_not_edited_yet':
        'Bado haijahaririwa — inaonyesha maudhui chaguo-msingi',
    'admin_static_pages_last_edited_by_prefix': 'Ilihaririwa mara ya mwisho na',
    'admin_static_pages_unknown_editor': 'haijulikani',
    'admin_static_pages_edit_button': 'Hariri',
    'admin_static_pages_edit_title_prefix': 'Hariri',
    'admin_static_pages_error_save_failed_prefix': 'Imeshindwa kuhifadhi:',
    'admin_static_pages_field_page_title': 'Kichwa cha Ukurasa',
    'admin_static_pages_field_subtitle': 'Kichwa kidogo / Kaulimbiu',
    'admin_static_pages_subtitle_helper':
        'Hiari — inatumika kwenye Kuhusu Sisi pekee',
    'admin_static_pages_field_last_updated': 'Lebo ya Kusasishwa Mwisho',
    'admin_static_pages_hint_last_updated': 'k.m. Julai 2026',
    'admin_static_pages_sections_heading': 'Sehemu',
    'admin_static_pages_section_prefix': 'Sehemu',
    'admin_static_pages_field_heading': 'Kichwa',
    'admin_static_pages_heading_helper': 'Acha wazi kwa aya ya kawaida',
    'admin_static_pages_field_body': 'Maudhui',
    'admin_static_pages_add_section': 'Ongeza sehemu',
    'admin_static_pages_saving': 'Inahifadhi…',
    'admin_static_pages_save_page': 'Hifadhi Ukurasa',

    // Admin settings screen
    'admin_settings_audit_target_system_settings': 'Mipangilio ya Mfumo',
    'admin_settings_saved_success': 'Mipangilio imehifadhiwa.',
    'admin_settings_error_save_failed_prefix':
        'Imeshindwa kuhifadhi mipangilio:',
    'admin_settings_maintenance_confirm_title': 'Washa Hali ya Matengenezo?',
    'admin_settings_maintenance_confirm_body':
        'Watalii wataona taarifa ya matengenezo badala ya ukurasa wa mwanzo '
            'hadi hii itakapozimwa tena. Wasimamizi hawaathiriwi.',
    'admin_settings_btn_enable': 'Washa',
    'admin_settings_audit_enabled': 'Imewashwa',
    'admin_settings_audit_disabled': 'Imezimwa',
    'admin_settings_maintenance_enabled': 'Hali ya matengenezo imewashwa.',
    'admin_settings_maintenance_disabled': 'Hali ya matengenezo imezimwa.',
    'admin_settings_error_maintenance_update_failed_prefix':
        'Imeshindwa kusasisha hali ya matengenezo:',
    'admin_settings_audit_target_maintenance_mode': 'Hali ya Matengenezo',
    'admin_settings_export_success_prefix': 'Imesafirisha',
    'admin_settings_export_success_suffix':
        'hati katika kila mkusanyiko wa Firestore. Maeneo/Miji/Kategoria/Usanidi wa Uhifadhi hukaa kwenye hifadhidata ya nyuma na hayahusiki na usafirishaji huu.',
    'admin_settings_error_export_failed_prefix': 'Usafirishaji umeshindwa:',
    'admin_settings_section_contact_title': 'Taarifa za Mawasiliano kwa Umma',
    'admin_settings_section_contact_subtitle':
        'Inaonyeshwa kwenye sehemu ya chini ya ukurasa wa mwanzo na skrini za mawasiliano.',
    'admin_settings_field_contact_email': 'Barua Pepe ya Mawasiliano',
    'admin_settings_field_contact_phone': 'Simu ya Mawasiliano',
    'admin_settings_section_footer_links_title': 'Viungo vya Sehemu ya Chini',
    'admin_settings_section_footer_links_subtitle':
        'Viungo vya ziada vinavyoonyeshwa kwenye sehemu ya chini ya ukurasa wa mwanzo.',
    'admin_settings_field_link_label': 'Lebo',
    'admin_settings_hint_link_label': 'k.m. Masharti ya Huduma',
    'admin_settings_field_link_url': 'URL',
    'admin_settings_add_link': 'Ongeza kiungo',
    'admin_settings_section_maintenance_title': 'Hali ya Matengenezo',
    'admin_settings_section_maintenance_subtitle':
        'Ikiwashwa, watalii wataona taarifa ya matengenezo badala ya '
            'ukurasa wa mwanzo. Wasimamizi bado wanaweza kuingia na kusimamia '
            'jukwaa kama kawaida.',
    'admin_settings_maintenance_on': 'Hali ya matengenezo IMEWASHWA',
    'admin_settings_maintenance_off': 'Hali ya matengenezo IMEZIMWA',
    'admin_settings_field_maintenance_message': 'Ujumbe wa Matengenezo',
    'admin_settings_hint_maintenance_message':
        'Tutarudi hivi karibuni — asante kwa uvumilivu wako.',
    'admin_settings_section_export_title': 'Usafirishaji wa Data',
    'admin_settings_section_export_subtitle':
        'Inapakua kila mkusanyiko unaotegemea Firestore (Watumiaji, '
            'Vipendwa, Uhifadhi, Maombi ya Usimamizi, Njia za Malipo, '
            'Maelezo ya Maeneo, Maswali ya Maeneo, Maelezo ya Miji, Maelezo '
            'ya Kategoria, Mipangilio, Kurasa Tuli, Kumbukumbu ya Ukaguzi) '
            'kama faili moja la JSON. Maeneo, Miji, Kategoria na Usanidi wa '
            'Uhifadhi hukaa kwenye hifadhidata ya nyuma — nakala halisi ya '
            'data hiyo inahitaji zana za kiwango cha DB upande wa mwenyeji, '
            'si kitufe hiki.',
    'admin_settings_exporting': 'Inasafirisha…',
    'admin_settings_export_button': 'Safirisha Data ya Firestore',
    'admin_settings_saving': 'Inahifadhi…',
    'admin_settings_save_button': 'Hifadhi Mipangilio',

    // Admin reports screen
    'admin_reports_csv_header_section': 'Sehemu',
    'admin_reports_csv_header_label': 'Lebo',
    'admin_reports_csv_header_value': 'Thamani',
    'admin_reports_csv_section_bookings': 'Uhifadhi',
    'admin_reports_csv_label_total': 'Jumla',
    'admin_reports_csv_label_pending': 'Inasubiri',
    'admin_reports_csv_label_confirmed': 'Imethibitishwa',
    'admin_reports_csv_label_completed': 'Imekamilika',
    'admin_reports_csv_label_cancelled': 'Imeghairiwa',
    'admin_reports_csv_label_estimated_revenue': 'Mapato Yanayokadiriwa',
    'admin_reports_csv_section_visitor_traffic': 'Msongamano wa Wageni',
    'admin_reports_csv_label_total_page_views':
        'Jumla ya Mionekano ya Ukurasa (siku 30)',
    'admin_reports_csv_section_businesses_per_city': 'Biashara kwa Kila Mji',
    'admin_reports_csv_section_businesses_per_channel':
        'Biashara kwa Kila Kituo',
    'admin_reports_page_title': 'Ripoti',
    'admin_reports_export_button': 'Safirisha CSV',
    'admin_reports_bookings_heading': 'Uhifadhi — Mfumo Mzima',
    'admin_reports_bookings_subtitle':
        'Jumla za moja kwa moja katika kila eneo kwenye jukwaa.',
    'admin_reports_stat_total_bookings': 'Jumla ya Uhifadhi',
    'admin_reports_stat_paid_via_mpesa': 'Imelipwa kwa M-Pesa',
    'admin_reports_stat_simulated_payments': 'Malipo ya Majaribio',
    'admin_reports_top_places_heading': 'Maeneo Bora kwa Uhifadhi',
    'admin_reports_no_bookings_yet': 'Hakuna uhifadhi bado.',
    'admin_reports_booking_singular': 'uhifadhi',
    'admin_reports_booking_plural': 'uhifadhi',
    'admin_reports_visitor_traffic_heading':
        'Msongamano wa Wageni — Siku 30 Zilizopita',
    'admin_reports_visitor_traffic_subtitle':
        'Mionekano ya ukurasa wa mwanzo, inayofuatiliwa na programu hii '
            '(nakala tofauti pia hutumwa kwa Google Analytics — data ya '
            'GA4 yenyewe haisomeki tena kutoka kwa programu).',
    'admin_reports_traffic_not_enough':
        'Bado hakuna historia ya kutosha ya msongamano — angalia tena baada ya siku chache.',
    'admin_reports_no_cities_yet': 'Hakuna miji ya mapumziko bado.',
    'admin_reports_place_singular': 'eneo',
    'admin_reports_place_plural': 'maeneo',
    'admin_reports_no_categories_yet': 'Hakuna kategoria bado.',

    // Admin categories screen
    'admin_categories_page_title': 'Kategoria',
    'admin_categories_page_subtitle':
        'Kategoria za huduma za jumla — zinazoshirikiwa katika miji yote',
    'admin_categories_add_button': 'Ongeza Kategoria',
    'admin_categories_search_hint': 'Tafuta kategoria…',
    'admin_categories_filter_active': 'Inatumika',
    'admin_categories_filter_inactive': 'Haitumiki',
    'admin_categories_empty_title': 'Hakuna kategoria bado',
    'admin_categories_empty_body':
        'Tengeneza kategoria yako ya kwanza kama Malazi, Chakula, au Ustawi.',
    'admin_categories_add_first_button': 'Ongeza Kategoria ya Kwanza',
    'admin_categories_snack_created': 'Kategoria imetengenezwa',
    'admin_categories_snack_updated': 'Kategoria imesasishwa',
    'admin_categories_snack_subcategory_added_prefix':
        'Kategoria ndogo imeongezwa kwa',
    'admin_categories_snack_subcategory_updated': 'Kategoria ndogo imesasishwa',
    'admin_categories_snack_deleted_prefix': 'Imefutwa',
    'admin_categories_snack_delete_failed_prefix': 'Kufuta kumeshindwa:',
    'admin_categories_delete_confirm_title_prefix': 'Futa',
    'admin_categories_delete_confirm_body_default':
        'Hatua hii haiwezi kutenduliwa.',
    'admin_categories_delete_confirm_body_has_children':
        'Hii pia itafuta kategoria ndogo zote. Tumia ufutaji wa kuporomoka.',
    'admin_categories_delete_confirm_body_has_links_prefix':
        'Kategoria hii imeunganishwa na',
    'admin_categories_delete_confirm_body_has_links_suffix':
        'eneo/maeneo. Ondoa viungo kwanza.',
    'admin_categories_menu_edit': 'Hariri',
    'admin_categories_menu_deactivate': 'Zima',
    'admin_categories_menu_activate': 'Washa',
    'admin_categories_status_active': 'Inatumika',
    'admin_categories_status_inactive': 'Haitumiki',
    'admin_categories_count_subcats': 'kategoria ndogo',
    'admin_categories_count_places': 'maeneo',
    'admin_categories_add_subcategory_prefix': 'Ongeza kategoria ndogo kwa',
    'admin_categories_dialog_edit_category': 'Hariri Kategoria',
    'admin_categories_dialog_edit_subcategory': 'Hariri Kategoria Ndogo',
    'admin_categories_dialog_add_category': 'Ongeza Kategoria',
    'admin_categories_dialog_add_subcategory': 'Ongeza Kategoria Ndogo',
    'admin_categories_field_category_type': 'Aina ya Kategoria',
    'admin_categories_root_category_label': 'Kategoria kuu (ngazi ya juu)',
    'admin_categories_subcategory_of_prefix': 'Kategoria ndogo ya:',
    'admin_categories_field_name': 'Jina la Kategoria',
    'admin_categories_hint_name': 'k.m. Malazi',
    'admin_categories_field_slug': 'Slug',
    'admin_categories_hint_slug': 'k.m. malazi',
    'admin_categories_helper_slug':
        'Inatengenezwa kiotomatiki kutoka jina. Herufi ndogo, mistari pekee.',
    'admin_categories_hint_icon': '🏨',
    'admin_categories_helper_icon': 'Bandika emoji moja',
    'admin_categories_field_description': 'Maelezo',
    'admin_categories_hint_description': 'Maelezo mafupi ya kategoria hii',
    'admin_categories_field_sort_order': 'Mpangilio wa Mfuatano',
    'admin_categories_helper_sort_order': 'Nambari ndogo huonekana kwanza',
    'admin_categories_field_tags': 'Vitambulisho',
    'admin_categories_hint_tags': 'k.m. ufuoni, rafiki wa familia, bei nafuu',
    'admin_categories_helper_tags':
        'Vinavyotenganishwa kwa koma — vinatumika kwa utafutaji/uchujaji',
    'admin_categories_field_visible_in': 'Inaonekana Katika',
    'admin_categories_visible_all_cities':
        'Miji yote ya mapumziko (chaguo-msingi)',
    'admin_categories_visible_selected_suffix': 'miji iliyochaguliwa',

    // Admin place map picker
    'admin_place_map_picker_title': 'Chagua Mahali kwenye Ramani',
    'admin_place_map_picker_tooltip_normal': 'Ramani ya Kawaida',
    'admin_place_map_picker_tooltip_satellite': 'Setelaiti',
    'admin_place_map_picker_resolving': 'INATAFUTA…',
    'admin_place_map_picker_confirm': 'THIBITISHA',
    'admin_place_map_picker_search_hint':
        'Tafuta mahali, hoteli, mkahawa, eneo…',
    'admin_place_map_picker_no_results':
        'Hakuna matokeo yaliyopatikana. Jaribu jina lingine, au gusa moja kwa moja kwenye ramani.',
    'admin_place_map_picker_resolving_address': 'Inatafuta anwani…',
    'admin_place_map_picker_bottom_hint':
        'Gusa mahali popote kwenye ramani ili kuweka pini. Buruta pini '
            'kurekebisha. Tafuta juu ili kupata maeneo yenye majina. Gusa ✕ '
            'kwenye upau wa taarifa hapo juu ili kuondoa pini isiyo sahihi.',
    'admin_place_map_picker_snack_select_first':
        'Gusa kwenye ramani au tafuta ili kuchagua eneo kwanza.',
    'admin_place_map_picker_snack_still_resolving':
        'Bado inatafuta anwani ya pini hii — subiri kidogo.',
    'admin_place_map_picker_tooltip_clear_pin': 'Ondoa pini',
    'admin_place_map_picker_crash_title': 'Onyesho la Ramani Halipatikani',
    'admin_place_map_picker_crash_default_message':
        'Huduma ya ramani haipatikani.',
    'admin_place_map_picker_crash_fallback_note':
        'Habari njema: kutafuta juu na Thibitisha bado vinafanya kazi bila '
            'hii — ni kuweka pini kwa kugusa na kurekebisha kwa kuburuta '
            'pekee vinavyohitaji ramani ya kuona.',
    'admin_place_map_picker_close_manual': 'Funga na Weka Kwa Mkono',
    'admin_place_map_picker_watchdog_message':
        'Onyesho la ramani halipakii — hii kwa kawaida inamaanisha huduma '
            'ya Ramani haijawashwa kikamilifu kwa programu hii bado.',

    // Admin places screen
    'admin_places_add_button': 'Ongeza Eneo',
    'admin_places_page_title': 'Maeneo',
    'admin_places_subtitle_all': 'Maeneo yote katika miji yote',
    'admin_places_subtitle_filtered_prefix': 'Kimechujwa kwa:',
    'admin_places_delete_confirm_active_body':
        'Eneo hili kwa sasa LINAFANYA KAZI. Kulifuta kutalitoa kwenye '
            'programu. Hatua hii haiwezi kutenduliwa.',
    'admin_places_snack_deleted_prefix': 'Imefutwa',
    'admin_places_snack_delete_failed_prefix': 'Kufuta kumeshindwa:',
    'admin_places_snack_featured_suffix': 'sasa imeangaziwa',
    'admin_places_snack_unfeatured_suffix': 'imeondolewa kuangaziwa',
    'admin_places_snack_update_failed_prefix': 'Imeshindwa kusasisha:',
    'admin_places_snack_loading_data': 'Inapakia data…',
    'admin_places_search_hint_narrow': 'Tafuta maeneo…',
    'admin_places_search_hint_wide': 'Tafuta kwa jina, mji, au anwani…',
    'admin_places_status_active': 'Linafanya Kazi',
    'admin_places_status_pending': 'Inasubiri',
    'admin_places_status_suspended': 'Imesimamishwa',
    'admin_places_status_archived': 'Imehifadhiwa',
    'admin_places_empty_title_none': 'Hakuna maeneo bado',
    'admin_places_empty_title_no_matches': 'Hakuna zinazolingana',
    'admin_places_empty_body_none':
        'Tengeneza eneo lako la kwanza kwa kutumia mchawi.\nJaza maelezo '
            'ya msingi, eneo, media, na uunganishe na kategoria.',
    'admin_places_empty_body_no_matches':
        'Jaribu utafutaji au kichujio kingine.',
    'admin_places_empty_action_add_first': 'Ongeza Eneo la Kwanza',
    'admin_places_filter_all_cities': 'Miji yote',
    'admin_places_filter_all_categories': 'Kategoria zote',
    'admin_places_menu_edit_continue': 'Hariri / Endelea',
    'admin_places_menu_unfeature': 'Ondoa Kuangaziwa',
    'admin_places_menu_feature': 'Angazia kwenye ukurasa wa mwanzo/kategoria',
    'admin_places_completion_suffix': '% imekamilika',
    'admin_places_draft_badge': 'RASIMU',
    'admin_places_continue_button': 'Endelea',
    'admin_places_edit_button': 'Hariri',

    // Admin blog compose screen
    'admin_blog_compose_title_edit': 'Hariri Chapisho',
    'admin_blog_compose_title_new': 'Chapisho Jipya la Blogu',
    'admin_blog_compose_tab_content': 'Maudhui',
    'admin_blog_compose_tab_meta_seo': 'Meta & SEO',
    'admin_blog_compose_tab_settings': 'Mipangilio',
    'admin_blog_compose_save_draft': 'Hifadhi Rasimu',
    'admin_blog_compose_publish_button': 'Chapisha',
    'admin_blog_compose_error_title_required': 'Kichwa kinahitajika',
    'admin_blog_compose_error_content_min_prefix':
        'Maudhui lazima yawe na angalau herufi 100 (kwa sasa',
    'admin_blog_compose_error_content_min_suffix': ')',
    'admin_blog_compose_error_scheduled_required':
        'Tarehe/muda wa kuratibiwa unahitajika',
    'admin_blog_compose_snack_updated': 'Chapisho limesasishwa kwa mafanikio',
    'admin_blog_compose_snack_created': 'Chapisho limetengenezwa kwa mafanikio',
    'admin_blog_compose_field_post_title': 'Kichwa cha Chapisho',
    'admin_blog_compose_hint_post_title': 'k.m. Hoteli 10 Bora Mombasa',
    'admin_blog_compose_field_content': 'Maudhui',
    'admin_blog_compose_rich_text_badge': 'Maandishi Yaliyopambwa',
    'admin_blog_compose_editor_placeholder':
        'Anza kuandika makala yako hapa. Tumia upau wa vifaa hapo juu '
            'kupamba maandishi, kuongeza vichwa, orodha, viungo…',
    'admin_blog_compose_min_characters_note':
        'Angalau herufi 100 za maudhui halisi.',
    'admin_blog_compose_field_excerpt': 'Muhtasari',
    'admin_blog_compose_hint_excerpt':
        'Muhtasari mfupi unaoonyeshwa kwenye orodha za machapisho…',
    'admin_blog_compose_helper_excerpt':
        'Hiari — hutengenezwa kiotomatiki ikiachwa wazi.',
    'admin_blog_compose_field_categories': 'Kategoria',
    'admin_blog_compose_hint_categories': 'malazi, chakula, ustawi',
    'admin_blog_compose_helper_categories':
        'Vitambulisho vya kategoria vilivyotenganishwa kwa koma.',
    'admin_blog_compose_field_tags': 'Vitambulisho',
    'admin_blog_compose_hint_tags': 'anasa, bei nafuu, familia',
    'admin_blog_compose_helper_tags':
        'Vitambulisho vilivyotenganishwa kwa koma.',
    'admin_blog_compose_seo_preview_heading': 'Onyesho la SEO',
    'admin_blog_compose_seo_preview_url': 'resortcities.com › blog',
    'admin_blog_compose_seo_preview_title_placeholder': 'Kichwa cha ukurasa…',
    'admin_blog_compose_seo_preview_desc_placeholder':
        'Maelezo ya meta yataonekana hapa…',
    'admin_blog_compose_field_meta_title': 'Kichwa cha Meta',
    'admin_blog_compose_hint_meta_title':
        'k.m. Hoteli 10 Bora Mombasa — Mwongozo wa 2026',
    'admin_blog_compose_helper_meta_title': 'Inapendekezwa: herufi 50–60.',
    'admin_blog_compose_field_meta_desc': 'Maelezo ya Meta',
    'admin_blog_compose_hint_meta_desc':
        'Maelezo yenye kuvutia kwa injini za utafutaji…',
    'admin_blog_compose_helper_meta_desc': 'Inapendekezwa: herufi 150–160.',
    'admin_blog_compose_field_featured_image': 'URL ya Picha Kuu',
    'admin_blog_compose_hint_featured_image':
        'https://cdn.resortcities.com/images/…',
    'admin_blog_compose_helper_featured_image':
        'URL kamili ya picha ya jalada la chapisho.',
    'admin_blog_compose_image_preview_error':
        'Imeshindwa kupakia onyesho la picha',
    'admin_blog_compose_post_status_label': 'Hali ya Chapisho',
    'admin_blog_compose_field_scheduled':
        'Tarehe na Muda wa Kuchapisha (ISO 8601)',
    'admin_blog_compose_helper_scheduled': 'Muundo: YYYY-MM-DDTHH:MM:SSZ',
    'admin_blog_compose_save_scheduled_button': 'Hifadhi Kama Iliyoratibiwa',
    'admin_blog_compose_field_city_id': 'Kitambulisho cha Mji (hiari)',
    'admin_blog_compose_helper_city_id':
        'Unganisha chapisho hili na mji maalum wa mapumziko.',
    'admin_blog_compose_publishing_notes_heading': 'Maelezo ya Uchapishaji',
    'admin_blog_compose_publishing_notes_body':
        '• RASIMU — inaonekana kwa wasimamizi pekee.\n'
            '• IMECHAPISHWA — inaonekana mara moja kwenye programu ya mtumiaji.\n'
            '• IMERATIBIWA — inaonekana kwenye tarehe na muda uliowekwa.',

    // Admin role requests screen
    'admin_role_requests_error_approve_missing_uid':
        'Imeshindwa kuidhinisha: UID ya Firebase ya mtumiaji haipo kwenye ombi hili.',
    'admin_role_requests_error_approve_failed':
        'Uidhinishaji umeshindwa. Tafadhali jaribu tena.',
    'admin_role_requests_snack_approved_as': 'ameidhinishwa kama',
    'admin_role_requests_snack_request_from': 'Ombi kutoka',
    'admin_role_requests_snack_declined_suffix': 'limekataliwa.',
    'admin_role_requests_error_deny_failed':
        'Kitendo kimeshindwa. Tafadhali jaribu tena.',
    'admin_role_requests_error_revoke_missing_uid':
        'Imeshindwa kubatilisha: UID ya Firebase ya mtumiaji haipo.',
    'admin_role_requests_revoke_confirm_title':
        'Batilisha Jukumu la Usimamizi?',
    'admin_role_requests_revoke_confirm_body_prefix': 'Hii itaondoa jukumu la',
    'admin_role_requests_revoke_confirm_body_middle': 'kutoka kwa',
    'admin_role_requests_revoke_confirm_body_suffix':
        'na kurejesha akaunti yao kwenye kiwango cha Mtalii. Wanaweza kuomba tena wakati wowote.',
    'admin_role_requests_confirm_revoke': 'Batilisha',
    'admin_role_requests_snack_role_revoked_prefix':
        'Jukumu limebatilishwa kwa',
    'admin_role_requests_error_revoke_failed':
        'Ubatilishaji umeshindwa. Tafadhali jaribu tena.',
    'admin_role_requests_delete_confirm_title': 'Futa Ombi?',
    'admin_role_requests_delete_confirm_body_prefix':
        'Hii itaondoa kabisa ombi lililokataliwa kutoka kwa',
    'admin_role_requests_delete_confirm_body_suffix':
        'Hatua hii haiwezi kutenduliwa.',
    'admin_role_requests_snack_deleted_suffix': 'limefutwa.',
    'admin_role_requests_error_delete_failed':
        'Kufuta kumeshindwa. Tafadhali jaribu tena.',
    'admin_role_requests_error_switch_missing_uid':
        'Imeshindwa kubadilisha jukumu: UID ya Firebase ya mtumiaji haipo.',
    'admin_role_requests_error_reassign_missing_uid':
        'Imeshindwa kupanga upya: UID ya Firebase ya mtumiaji haipo.',
    'admin_role_requests_tab_pending': 'Inasubiri',
    'admin_role_requests_tab_approved': 'Imeidhinishwa',
    'admin_role_requests_tab_denied': 'Imekataliwa',
    'admin_role_requests_stat_total': 'Jumla',
    'admin_role_requests_approve_sheet_title': 'Idhinisha Ombi',
    'admin_role_requests_approve_sheet_notice_prefix':
        'Kuidhinisha kutatoa jukumu lililochaguliwa na kusasisha mara moja ufikiaji wa',
    'admin_role_requests_approve_sheet_notice_suffix': 'katika jukwaa.',
    'admin_role_requests_select_role_to_grant': 'Chagua Jukumu la Kutoa',
    'admin_role_requests_role_desc_city_manager':
        'Anasimamia eneo moja lililokabidhiwa — uhifadhi, maswali, maelezo. '
            'Anaweza kuongeza/kuhariri na kufuta ndani ya eneo hilo.',
    'admin_role_requests_role_desc_content_admin':
        'Wigo sawa wa eneo moja kama Meneja wa Mji, lakini anaweza '
            'kuongeza/kuhariri maudhui tu — hawezi kufuta data ya msingi.',
    'admin_role_requests_role_desc_main_admin':
        'Ufikiaji kamili wa mfumo ikiwa ni pamoja na kutoa na kubatilisha kila jukumu.',
    'admin_role_requests_approve_as_prefix': 'Idhinisha kama',
    'admin_role_requests_switch_sheet_title': 'Badilisha Jukumu',
    'admin_role_requests_switch_sheet_notice_currently_prefix': 'Kwa sasa',
    'admin_role_requests_switch_sheet_notice_suffix':
        'Kubadilisha kutasasisha mara moja ufikiaji wa',
    'admin_role_requests_switch_sheet_notice_suffix2':
        'katika jukwaa. Ikiwa jukumu jipya linahitaji ugawaji wa eneo na '
            'hakuna lililopo, utaulizwa kuchagua moja baadaye.',
    'admin_role_requests_select_new_role': 'Chagua Jukumu Jipya',
    'admin_role_requests_select_different_role': 'Chagua jukumu tofauti',
    'admin_role_requests_switch_to_prefix': 'Badilisha kuwa',
    'admin_role_requests_deny_sheet_title': 'Kataa Ombi',
    'admin_role_requests_deny_sheet_notice_prefix':
        'Mtumiaji ataarifiwa kuwa ombi lake la usimamizi kwa',
    'admin_role_requests_deny_sheet_notice_suffix': 'limekataliwa.',
    'admin_role_requests_reason_for_denial': 'Sababu ya Kukataa (hiari)',
    'admin_role_requests_reason_hint':
        'k.m. Nyaraka za kutosha za uthibitisho hazipo.',
    'admin_role_requests_btn_decline_request': 'Kataa Ombi',
    'admin_role_requests_status_pending': 'INASUBIRI',
    'admin_role_requests_status_approved': 'IMEIDHINISHWA',
    'admin_role_requests_status_declined': 'IMEKATALIWA',
    'admin_role_requests_services_offered': 'HUDUMA ZINAZOTOLEWA',
    'admin_role_requests_meta_submitted_prefix': 'Imetumwa:',
    'admin_role_requests_meta_by_prefix': 'Na:',
    'admin_role_requests_meta_role_prefix': 'Jukumu:',
    'admin_role_requests_reason_prefix': 'Sababu:',
    'admin_role_requests_btn_decline': 'Kataa',
    'admin_role_requests_btn_approve': 'Idhinisha',
    'admin_role_requests_btn_reassign_place': 'Panga Upya Eneo',
    'admin_role_requests_btn_switch_role': 'Badilisha Jukumu',
    'admin_role_requests_btn_revoke_role': 'Batilisha Jukumu',
    'admin_role_requests_btn_reapprove': 'Idhinisha Tena',
    'admin_role_requests_empty_all': 'maombi',
    'admin_role_requests_empty_pending': 'maombi yanayosubiri',
    'admin_role_requests_empty_approved': 'maombi yaliyoidhinishwa',
    'admin_role_requests_empty_declined': 'maombi yaliyokataliwa',
    'admin_role_requests_empty_prefix': 'Hakuna',
    'admin_role_requests_empty_body': 'Yataonekana hapa yatakapotumwa.',
    'admin_role_requests_error_load_title': 'Imeshindwa kupakia maombi',

    // Admin Dashboard shell
    'admin_dashboard_nav_dashboard': 'Dashibodi',
    'admin_dashboard_nav_resort_cities': 'Miji ya Mapumziko',
    'admin_dashboard_nav_categories': 'Jamii',
    'admin_dashboard_nav_places': 'Maeneo',
    'admin_dashboard_nav_blog': 'Blogu',
    'admin_dashboard_nav_role_requests': 'Maombi ya Majukumu',
    'admin_dashboard_nav_payment_methods': 'Njia za Malipo',
    'admin_dashboard_nav_bookings': 'Ubunifu wa Nafasi',
    'admin_dashboard_nav_reports': 'Ripoti',
    'admin_dashboard_nav_messages': 'Ujumbe',
    'admin_dashboard_nav_settings': 'Mipangilio',
    'admin_dashboard_nav_static_pages': 'Kurasa Tuli',
    'admin_dashboard_nav_audit_log': 'Kumbukumbu za Ukaguzi',
    'admin_dashboard_title_admin_console': 'Dashibodi ya Msimamizi',
    'admin_dashboard_subtitle_overview':
        'Muhtasari wa mfumo na vitendo vya haraka',
    'admin_dashboard_subtitle_resort_cities':
        'Ongeza, hariri na ondoa maeneo ya mapumziko',
    'admin_dashboard_subtitle_categories':
        'Simamia jamii na jamii ndogo za kimataifa',
    'admin_dashboard_subtitle_places_filtered_prefix':
        'Inaonyesha maeneo katika',
    'admin_dashboard_subtitle_places': 'Simamia orodha na maeneo',
    'admin_dashboard_subtitle_blog': 'Unda, hariri na chapisha makala za blogu',
    'admin_dashboard_role_requests_pending_singular':
        'ombi linalosubiri kukaguliwa',
    'admin_dashboard_role_requests_pending_plural':
        'maombi yanayosubiri kukaguliwa',
    'admin_dashboard_subtitle_role_requests':
        'Kagua na simamia maombi ya majukumu ya usimamizi',
    'admin_dashboard_subtitle_payment_methods':
        'Sanidi chaguo za malipo ambazo maeneo yanaweza kukubali',
    'admin_dashboard_subtitle_bookings':
        'Kagua na simamia maombi ya ubunifu wa watalii',
    'admin_dashboard_subtitle_reports': 'Uchambuzi wa ubunifu wa mfumo mzima',
    'admin_dashboard_subtitle_messages':
        'Ujumbe uliotumwa kupitia fomu ya mawasiliano ya ukurasa wa kwanza',
    'admin_dashboard_subtitle_settings':
        'Maelezo ya mawasiliano, viungo vya chini, hali ya matengenezo na uhamishaji data',
    'admin_dashboard_subtitle_static_pages':
        'Hariri Kutuhusu, Sera ya Faragha, Masharti ya Huduma, Sera ya Vidakuzi',
    'admin_dashboard_subtitle_audit_log':
        'Kila hatua ya msimamizi, kwa mpangilio — nani alifanya nini, na lini',
    'admin_dashboard_logo_label': 'Msimamizi',
    'admin_dashboard_place_admin': 'Msimamizi wa Eneo',
    'admin_dashboard_place_admin_sub': 'Simamia eneo maalum',
    'admin_dashboard_back_to_app': 'Rudi kwenye Programu',
    'admin_dashboard_no_place_title': 'Hakuna eneo lililopangwa bado',
    'admin_dashboard_no_place_body':
        'Msimamizi Mkuu anahitaji kuunganisha akaunti yako na eneo kabla ya kusimamia chochote hapa.',
    'admin_dashboard_active_filters': 'Vichujio vinavyotumika',
    'admin_dashboard_stat_registered_users': 'Watumiaji Waliosajiliwa',
    'admin_dashboard_stat_active_places': 'Maeneo Yanayotumika',
    'admin_dashboard_stat_pending_drafts': 'Rasimu Zinazosubiri',
    'admin_dashboard_quick_actions': 'Vitendo vya Haraka',
    'admin_dashboard_qa_add_resort_city': 'Ongeza Mji wa Mapumziko',
    'admin_dashboard_qa_add_resort_city_desc': 'Unda eneo jipya la mapumziko',
    'admin_dashboard_qa_add_category': 'Ongeza Jamii',
    'admin_dashboard_qa_add_category_desc': 'Unda jamii mpya ya huduma',
    'admin_dashboard_qa_add_place': 'Ongeza Eneo',
    'admin_dashboard_qa_add_place_desc': 'Orodhesha eneo au biashara mpya',
    'admin_dashboard_qa_write_blog': 'Andika Makala ya Blogu',
    'admin_dashboard_qa_write_blog_desc': 'Chapisha makala au mwongozo mpya',
    'admin_dashboard_qa_role_requests_desc':
        'Kagua maombi ya majukumu ya usimamizi',
    'admin_dashboard_qa_role_requests_pending_suffix':
        'yanasubiri • gusa kukagua',
    'admin_dashboard_qa_payment_methods_desc':
        'Sanidi chaguo za malipo zinazokubalika',
    'admin_dashboard_qa_bookings_desc': 'Kagua maombi ya ubunifu ya watalii',
    'admin_dashboard_growth_title': 'Ukuaji — Siku 30 Zilizopita',
    'admin_dashboard_growth_desc':
        'Maeneo yanayotumika, miji ya mapumziko na watumiaji waliosajiliwa, '
            'yaliyopimwa mara moja kwa siku.',
    'admin_dashboard_growth_no_history':
        'Bado hakuna historia ya kutosha — angalia tena baada ya siku '
            'chache za shughuli kuona mwelekeo.',
    'admin_dashboard_legend_active_places': 'Maeneo yanayotumika',
    'admin_dashboard_legend_resort_cities': 'Miji ya mapumziko',
    'admin_dashboard_legend_users': 'Watumiaji',
    'admin_dashboard_workflow_title': 'Mchakato wa Kuanzisha',
    'admin_dashboard_workflow_step1_body':
        'Unda kila mji unaolengwa (mfano: Mombasa, Nairobi).',
    'admin_dashboard_workflow_step2_body':
        'Unda jamii za kimataifa (Malazi, Chakula, Ustawi…).',
    'admin_dashboard_workflow_step3_body':
        'Ongeza kila eneo kupitia mchakato wa hatua 11.',
    'admin_dashboard_workflow_step4_body':
        'Chapisha makala, miongozo, na vivutio vya miji.',
    'admin_dashboard_workflow_step5_body':
        'Kagua na idhinisha maombi ya majukumu ya usimamizi kutoka kwa watumiaji.',
    'admin_dashboard_workflow_step6_body':
        'Bainisha chaguo za malipo ambazo maeneo yanaweza kukubali (M-Pesa, Kadi, Fedha taslimu…).',
    'admin_dashboard_workflow_step7_body':
        'Kagua na thibitisha maombi ya ubunifu yaliyotumwa na watalii.',

    // Admin Blog List
    'admin_blog_error_load_post_prefix': 'Imeshindwa kupakia makala:',
    'admin_blog_loading_post': 'Inapakia makala…',
    'admin_blog_delete_dialog_title': 'Futa Makala',
    'admin_blog_delete_dialog_body_prefix': 'Ungependa kuondoaje',
    'admin_blog_delete_dialog_body_suffix': '?',
    'admin_blog_archive': 'Hifadhi Kumbukumbu',
    'admin_blog_permanent': 'Kudumu',
    'admin_blog_permanent_delete_title': 'Futa Kabisa',
    'admin_blog_permanent_delete_body_prefix': 'Hatua hii ni',
    'admin_blog_permanent_delete_body_irreversible': 'HAIWEZI KUTENGUZWA',
    'admin_blog_permanent_delete_body_suffix':
        '. Makala, maoni yake yote, kupendwa, na historia ya kutazamwa '
            'itafutwa kabisa kwenye database.\n\nUna uhakika kabisa?',
    'admin_blog_yes_delete_permanently': 'Ndiyo, Futa Kabisa',
    'admin_blog_snack_permanently_deleted_suffix': 'imefutwa kabisa.',
    'admin_blog_snack_archived_suffix': 'imehifadhiwa kwenye kumbukumbu.',
    'admin_blog_error_delete_prefix': 'Kufuta kumeshindwa:',
    'admin_blog_search_hint': 'Tafuta makala… (upande wa seva, kurasa zote)',
    'admin_blog_new_post': 'Makala Mpya',
    'admin_blog_filter_all': 'Makala Zote',
    'admin_blog_filter_published': 'Zilizochapishwa',
    'admin_blog_filter_drafts': 'Rasimu',
    'admin_blog_filter_scheduled': 'Zilizopangwa',
    'admin_blog_filter_my_drafts': 'Rasimu Zangu',
    'admin_blog_untitled': 'Bila Kichwa',
    'admin_blog_min_read_suffix': 'dk kusoma',
    'admin_blog_comments': 'Maoni',
    'admin_blog_promote': 'Kuza',
    'admin_blog_edit': 'Hariri',
    'admin_blog_promote_dialog_title': 'Kuza Makala',
    'admin_blog_featured': 'Iliyoangaziwa',
    'admin_blog_featured_sub': 'Inaonekana kwanza kwenye sehemu ya blogu',
    'admin_blog_paid_advert': 'Tangazo Linalolipwa',
    'admin_blog_paid_advert_sub': 'Inaonyesha lebo ya "Imefadhiliwa na"',
    'admin_blog_sponsor_name': 'Jina la Mfadhili',
    'admin_blog_related_links': 'Viungo Vinavyohusiana',
    'admin_blog_link_a_place': 'Unganisha Eneo',
    'admin_blog_saving': 'Inahifadhi…',
    'admin_blog_reply_hint': 'Andika jibu…',
    'admin_blog_comment_hint': 'Ongeza maoni…',
    'admin_blog_no_comments_yet': 'Hakuna maoni bado.',
    'admin_blog_be_first_comment': 'Kuwa wa kwanza kutoa maoni hapa chini.',
    'admin_blog_anonymous': 'Asiyejulikana',
    'admin_blog_failed_post_comment': 'Imeshindwa kutuma maoni',
    'admin_blog_reply': 'Jibu',
    'admin_blog_replying_to_prefix': 'Unajibu',
    'admin_blog_empty_no_posts': 'Hakuna makala za blogu bado',
    'admin_blog_empty_no_drafts': 'Hakuna rasimu bado',
    'admin_blog_empty_hit_new_post':
        'Gusa "Makala Mpya" kuandika makala yako ya kwanza.',
    'admin_blog_empty_try_filter': 'Jaribu kubadilisha kichujio hapo juu.',
    'admin_blog_write_first_post': 'Andika Makala ya Kwanza',

    // Admin Resort Cities
    'admin_resort_title': 'Miji ya Mapumziko',
    'admin_resort_loading': 'Inapakia…',
    'admin_resort_city_singular': 'mji',
    'admin_resort_city_plural': 'miji',
    'admin_resort_total_suffix': 'jumla',
    'admin_resort_filtered_suffix': 'imechujwa',
    'admin_resort_add_city': 'Ongeza Mji wa Mapumziko',
    'admin_resort_search_hint_narrow': 'Tafuta miji…',
    'admin_resort_search_hint_wide': 'Tafuta kwa jina, nchi, mkoa au slug…',
    'admin_resort_filter_all': 'Zote',
    'admin_resort_filter_active': 'Inatumika',
    'admin_resort_filter_inactive': 'Haitumiki',
    'admin_resort_refresh_tooltip': 'Onyesha upya',
    'admin_resort_failed_load': 'Imeshindwa kupakia miji',
    'admin_resort_empty_title': 'Hakuna Miji ya Mapumziko Bado',
    'admin_resort_empty_body':
        'Ongeza mji wako wa kwanza wa mapumziko ili uonekane kwenye programu.',
    'admin_resort_add_first_city': 'Ongeza Mji wa Kwanza',
    'admin_resort_no_match_prefix': 'Hakuna miji inayolingana na',
    'admin_resort_delete_title_prefix': 'Futa',
    'admin_resort_delete_body':
        'Hii itaondoa kabisa mji na maeneo yake yote. Hatua hii haiwezi '
            'kutenguzwa.',
    'admin_resort_snack_deleted_prefix': 'Imefutwa',
    'admin_resort_snack_delete_failed': 'Imeshindwa kufuta mji',
    'admin_resort_snack_now_prefix': 'sasa',
    'admin_resort_snack_created_suffix': 'Imeundwa',
    'admin_resort_snack_updated_suffix': 'Imesasishwa',
    'admin_resort_pop_view_places': 'Angalia Maeneo',
    'admin_resort_pop_view_by_category': 'Angalia kwa Jamii',
    'admin_resort_pop_edit_city': 'Hariri Mji',
    'admin_resort_pop_set_inactive': 'Weka Haitumiki',
    'admin_resort_pop_set_active': 'Weka Inatumika',
    'admin_resort_pop_unfeature_city': 'Ondoa Kuangaziwa',
    'admin_resort_pop_feature_city': 'Angazia Mji',
    'admin_resort_pop_set_sort_order': 'Weka Mpangilio',
    'admin_resort_set_sort_order_title': 'Weka Mpangilio',
    'admin_resort_set_sort_order_hint': 'Nambari ndogo zinaonekana kwanza',
    'admin_resort_edit_city_title': 'Hariri Mji wa Mapumziko',
    'admin_resort_add_city_title': 'Ongeza Mji wa Mapumziko',
    'admin_resort_id_prefix': 'Kitambulisho:',
    'admin_resort_section_basic_info': 'Taarifa za Msingi',
    'admin_resort_section_description': 'Maelezo',
    'admin_resort_section_media': 'Vyombo vya Habari',
    'admin_resort_section_location': 'Kuratibu za Eneo',
    'admin_resort_section_visibility': 'Mwonekano',
    'admin_resort_field_city_name': 'Jina la Mji',
    'admin_resort_field_city_name_hint': 'mfano: Nairobi',
    'admin_resort_error_city_name_required': 'Jina la mji linahitajika',
    'admin_resort_field_country': 'Nchi',
    'admin_resort_field_country_hint': 'mfano: Kenya',
    'admin_resort_field_region': 'Mkoa / Kaunti',
    'admin_resort_field_region_hint': 'mfano: Pwani',
    'admin_resort_error_required': 'Inahitajika',
    'admin_resort_field_slug': 'Slug',
    'admin_resort_field_slug_hint':
        'mfano: nairobi  (huundwa kiotomatiki kutoka jina)',
    'admin_resort_field_slug_helper':
        'Kitambulisho salama cha URL — herufi ndogo, hyphens pekee.',
    'admin_resort_error_slug_required': 'Slug inahitajika',
    'admin_resort_error_slug_format': 'Herufi ndogo, tarakimu na hyphens pekee',
    'admin_resort_field_description': 'Maelezo',
    'admin_resort_field_description_hint':
        'Maelezo mafupi ya mji yanayoonyeshwa kwa watumiaji',
    'admin_resort_error_description_required': 'Maelezo yanahitajika',
    'admin_resort_cover_image_label': 'Picha ya Jalada',
    'admin_resort_select_upload_image': 'Chagua na Pakia Picha',
    'admin_resort_change_image': 'Badilisha Picha',
    'admin_resort_uploading_prefix': 'Inapakia…',
    'admin_resort_field_cover_image_url': 'URL ya Picha ya Jalada',
    'admin_resort_field_cover_image_url_hint':
        'Inajazwa kiotomatiki baada ya kupakia — au bandika URL moja kwa moja',
    'admin_resort_cover_image_uploading_helper':
        'Inapakia picha kwenye Firebase Storage…',
    'admin_resort_cover_image_helper':
        'Chagua picha hapo juu kupakia, au weka URL mwenyewe.',
    'admin_resort_error_url_format': 'Lazima iwe URL kamili inayoanza na http',
    'admin_resort_pick_on_map': 'Chagua kwenye Ramani',
    'admin_resort_map_hint': 'Tafuta kwa jina, gusa ramani, au buruta pini — '
        'au weka kuratibu mwenyewe hapa chini.',
    'admin_resort_field_latitude': 'Latitudo',
    'admin_resort_field_latitude_hint': 'mfano: -1.2921',
    'admin_resort_field_longitude': 'Longitudo',
    'admin_resort_field_longitude_hint': 'mfano: 36.8219',
    'admin_resort_error_must_be_number': 'Lazima iwe nambari',
    'admin_resort_error_lat_range': 'Kati ya -90 na 90',
    'admin_resort_error_lng_range': 'Kati ya -180 na 180',
    'admin_resort_error_valid_number': 'Lazima iwe nambari sahihi',
    'admin_resort_active_visible': 'Inatumika / Inaonekana',
    'admin_resort_visible_desc':
        'Mji umechapishwa na unaonekana kwa watumiaji wanaovinjari.',
    'admin_resort_hidden_desc':
        'Mji umefichwa kutoka kwa watumiaji wanaovinjari.',
    'admin_resort_save_changes': 'Hifadhi Mabadiliko',
    'admin_resort_create_city': 'Unda Mji',
    'admin_resort_error_storage_unavailable':
        'Firebase Storage haipatikani. Angalia uanzishaji wa Firebase.',
    'admin_resort_error_image_upload_prefix': 'Kupakia picha kumeshindwa:',
    'admin_resort_error_unexpected': 'Hitilafu isiyotarajiwa imetokea.',
    'admin_resort_active_badge': 'Inatumika',
    'admin_resort_inactive_badge': 'Haitumiki',
    'admin_resort_stat_places': 'Maeneo',
    'admin_resort_stat_events': 'Matukio',
    'admin_resort_stat_cats': 'Jamii',

    // Admin Place Wizard — navigation chrome (shown on every step)
    'admin_wizard_step_draft': 'Rasimu',
    'admin_wizard_step_location': 'Eneo',
    'admin_wizard_step_contact': 'Mawasiliano',
    'admin_wizard_step_media': 'Vyombo vya Habari',
    'admin_wizard_step_booking': 'Ubunifu',
    'admin_wizard_step_categories': 'Jamii',
    'admin_wizard_step_validate': 'Thibitisha',
    'admin_wizard_step_submit': 'Wasilisha',
    'admin_wizard_step_basic_info_full': 'Taarifa za Msingi',
    'admin_wizard_step_info_short': 'Taarifa',
    'admin_wizard_step_attributes_full': 'Sifa',
    'admin_wizard_step_attrs_short': 'Sifa',
    'admin_wizard_step_nested_data_full': 'Data Ndani',
    'admin_wizard_step_data_short': 'Data',
    'admin_wizard_title_draft': 'Unda Rasimu',
    'admin_wizard_sub_draft': 'Weka jina, mji, na jamii kuu',
    'admin_wizard_title_basic_info': 'Taarifa za Msingi',
    'admin_wizard_sub_basic_info': 'Ongeza maelezo na taarifa za eneo',
    'admin_wizard_sub_location': 'Weka anwani na kuratibu za GPS',
    'admin_wizard_title_contact': 'Maelezo ya Mawasiliano',
    'admin_wizard_sub_contact': 'Ongeza simu, barua pepe, na tovuti',
    'admin_wizard_sub_attributes': 'Ongeza maelezo mahususi ya jamii',
    'admin_wizard_title_media': 'Vyombo vya Habari na Picha',
    'admin_wizard_sub_media': 'Ongeza picha ya jalada na picha za ziada',
    'admin_wizard_title_booking': 'Ubunifu na Bei',
    'admin_wizard_sub_booking': 'Sanidi bei na chaguo za ubunifu',
    'admin_wizard_title_categories': 'Unganisha Jamii',
    'admin_wizard_sub_categories': 'Chagua jamii zote za huduma zinazohusika',
    'admin_wizard_sub_validate': 'Angalia sehemu zinazohitajika zimekamilika',
    'admin_wizard_title_submit_activate': 'Wasilisha na Amilisha',
    'admin_wizard_sub_submit': 'Fanya eneo hili lionekane kwenye programu',
    'admin_wizard_nested_sub_prefix': 'Ongeza',
    'admin_wizard_nested_sub_suffix': 'kwa eneo hili (si lazima)',
    'admin_wizard_btn_back': 'Rudi',
    'admin_wizard_btn_save_exit': 'Hifadhi na Toka',
    'admin_wizard_btn_next': 'Endelea',
    'admin_wizard_btn_save_continue': 'Hifadhi na Endelea',
    'admin_wizard_btn_submit_activate': 'Wasilisha na Amilisha',
    'admin_wizard_saving': 'Inahifadhi…',
    'admin_wizard_next_tooltip': 'Nenda hatua inayofuata bila kuhifadhi',
    'admin_wizard_step_of_prefix': 'Hatua',
    'admin_wizard_step_of_middle': 'kati ya',
    'admin_wizard_tap_segment': 'Gusa sehemu kuruka',
    'admin_wizard_saved_legend': 'Imehifadhiwa',
    'admin_wizard_needs_attention': 'Inahitaji Uangalifu',
    'admin_wizard_incomplete_prefix': 'Haijakamilika:',
    // Step 0 — Draft
    'admin_wizard_error_name_required': 'Jina linahitajika',
    'admin_wizard_error_select_city': 'Chagua mji wa mapumziko',
    'admin_wizard_error_select_category': 'Chagua jamii kuu',
    'admin_wizard_field_place_name': 'Jina la Eneo',
    'admin_wizard_field_place_name_hint': 'mfano: Serena Beach Resort & Spa',
    'admin_wizard_field_resort_city': 'Mji wa Mapumziko',
    'admin_wizard_field_resort_city_hint': 'Chagua mji ulipo eneo hili',
    'admin_wizard_field_primary_category': 'Jamii Kuu',
    'admin_wizard_field_primary_category_desc':
        'Inatumika kubainisha aina ya data ndani inayotumika kwa eneo hili.',
    'admin_wizard_field_primary_category_hint': 'Chagua jamii kuu',
    // Step 10 — Submit
    'admin_wizard_submit_tap_notice':
        'Kugusa "Wasilisha na Amilisha" kutabadilisha eneo hili kutoka '
            'PENDING kwenda ACTIVE, na kulifanya lionekane kwenye programu '
            'kwa watumiaji.',
    'admin_wizard_summary_city_set': 'Mji umewekwa',
    'admin_wizard_summary_categories_suffix': 'jamii',
    'admin_wizard_summary_has_media': 'Ina vyombo vya habari',
    'admin_wizard_summary_no_media': 'Hakuna vyombo vya habari',
    // Common form actions used across the wizard
    'admin_wizard_add_image_url': 'Ongeza URL ya Picha',
    'admin_wizard_remove': 'Ondoa',
    'admin_wizard_select_upload_image': 'Chagua na Pakia Picha',
    'admin_wizard_change_image': 'Badilisha Picha',
    // Step 2 — Basic Info
    'admin_wizard_field_short_desc': 'Maelezo Mafupi',
    'admin_wizard_field_short_desc_hint':
        'Muhtasari wa sentensi moja (upeo herufi 300)',
    'admin_wizard_field_full_desc': 'Maelezo Kamili',
    'admin_wizard_field_full_desc_hint':
        'Maelezo ya kina ya eneo hili (angalau herufi 100)',
    'admin_wizard_field_area': 'Eneo / Mtaa',
    'admin_wizard_field_area_hint': 'mfano: Shanzu, Westlands',
    // Step 3 — Location
    'admin_wizard_location_selected': 'Eneo Limechaguliwa',
    'admin_wizard_pick_on_map': 'Chagua kwenye Ramani',
    'admin_wizard_tap_adjust_pin': 'Gusa kurekebisha nafasi ya pini',
    'admin_wizard_open_map_search':
        'Fungua ramani shirikishi kutafuta na kuweka pini eneo',
    'admin_wizard_adjust_on_map': 'Rekebisha kwenye Ramani',
    'admin_wizard_open_map_picker': 'Fungua Kichagua Ramani',
    'admin_wizard_or_enter_manually': 'au weka mwenyewe',
    'admin_wizard_field_full_address': 'Anwani Kamili',
    'admin_wizard_field_full_address_hint': 'mfano: Shanzu Beach Road, Mombasa',
    'admin_wizard_lat_hint': 'mfano: -3.9875',
    'admin_wizard_lng_hint': 'mfano: 39.7392',
    'admin_wizard_map_tip': 'Kidokezo: Tumia Kichagua Ramani kwa kuratibu sahihi. '
        'Unaweza kutafuta kwa jina la eneo, gusa kwenye ramani, au buruta pini.',
    // Step 4 — Contact
    'admin_wizard_field_phone': 'Nambari ya Simu',
    'admin_wizard_field_email': 'Anwani ya Barua Pepe',
    'admin_wizard_field_website': 'URL ya Tovuti',
    // Step 9 — Categories
    'admin_wizard_categories_info':
        'Chagua kila jamii inayotolewa na eneo hili. Hoteli inayotoa malazi '
            'NA chakula NA ustawi inapaswa kuwa na zote tatu zimechaguliwa.',
    'admin_wizard_category_selected_singular': 'jamii imechaguliwa',
    'admin_wizard_category_selected_plural': 'jamii zimechaguliwa',

    // Place Admin Panel
    'place_admin_panel_back_to_app': 'Rudi kwenye Programu',
    'place_admin_panel_tab_overview': 'Muhtasari',
    'place_admin_panel_tab_bookings': 'Uhifadhi',
    'place_admin_panel_tab_details': 'Maelezo ya Eneo',
    'place_admin_panel_tab_payments': 'Njia za Malipo',
    'place_admin_panel_tab_queries': 'Maswali',
    'place_admin_panel_bookings_overview': 'Muhtasari wa Uhifadhi',
    'place_admin_panel_stat_total': 'Jumla',
    'place_admin_panel_stat_pending': 'Inasubiri',
    'place_admin_panel_stat_confirmed': 'Imethibitishwa',
    'place_admin_panel_stat_completed': 'Imekamilika',
    'place_admin_panel_stat_cancelled': 'Imeghairiwa',
    'place_admin_panel_stat_paid_mpesa': 'Imelipwa kupitia M-Pesa',
    'place_admin_panel_stat_revenue': 'Mapato Yanayokadiriwa',
    'place_admin_panel_edit_title': 'Hariri',
    'place_admin_panel_edit_body':
        'Sasisha picha, maelezo, bei, mipangilio ya uhifadhi na kila kitu kingine kuhusu eneo hili.',
    'place_admin_panel_edit_load_error': 'Imeshindwa kupakia maelezo ya eneo',
    'place_admin_panel_loading': 'Inapakia…',
    'place_admin_panel_edit_button': 'Hariri Maelezo ya Eneo',
    'place_admin_panel_payments_title': 'Njia za Malipo Zinazokubalika',
    'place_admin_panel_payments_subtitle':
        'Chagua ni njia zipi za malipo zilizowekwa kwenye mfumo ambazo eneo hili linakubali.',
    'place_admin_panel_payments_empty_title':
        'Hakuna njia za malipo zilizowekwa',
    'place_admin_panel_payments_empty_body':
        'Muombe MainAdmin aongeze njia za malipo kwenye orodha ya mfumo mzima kwanza.',
    'place_admin_panel_payments_updated': 'Njia za malipo zimesasishwa.',
    'place_admin_panel_saving': 'Inahifadhi…',
    'place_admin_panel_save': 'Hifadhi',
    'place_admin_panel_queries_empty_title': 'Hakuna maswali bado',
    'place_admin_panel_queries_empty_body':
        'Maswali ya watalii kuhusu eneo hili yataonekana hapa.',
    'place_admin_panel_status_answered': 'IMEJIBIWA',
    'place_admin_panel_status_open': 'WAZI',
    'place_admin_panel_your_reply_prefix': 'Jibu lako',
    'place_admin_panel_reply_hint': 'Andika jibu lako…',
    'place_admin_panel_reply_button': 'Jibu',
    'place_admin_panel_send_reply': 'Tuma Jibu',
    'place_admin_panel_sending': 'Inatuma…',

    // Place details — room detail chips
    'place_details_room_balcony': 'Baraza',
    'place_details_room_kitchen': 'Jiko',
    'place_details_room_living_room': 'Sebule',
    'place_details_room_more_amenities': 'zaidi',

    // Place details — menu item detail chips
    'place_details_menu_signature': 'Maalum',
    'place_details_menu_chef_special': 'Kipendwa cha Mpishi',
  };

  static String of(BuildContext context, String key) {
    final isSwahili = AppSettingsScope.of(context).isSwahili;
    if (isSwahili) return _sw[key] ?? _en[key] ?? key;
    return _en[key] ?? key;
  }
}

extension AppStringsX on BuildContext {
  /// Looks up [key] in the active language (English/Swahili), falling back
  /// to English then the raw key if untranslated.
  String tr(String key) => AppStrings.of(this, key);
}
