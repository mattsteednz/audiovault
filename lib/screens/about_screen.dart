import 'package:flutter/material.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'licenses_screen.dart';

class AboutScreen extends StatefulWidget {
  const AboutScreen({super.key});

  @override
  State<AboutScreen> createState() => _AboutScreenState();
}

class _AboutScreenState extends State<AboutScreen> {
  String _version = '';

  @override
  void initState() {
    super.initState();
    PackageInfo.fromPlatform().then((info) {
      if (mounted) setState(() => _version = 'Version ${info.version}');
    });
  }

  Future<void> _open(String url) => launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('About AudioVault')),
      body: ListView(
        children: [
          // ── Identity block ────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 32),
            child: Column(
              children: [
                _VaultIcon(size: 80),
                const SizedBox(height: 16),
                Text(
                  'AudioVault',
                  style: theme.textTheme.headlineSmall
                      ?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _version.isEmpty ? '' : _version,
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.55),
                  ),
                ),
              ],
            ),
          ),

          const Divider(),

          // ── Links ─────────────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.language_rounded),
            title: const Text('AudioVault website'),
            subtitle: const Text('audiovault.mattsteed.com'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () => _open('https://audiovault.mattsteed.com'),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          ),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('Privacy policy'),
            subtitle: const Text('How AudioVault handles your data'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () =>
                _open('https://audiovault.mattsteed.com/privacy-policy/'),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          ),
          ListTile(
            leading: const Icon(Icons.code_rounded),
            title: const Text('Source code'),
            subtitle: const Text('github.com/mattsteednz/audiovault'),
            trailing: const Icon(Icons.open_in_new, size: 18),
            onTap: () =>
                _open('https://github.com/mattsteednz/audiovault'),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          ),

          const Divider(),

          // ── Legal ─────────────────────────────────────────────────────────
          ListTile(
            leading: const Icon(Icons.balance_rounded),
            title: const Text('Third-party libraries'),
            subtitle: const Text('Open-source licences'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const LicensesScreen()),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          ),
        ],
      ),
    );
  }
}

// ── Vault icon widget ─────────────────────────────────────────────────────────
// Mirrors the VaultIcon SVG (viewBox 0 0 48 48) from the website.

class _VaultIcon extends StatelessWidget {
  final double size;
  const _VaultIcon({required this.size});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _VaultPainter(),
    );
  }
}

class _VaultPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width / 48; // scale factor from 48-unit viewBox
    final cx = size.width / 2;
    final cy = size.height / 2;

    const bg        = Color(0xFF6B4C9A);
    const light     = Color(0xFFCCB5FF);
    const dashRing  = Color(0xFF8A5EF7);
    const whiteDot  = Color(0xFFF3EEFF);

    // 1. Rounded-rect background
    final bgPaint = Paint()..color = bg;
    final rrect = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, size.width, size.height),
      Radius.circular(12 * s),
    );
    canvas.drawRRect(rrect, bgPaint);

    // Helper: filled circle
    void circle(double r, Color c, {bool stroke = false, double sw = 1}) {
      final p = Paint()
        ..color = c
        ..style = stroke ? PaintingStyle.stroke : PaintingStyle.fill
        ..strokeWidth = sw * s;
      canvas.drawCircle(Offset(cx, cy), r * s, p);
    }

    // 2. Outer ring  r=13, stroke=2.5
    circle(13, light, stroke: true, sw: 2.5);

    // 3. Cardinal tick marks (strokeWidth=2.5, round caps)
    final tickPaint = Paint()
      ..color = light
      ..strokeWidth = 2.5 * s
      ..strokeCap = StrokeCap.round;
    for (final (dx1, dy1, dx2, dy2) in [
      (0.0, -13.0, 0.0, -9.0), // top
      (0.0,  13.0, 0.0,  9.0), // bottom
      (-13.0, 0.0, -9.0, 0.0), // left
      ( 13.0, 0.0,  9.0, 0.0), // right
    ]) {
      canvas.drawLine(
        Offset(cx + dx1 * s, cy + dy1 * s),
        Offset(cx + dx2 * s, cy + dy2 * s),
        tickPaint,
      );
    }

    // 4. Dashed inner ring  r=9, dashArray 2 3
    final dashPaint = Paint()
      ..color = dashRing
      ..strokeWidth = 1 * s
      ..style = PaintingStyle.stroke;
    const r9 = 9.0;
    const dashOn = 2.0;
    const dashOff = 3.0;
    final circum = 2 * 3.141592653589793 * r9;
    var angle = 0.0;
    while (angle < 360) {
      final onDeg  = (dashOn  / circum) * 360;
      final offDeg = (dashOff / circum) * 360;
      canvas.drawArc(
        Rect.fromCircle(center: Offset(cx, cy), radius: r9 * s),
        angle * 3.141592653589793 / 180 - 3.141592653589793 / 2,
        onDeg * 3.141592653589793 / 180,
        false,
        dashPaint,
      );
      angle += onDeg + offDeg;
      if (angle > 360) break;
    }

    // 5. Hub: r=5 filled (light), r=4 punched (bg), r=2 white dot
    circle(5, light);
    circle(4, bg);
    circle(2, whiteDot);
  }

  @override
  bool shouldRepaint(_VaultPainter _) => false;
}
