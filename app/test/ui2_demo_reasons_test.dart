import 'package:flutter_test/flutter_test.dart';
import 'package:yeshshree_ops/ui2/data/api2.dart';

/// Regression: every demo reject/override reason MUST carry a stable `id`. The
/// reject-reason picker keys options by id, so a null id makes options
/// indistinguishable and leaves reject_reason_id null — which kept "Pick a reject
/// reason" stuck and the Close-shift / Save-interim buttons disabled even after a
/// reason was chosen.
void main() {
  // Every master list shown in a picker must carry stable, distinct ids: a null
  // id makes options indistinguishable AND leaves an id-gated CTA disabled (this
  // bit the reject-reason picker, the issue-material picker, and would have bitten
  // customers/vendors next).
  final lists = <String, List<Map<String, dynamic>>>{
    'demoReasons': Data.demoReasons,
    'demoMaterials': Data.demoMaterials,
    'demoCustomers': Data.demoCustomers,
    'demoVendors': Data.demoVendors,
    'demoLines': Data.demoLines,
  };

  lists.forEach((name, rows) {
    test('$name rows all have a distinct non-null integer id', () {
      expect(rows, isNotEmpty, reason: '$name is empty');
      for (final r in rows) {
        expect(r['id'], isA<int>(), reason: '$name row $r is missing an id');
      }
      final ids = rows.map((r) => r['id']).toSet();
      expect(ids.length, rows.length, reason: '$name has duplicate ids');
    });
  });
}
