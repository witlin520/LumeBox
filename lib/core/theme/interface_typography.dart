import 'package:flutter/material.dart';

class InterfaceTypeStyle extends ThemeExtension<InterfaceTypeStyle> {
  const InterfaceTypeStyle(this.bold);
  final bool bold;
  @override
  InterfaceTypeStyle copyWith({bool? bold}) =>
      InterfaceTypeStyle(bold ?? this.bold);
  @override
  InterfaceTypeStyle lerp(covariant InterfaceTypeStyle? other, double t) =>
      t < .5 ? this : other ?? this;
}

FontWeight interfaceFontWeight(BuildContext context, FontWeight preferred) =>
    Theme.of(context).extension<InterfaceTypeStyle>()?.bold == false &&
        preferred.value > 400
    ? FontWeight.w400
    : preferred;

/// Composes app scaling with the OS scaler (including nonlinear accessibility
/// scaling) instead of replacing it with a linear default.
class InterfaceTextScaler extends TextScaler {
  const InterfaceTextScaler(this.system, this.factor);
  final TextScaler system;
  final double factor;
  @override
  double scale(double fontSize) => system.scale(fontSize) * factor;
  @override
  double get textScaleFactor => scale(14) / 14;
  @override
  bool operator ==(Object other) =>
      other is InterfaceTextScaler &&
      other.system == system &&
      other.factor == factor;
  @override
  int get hashCode => Object.hash(system, factor);
}

/// App font preferences change glyphs only. Geometry may still accommodate
/// the system accessibility scaler, independently of the app's font slider.
TextScaler interfaceLayoutTextScaler(BuildContext context) {
  final scaler = MediaQuery.textScalerOf(context);
  return scaler is InterfaceTextScaler ? scaler.system : scaler;
}

ThemeData interfaceTypography(
  ThemeData theme, {
  String? family,
  bool bold = true,
  bool italic = false,
}) {
  if (family == null && bold && !italic) return theme;
  TextStyle? style(TextStyle? value) => value?.copyWith(
    fontFamily: family,
    fontWeight: !bold && (value.fontWeight?.value ?? 400) > 400
        ? FontWeight.w400
        : value.fontWeight,
    fontStyle: italic ? FontStyle.italic : FontStyle.normal,
  );
  TextTheme texts(TextTheme value) => TextTheme(
    displayLarge: style(value.displayLarge),
    displayMedium: style(value.displayMedium),
    displaySmall: style(value.displaySmall),
    headlineLarge: style(value.headlineLarge),
    headlineMedium: style(value.headlineMedium),
    headlineSmall: style(value.headlineSmall),
    titleLarge: style(value.titleLarge),
    titleMedium: style(value.titleMedium),
    titleSmall: style(value.titleSmall),
    bodyLarge: style(value.bodyLarge),
    bodyMedium: style(value.bodyMedium),
    bodySmall: style(value.bodySmall),
    labelLarge: style(value.labelLarge),
    labelMedium: style(value.labelMedium),
    labelSmall: style(value.labelSmall),
  );
  ButtonStyle? button(ButtonStyle? value) => value?.copyWith(
    textStyle: WidgetStateProperty.resolveWith(
      (states) => style(value.textStyle?.resolve(states)),
    ),
  );
  return theme.copyWith(
    extensions: [
      ...theme.extensions.values.where((value) => value is! InterfaceTypeStyle),
      InterfaceTypeStyle(bold),
    ],
    textTheme: texts(theme.textTheme),
    primaryTextTheme: texts(theme.primaryTextTheme),
    appBarTheme: theme.appBarTheme.copyWith(
      titleTextStyle: style(theme.appBarTheme.titleTextStyle),
      toolbarTextStyle: style(theme.appBarTheme.toolbarTextStyle),
    ),
    dialogTheme: theme.dialogTheme.copyWith(
      titleTextStyle: style(theme.dialogTheme.titleTextStyle),
      contentTextStyle: style(theme.dialogTheme.contentTextStyle),
    ),
    listTileTheme: theme.listTileTheme.copyWith(
      titleTextStyle: style(theme.listTileTheme.titleTextStyle),
      subtitleTextStyle: style(theme.listTileTheme.subtitleTextStyle),
      leadingAndTrailingTextStyle: style(
        theme.listTileTheme.leadingAndTrailingTextStyle,
      ),
    ),
    tabBarTheme: theme.tabBarTheme.copyWith(
      labelStyle: style(theme.tabBarTheme.labelStyle),
      unselectedLabelStyle: style(theme.tabBarTheme.unselectedLabelStyle),
    ),
    textButtonTheme: TextButtonThemeData(
      style: button(theme.textButtonTheme.style),
    ),
    elevatedButtonTheme: ElevatedButtonThemeData(
      style: button(theme.elevatedButtonTheme.style),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: button(theme.filledButtonTheme.style),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: button(theme.outlinedButtonTheme.style),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: button(theme.segmentedButtonTheme.style),
    ),
    snackBarTheme: theme.snackBarTheme.copyWith(
      contentTextStyle: style(theme.snackBarTheme.contentTextStyle),
    ),
    popupMenuTheme: theme.popupMenuTheme.copyWith(
      textStyle: style(theme.popupMenuTheme.textStyle),
    ),
    tooltipTheme: theme.tooltipTheme.copyWith(
      textStyle: style(theme.tooltipTheme.textStyle),
    ),
  );
}
