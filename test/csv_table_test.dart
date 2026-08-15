import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/documents/domain/csv_table.dart';

void main() {
  test('普通 CSV', () {
    final CsvTable table = CsvTable.parse('a,b\n1,2');
    expect(table.rowCount, 2);
    expect(table.rows[0], <String>['a', 'b']);
    expect(table.rows[1], <String>['1', '2']);
  });

  test('引号、逗号与内嵌换行', () {
    final CsvTable table = CsvTable.parse('"x,y","line1\nline2"\n1,2');
    expect(table.rows[0][0], 'x,y');
    expect(table.rows[0][1], 'line1\nline2');
  });

  test('TSV 分隔', () {
    final CsvTable table = CsvTable.parse('a\tb\n1\t2', delimiter: '\t');
    expect(table.rows[0], <String>['a', 'b']);
    expect(table.rows[1], <String>['1', '2']);
  });
}
