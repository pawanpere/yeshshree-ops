import 'package:flutter/material.dart';

import '../tokens.dart';

class Picker2Option<T> {
  const Picker2Option(this.label, this.value, {this.sub});
  final String label;
  final String? sub;
  final T value;
}

/// Bottom-anchored option picker, shown inside the phone frame via
/// `nav.overlay(Picker2Sheet(...))`. Calls [onPick] with the chosen value;
/// the caller is responsible for `nav.hideOverlay()` and applying the value.
class Picker2Sheet<T> extends StatelessWidget {
  const Picker2Sheet({
    super.key,
    required this.title,
    required this.options,
    required this.onPick,
  });
  final String title;
  final List<Picker2Option<T>> options;
  final ValueChanged<T> onPick;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 440),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(Y2.rSheet)),
      ),
      padding: const EdgeInsets.fromLTRB(18, 16, 18, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            width: 38,
            height: 4,
            margin: const EdgeInsets.only(bottom: 12),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Y2.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Text(title, style: F.khand(16, ls: 0.3, color: Y2.ink)),
          const SizedBox(height: 10),
          Flexible(
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: options.length,
              separatorBuilder: (_, __) => const SizedBox(height: 7),
              itemBuilder: (context, i) {
                final o = options[i];
                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onPick(o.value),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 13, vertical: 12),
                    decoration: BoxDecoration(
                      color: const Color(0xFFF6F8FB),
                      borderRadius: BorderRadius.circular(11),
                      border: Border.all(color: Y2.line),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(o.label,
                                  style: F.hind(15,
                                      w: FontWeight.w600, color: Y2.ink)),
                              if (o.sub != null)
                                Text(o.sub!,
                                    style: F.hind(11, color: Y2.muted)),
                            ],
                          ),
                        ),
                        Text('›', style: F.hind(16, color: Y2.muted)),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
