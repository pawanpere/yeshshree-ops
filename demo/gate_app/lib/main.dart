// Yeshshree Gate Receiving — demo app shell (Flutter).
// A real Android app that hosts the tested receiving flow. In the Android Studio
// emulator, 10.0.2.2 is an alias for your laptop's localhost, so this reaches the
// Python demo server running there.  Change kServerUrl to your laptop's LAN IP
// (e.g. http://192.168.1.50:8000) if you run it on a PHYSICAL phone over Wi-Fi.
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

const String kServerUrl = 'http://10.0.2.2:8000';

void main() => runApp(const GateApp());

class GateApp extends StatelessWidget {
  const GateApp({super.key});
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Yeshshree Gate',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF0F1720),
      ),
      home: const GateScreen(),
    );
  }
}

class GateScreen extends StatefulWidget {
  const GateScreen({super.key});
  @override
  State<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends State<GateScreen> {
  late final WebViewController _controller;
  bool _loading = true;
  bool _error = false;

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(const Color(0xFF0F1720))
      ..setNavigationDelegate(NavigationDelegate(
        onPageStarted: (_) => setState(() {
          _loading = true;
          _error = false;
        }),
        onPageFinished: (_) => setState(() => _loading = false),
        onWebResourceError: (_) => setState(() {
          _loading = false;
          _error = true;
        }),
      ))
      ..loadRequest(Uri.parse(kServerUrl));
  }

  void _reload() {
    setState(() => _error = false);
    _controller.loadRequest(Uri.parse(kServerUrl));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1F4E78),
        foregroundColor: Colors.white,
        title: const Text('Yeshshree Gate · Receiving',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 17)),
        actions: [
          Container(
            margin: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: const Color(0xFFB00000),
                borderRadius: BorderRadius.circular(4)),
            child: const Text('DEMO',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold)),
          ),
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: Stack(
        children: [
          if (!_error) WebViewWidget(controller: _controller),
          if (_error)
            Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.wifi_off, size: 56, color: Colors.white38),
                    const SizedBox(height: 16),
                    const Text("Can't reach the demo server",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 8),
                    const Text(
                      'Is the Python server running on your laptop?\n'
                      'Start it with --host 0.0.0.0, then tap Retry.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white60),
                    ),
                    const SizedBox(height: 18),
                    FilledButton(onPressed: _reload, child: const Text('Retry')),
                  ],
                ),
              ),
            ),
          if (_loading && !_error)
            const Center(child: CircularProgressIndicator()),
        ],
      ),
    );
  }
}
