import 'package:flutter_test/flutter_test.dart';
import 'package:yeshshree_ops/ui2/data/api2.dart';

/// Regression: every demo reject/override reason MUST carry a stable `id`. The
/// reject-reason picker keys options by id, so a null id makes options
/// indistinguishable and leaves reject_reason_id null — which kept "Pick a reject
/// reason" stuck and the Close-shift / Save-interim buttons disabled even after a
/// reason was chosen.
void main() {
  test('every demo reason has a non-null integer id', () {
    expect(Data.demoReasons, isNotEmpty);
    for (final r in Data.demoReasons) {
      expect(r['id'], isA<int>(),
          reason: 'reason ${r['code']} is missing an id');
    }
    // Ids must be distinct so the picker can resolve the tapped option.
    final ids = Data.demoReasons.map((r) => r['id']).toSet();
    expect(ids.length, Data.demoReasons.length);
  });
}
