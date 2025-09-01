import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lazy_2fa/qr_scanner_screen.dart';
import 'package:otp/otp.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:lazy_2fa/storage.dart';

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class OtpEntry {
  final String issuer;
  final String account;
  final String secret;

  OtpEntry({required this.issuer, required this.account, required this.secret});

  String generateCode() {
    return OTP.generateTOTPCodeString(
      secret,
      DateTime.now().millisecondsSinceEpoch,
      length: 6,
      interval: 30,
      algorithm: Algorithm.SHA1,
      isGoogle: true,
    );
  }
}

class _MyHomePageState extends State<MyHomePage> {
  final List<OtpEntry> entries = [];

  late Timer timer;
  int remaining = 30;

  @override
  void initState() {
    super.initState();
    _loadEntries();
    _startTimer();
  }

  Future<void> _loadEntries() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getStringList("otp_entries") ?? [];
    setState(() {
      entries.clear();
      entries.addAll(
        saved.map((e) {
          final data = jsonDecode(e);
          return OtpEntry(
            issuer: data["issuer"],
            account: data["account"],
            secret: data["secret"],
          );
        }),
      );
    });
  }

  void _startTimer() {
    remaining = 30 - (DateTime.now().second % 30);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      setState(() {
        remaining = 30 - (DateTime.now().second % 30);
      });
    });
  }

  @override
  void dispose() {
    timer.cancel();
    super.dispose();
  }

  String formatOTP(String code) {
    final buffer = StringBuffer();
    for (int i = 0; i < code.length; i++) {
      buffer.write(code[i]);
      if ((i + 1) % 3 == 0 && i != code.length - 1) {
        buffer.write(' ');
      }
    }
    return buffer.toString();
  }

  void _showAddOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: const Text("Scan QR Code"),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) =>
                        QRScannerScreen(onScanned: _addFromQR),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text("Enter details manually"),
              onTap: () {
                Navigator.pop(context);
                _showManualInputDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  void _addFromQR(String data) {
    if (data.startsWith("otpauth://totp/")) {
      final uri = Uri.parse(data);
      final label = uri.pathSegments.isNotEmpty
          ? uri.pathSegments.first
          : "Account";
      final secret = uri.queryParameters["secret"] ?? "";
      final issuer = uri.queryParameters["issuer"] ?? "Unknown";
      setState(() {
        _addToStorage(issuer, label, secret);
      });
    }
  }

  void _addToStorage(final issuer, final label, final secret) {
    final otpElement = OtpEntry(issuer: issuer, account: label, secret: secret);
    if (entries
        .where(
          (ele) =>
              ele.secret == secret &&
              ele.account == label &&
              ele.issuer == issuer,
        )
        .isEmpty) {
      entries.add(otpElement);
      saveEntries(entries);
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Duplicate code: Code already exists"),
          duration: Duration(seconds: 3),
        ),
      );
    }
  }

  void _showManualInputDialog() {
    final issuerController = TextEditingController();
    final accountController = TextEditingController();
    final secretController = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Add Account"),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: issuerController,
              decoration: const InputDecoration(labelText: "Issuer"),
            ),
            TextField(
              controller: accountController,
              decoration: const InputDecoration(labelText: "Account"),
            ),
            TextField(
              controller: secretController,
              decoration: const InputDecoration(labelText: "Secret"),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () {
              if (issuerController.text.isNotEmpty &&
                  accountController.text.isNotEmpty &&
                  secretController.text.isNotEmpty) {
                setState(() {
                  _addToStorage(
                    issuerController.text,
                    accountController.text,
                    secretController.text,
                  );
                });
              }
              Navigator.pop(context);
            },
            child: const Text("Add"),
          ),
        ],
      ),
    );
  }

  Widget _listTileBuilder(index) {
    final entry = entries[index];
    final code = entry.generateCode();

    return ListTile(
      title: Text(
        entry.issuer,
        style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
      ),
      subtitle: Text(entry.account),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          GestureDetector(
            onTap: () {
              Clipboard.setData(ClipboardData(text: code));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text("Code copied to clipboard"),
                  duration: Duration(seconds: 1),
                ),
              );
            },
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 500),
              transitionBuilder: (child, anim) =>
                  FadeTransition(opacity: anim, child: child),
              child: Text(
                formatOTP(code),
                key: ValueKey(code),
                style: const TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.bold,
                  color: Color.fromARGB(255, 5, 91, 161),
                ),
              ),
            ),
          ),
          const SizedBox(width: 15),
          SizedBox(
            width: 10,
            height: 10,
            child: CircularProgressIndicator(
              value: 1 - (remaining / 30),
              strokeWidth: 12,
              backgroundColor: remaining > 5 ? Colors.blue : Colors.red,
              valueColor: AlwaysStoppedAnimation<Color>(
                ThemeData.light().scaffoldBackgroundColor,
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Lazy 2FA")),
      body: ListView.separated(
        itemCount: entries.length,
        separatorBuilder: (context, index) => const Divider(height: 1),
        itemBuilder: (context, index) => _listTileBuilder(index),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _showAddOptions,
        child: const Icon(Icons.add),
      ),
    );
  }
}
