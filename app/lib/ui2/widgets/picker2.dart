import 'package:flutter/material.dart';

import '../../core/strings.dart';
import '../tokens.dart';

class Picker2Option<T> {
  const Picker2Option(this.label, this.value, {this.sub});
  final String label;
  final String? sub;
  final T value;
}

/// A SEARCHABLE bottom-anchored picker (e.g. "what's being produced?"). Type to
/// filter the options by label or sub. Shown via `nav.overlay(SearchPicker2Sheet(...))`;
/// the caller handles `nav.hideOverlay()` + applying the value in [onPick].
class SearchPicker2Sheet<T> extends StatefulWidget {
  const SearchPicker2Sheet({
    super.key,
    required this.title,
    required this.options,
    required this.onPick,
    this.hint,
  });
  final String title;
  final List<Picker2Option<T>> options;
  final ValueChanged<T> onPick;
  final String? hint;

  @override
  State<SearchPicker2Sheet<T>> createState() => _SearchPicker2SheetState<T>();
}

class _SearchPicker2SheetState<T> extends State<SearchPicker2Sheet<T>> {
  final _c = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final filtered = q.isEmpty
        ? widget.options
        : widget.options
            .where((o) =>
                o.label.toLowerCase().contains(q) ||
                (o.sub?.toLowerCase().contains(q) ?? false))
            .toList();
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxHeight: 480),
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
            decoration:
                BoxDecoration(color: Y2.line, borderRadius: BorderRadius.circular(2)),
          ),
          Text(widget.title, style: F.khand(16, ls: 0.3, color: Y2.ink)),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: Y2.card,
              border: Border.all(color: Y2.line),
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                const Icon(Icons.search, size: 18, color: Y2.muted),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _c,
                    autofocus: true,
                    style: F.hind(15, color: Y2.ink),
                    cursorColor: Y2.accent,
                    onChanged: (v) => setState(() => _q = v),
                    decoration: InputDecoration(
                      isDense: true,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 12),
                      hintText: widget.hint ?? S.t('Search…', 'शोधा…'),
                      hintStyle: F.hind(15, color: Y2.muted2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Flexible(
            child: filtered.isEmpty
                ? Padding(
                    padding: const EdgeInsets.symmetric(vertical: 24),
                    child: Text(S.t('No matches', 'जुळणारे नाही'),
                        textAlign: TextAlign.center,
                        style: F.hind(13, color: Y2.muted)),
                  )
                : ListView.separated(
                    shrinkWrap: true,
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 7),
                    itemBuilder: (context, i) {
                      final o = filtered[i];
                      return GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () => widget.onPick(o.value),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 13, vertical: 12),
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
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: F.hind(15,
                                            w: FontWeight.w600, color: Y2.ink)),
                                    if (o.sub != null)
                                      Text(o.sub!,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
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
