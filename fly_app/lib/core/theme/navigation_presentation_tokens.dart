/// Telegram-iOS source-aligned navigation and search presentation roles.
///
/// NavigationBar and NavigationSearchBar are independent theme families in
/// Telegram-iOS. Keeping them separate from the app-wide semantic palette
/// prevents search, navigation controls and page surfaces from collapsing into
/// one generic Material color set.
library;

import 'package:flutter/material.dart';

@immutable
class NavigationPresentationTokens
    extends ThemeExtension<NavigationPresentationTokens> {
  const NavigationPresentationTokens({
    required this.barBackground,
    required this.button,
    required this.disabledButton,
    required this.primaryText,
    required this.secondaryText,
    required this.control,
    required this.separator,
    required this.searchBackground,
    required this.searchFill,
    required this.searchText,
    required this.searchPlaceholder,
    required this.searchIcon,
    required this.searchClear,
  });

  final Color barBackground;
  final Color button;
  final Color disabledButton;
  final Color primaryText;
  final Color secondaryText;
  final Color control;
  final Color separator;

  final Color searchBackground;
  final Color searchFill;
  final Color searchText;
  final Color searchPlaceholder;
  final Color searchIcon;
  final Color searchClear;

  /// Telegram-iOS DefaultDayPresentationTheme root navigation/search roles.
  /// The app keeps its own cyan-blue brand as the actionable navigation accent.
  static const light = NavigationPresentationTokens(
    barBackground: Color(0xFFFFFFFF),
    button: Color(0xFF24A1DE),
    disabledButton: Color(0xFFD0D0D0),
    primaryText: Color(0xFF000000),
    secondaryText: Color(0xFF787878),
    control: Color(0xFF7E8791),
    separator: Color(0xFFC8C7CC),
    searchBackground: Color(0xFFFFFFFF),
    searchFill: Color(0x0F000000), // black @ 6%
    searchText: Color(0xFF000000),
    searchPlaceholder: Color(0xFF8E8E93),
    searchIcon: Color(0xFF8E8E93),
    searchClear: Color(0xFF7B7B81),
  );

  /// Telegram-iOS DefaultDarkPresentationTheme root navigation/search roles.
  static const dark = NavigationPresentationTokens(
    barBackground: Color(0xE61D1D1D),
    button: Color(0xFFFFFFFF),
    disabledButton: Color(0xFF525252),
    primaryText: Color(0xFFFFFFFF),
    secondaryText: Color(0x80FFFFFF),
    control: Color(0xFF767676),
    separator: Color(0x8C545458), // #545458 @ 55%
    searchBackground: Color(0xFF1C1C1D),
    searchFill: Color(0x1AFFFFFF), // white @ 10%
    searchText: Color(0xFFFFFFFF),
    searchPlaceholder: Color(0xFF8F8F8F),
    searchIcon: Color(0xFF8F8F8F),
    searchClear: Color(0xFF8F8F8F),
  );

  @override
  NavigationPresentationTokens copyWith({
    Color? barBackground,
    Color? button,
    Color? disabledButton,
    Color? primaryText,
    Color? secondaryText,
    Color? control,
    Color? separator,
    Color? searchBackground,
    Color? searchFill,
    Color? searchText,
    Color? searchPlaceholder,
    Color? searchIcon,
    Color? searchClear,
  }) {
    return NavigationPresentationTokens(
      barBackground: barBackground ?? this.barBackground,
      button: button ?? this.button,
      disabledButton: disabledButton ?? this.disabledButton,
      primaryText: primaryText ?? this.primaryText,
      secondaryText: secondaryText ?? this.secondaryText,
      control: control ?? this.control,
      separator: separator ?? this.separator,
      searchBackground: searchBackground ?? this.searchBackground,
      searchFill: searchFill ?? this.searchFill,
      searchText: searchText ?? this.searchText,
      searchPlaceholder: searchPlaceholder ?? this.searchPlaceholder,
      searchIcon: searchIcon ?? this.searchIcon,
      searchClear: searchClear ?? this.searchClear,
    );
  }

  @override
  NavigationPresentationTokens lerp(
    ThemeExtension<NavigationPresentationTokens>? other,
    double t,
  ) {
    if (other is! NavigationPresentationTokens) return this;
    Color c(Color a, Color b) => Color.lerp(a, b, t)!;
    return NavigationPresentationTokens(
      barBackground: c(barBackground, other.barBackground),
      button: c(button, other.button),
      disabledButton: c(disabledButton, other.disabledButton),
      primaryText: c(primaryText, other.primaryText),
      secondaryText: c(secondaryText, other.secondaryText),
      control: c(control, other.control),
      separator: c(separator, other.separator),
      searchBackground: c(searchBackground, other.searchBackground),
      searchFill: c(searchFill, other.searchFill),
      searchText: c(searchText, other.searchText),
      searchPlaceholder: c(searchPlaceholder, other.searchPlaceholder),
      searchIcon: c(searchIcon, other.searchIcon),
      searchClear: c(searchClear, other.searchClear),
    );
  }
}
