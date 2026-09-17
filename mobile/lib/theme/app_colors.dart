import 'package:flutter/material.dart';

/// かめすらのブランドカラー。亀の甲羅の緑とスライムの青の2色を基調にする。
/// 個別の画面で新しい色を増やす前に、まずここへ集約する。
class AppColors {
  const AppColors._();

  /// 甲羅の緑（プライマリ）。
  static const turtleGreen = Color(0xFF2FA36B);
  static const turtleGreenDark = Color(0xFF123B2C);
  static const turtleGreenTint = Color(0xFFE6F7EF);

  /// スライムの青（セカンダリ／アクセント）。
  static const slimeBlue = Color(0xFF3E8EDE);
  static const slimeBlueDark = Color(0xFF0B2A45);
}
