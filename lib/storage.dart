 import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

Future<void> saveEntries(entries) async {
    final prefs = await SharedPreferences.getInstance();
    final list = entries
        .map(
          (e) => jsonEncode({
            "issuer": e.issuer,
            "account": e.account,
            "secret": e.secret,
          }),
        )
        .toList();
    await prefs.setStringList("otp_entries", list);
  }

  