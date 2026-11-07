import 'package:flutter/widgets.dart';

/// Teks dua bahasa untuk UI baru: Indonesia / Inggris mengikuti locale aktif.
String tr(BuildContext context, String id, String en) =>
    Localizations.localeOf(context).languageCode == 'id' ? id : en;
