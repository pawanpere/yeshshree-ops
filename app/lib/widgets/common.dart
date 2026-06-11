/// Shared UI vocabulary — direct translations of the app map's components:
/// KPI tiles, status badges, bordered cards, alert banners, home tiles, list rows,
/// progress bars. Agents IMPORT these; never redefine them per-feature.
import 'package:flutter/material.dart';

import '../core/theme.dart';

class StatusBadge extends StatelessWidget {
  const StatusBadge(this.label, {super.key, this.kind = 'blue'});
  final String label;
  final String kind;

  @override
  Widget build(BuildContext context) {
    final c = statusColors(kind);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
          color: c.bg, borderRadius: BorderRadius.circular(20)),
      child: Text(label.toUpperCase(),
          style: TextStyle(
              color: c.fg, fontSize: 9.5, fontWeight: FontWeight.w700)),
    );
  }
}

class KpiCard extends StatelessWidget {
  const KpiCard({super.key, required this.label, required this.value,
      this.delta, this.deltaBad = false});
  final String label;
  final String value;
  final String? delta;
  final bool deltaBad;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border.all(color: YColors.line),
        borderRadius: BorderRadius.circular(9),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label.toUpperCase(),
            style: const TextStyle(fontSize: 10, color: YColors.muted,
                letterSpacing: .4)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700,
                color: YColors.navy)),
        if (delta != null)
          Text(delta!,
              style: TextStyle(fontSize: 10,
                  color: deltaBad ? YColors.red : YColors.green)),
      ]),
    );
  }
}

/// Card with the app map's colored left border: urgent/warn/ok/info.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.title, this.meta, this.body,
      this.kind, this.trailing, this.onTap, this.child});
  final String title;
  final String? meta;
  final String? body;
  final String? kind; // urgent|warn|ok|info|null
  final Widget? trailing;
  final VoidCallback? onTap;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final borderColor = switch (kind) {
      'urgent' => YColors.red,
      'warn' => YColors.amber,
      'ok' => YColors.green,
      'info' => YColors.blue,
      _ => null,
    };
    return Card(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(10),
        child: Container(
          decoration: borderColor == null
              ? null
              : BoxDecoration(
                  border: Border(left: BorderSide(color: borderColor, width: 4)),
                  borderRadius: BorderRadius.circular(10),
                ),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(title,
                      style: const TextStyle(fontWeight: FontWeight.w700,
                          fontSize: 13, color: YColors.navy))),
              if (trailing != null) trailing!,
            ]),
            if (meta != null)
              Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Text(meta!,
                    style: const TextStyle(
                        fontSize: 10.5, color: YColors.muted)),
              ),
            if (body != null)
              Padding(
                padding: const EdgeInsets.only(top: 3),
                child: Text(body!,
                    style: const TextStyle(
                        fontSize: 11.5, color: Color(0xFF334155))),
              ),
            if (child != null)
              Padding(padding: const EdgeInsets.only(top: 6), child: child!),
          ]),
        ),
      ),
    );
  }
}

class AlertBanner extends StatelessWidget {
  const AlertBanner({super.key, required this.title, this.body,
      this.kind = 'info'});
  final String title;
  final String? body;
  final String kind; // info|success|warn|danger|purple

  @override
  Widget build(BuildContext context) {
    final c = switch (kind) {
      'success' => (fg: const Color(0xFF14532D), bg: YColors.greenBg, bar: YColors.green),
      'warn' => (fg: const Color(0xFF7C2D12), bg: YColors.amberBg, bar: YColors.amber),
      'danger' => (fg: const Color(0xFF7F1D1D), bg: YColors.redBg, bar: YColors.red),
      'purple' => (fg: const Color(0xFF5B21B6), bg: YColors.purpleBg, bar: YColors.purple),
      _ => (fg: const Color(0xFF1E3A8A), bg: YColors.blueBg, bar: YColors.blue),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
      decoration: BoxDecoration(
        color: c.bg,
        borderRadius: BorderRadius.circular(8),
        border: Border(left: BorderSide(color: c.bar, width: 3)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: TextStyle(color: c.fg, fontWeight: FontWeight.w700,
                fontSize: 11.5)),
        if (body != null)
          Text(body!, style: TextStyle(color: c.fg, fontSize: 11.5)),
      ]),
    );
  }
}

/// Home-screen tile (emoji icon + title + subtitle), 2-per-row grid.
class TileButton extends StatelessWidget {
  const TileButton({super.key, required this.icon, required this.title,
      this.subtitle, this.onTap, this.ribbon});
  final String icon; // emoji, like the app map
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final String? ribbon; // e.g. 'NEW', 'DO NOW'

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Stack(children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: YColors.line),
            boxShadow: const [BoxShadow(color: Color(0x0F0F172A),
                blurRadius: 4, offset: Offset(0, 2))],
          ),
          child: Column(children: [
            Text(icon, style: const TextStyle(fontSize: 24)),
            const SizedBox(height: 5),
            Text(title, textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12,
                    fontWeight: FontWeight.w700, color: YColors.navy)),
            if (subtitle != null)
              Text(subtitle!, textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 9.5, color: YColors.muted)),
          ]),
        ),
        if (ribbon != null)
          Positioned(
            top: 8, right: 8,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(color: YColors.purple,
                  borderRadius: BorderRadius.circular(20)),
              child: Text(ribbon!,
                  style: const TextStyle(color: Colors.white, fontSize: 9,
                      fontWeight: FontWeight.w700)),
            ),
          ),
      ]),
    );
  }
}

class ListRow extends StatelessWidget {
  const ListRow({super.key, required this.title, this.subtitle, this.trailing,
      this.onTap});
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      child: ListTile(
        dense: true,
        onTap: onTap,
        title: Text(title,
            style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12,
                color: YColors.navy)),
        subtitle: subtitle == null
            ? null
            : Text(subtitle!,
                style: const TextStyle(fontSize: 10.5, color: YColors.muted)),
        trailing: trailing,
      ),
    );
  }
}

class ProgressBar extends StatelessWidget {
  const ProgressBar({super.key, required this.fraction});
  final double fraction; // 0..1+

  @override
  Widget build(BuildContext context) {
    final f = fraction.clamp(0.0, 1.0);
    final color = fraction >= 0.9
        ? YColors.green
        : fraction >= 0.8
            ? YColors.amber
            : YColors.red;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: LinearProgressIndicator(
          value: f, minHeight: 8, backgroundColor: YColors.line,
          valueColor: AlwaysStoppedAnimation(color)),
    );
  }
}

/// Standard async snapshot scaffolding: loading / error (localized) / data.
class AsyncBody<T> extends StatelessWidget {
  const AsyncBody({super.key, required this.future, required this.builder,
      this.onRetry});
  final Future<T> future;
  final Widget Function(BuildContext, T) builder;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<T>(
      future: future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          final msg = snap.error.toString();
          return Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Text(msg, textAlign: TextAlign.center,
                  style: const TextStyle(color: YColors.red, fontSize: 12)),
              if (onRetry != null)
                TextButton(onPressed: onRetry, child: const Text('Retry')),
            ]),
          );
        }
        return builder(context, snap.data as T);
      },
    );
  }
}
