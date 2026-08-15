import 'package:csv/csv.dart';

/// CSV/TSV 表格解析（docs/00 §5.3，DOC-105）。
class CsvTable {
  const CsvTable._(this.rows);

  final List<List<String>> rows;

  int get rowCount => rows.length;

  int get columnCount => rows.isEmpty
      ? 0
      : rows.fold<int>(
          0,
          (int m, List<String> r) => r.length > m ? r.length : m,
        );

  static CsvTable parse(String text, {String delimiter = ','}) {
    final CsvDecoder decoder = CsvDecoder(
      fieldDelimiter: delimiter,
      quoteCharacter: '"',
      dynamicTyping: false,
    );
    final List<List<dynamic>> raw = decoder.convert(text);
    final List<List<String>> rows = raw
        .map(
          (List<dynamic> row) =>
              row.map((dynamic cell) => cell.toString()).toList(),
        )
        .toList();
    return CsvTable._(rows);
  }
}
