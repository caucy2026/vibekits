import 'package:flutter_test/flutter_test.dart';
import 'package:vibekits/features/documents/domain/format_router.dart';

void main() {
  test('后缀路由', () {
    expect(documentModeForPath('a.txt'), DocViewMode.text);
    expect(documentModeForPath('A.LOG'), DocViewMode.text);
    expect(documentModeForPath('b.yaml'), DocViewMode.text);
    expect(documentModeForPath('c.md'), DocViewMode.markdown);
    expect(documentModeForPath('d.markdown'), DocViewMode.markdown);
    expect(documentModeForPath('e.bin'), DocViewMode.hex);
    expect(documentModeForPath('f.json'), DocViewMode.structured);
    expect(documentModeForPath('g.csv'), DocViewMode.structured);
    expect(documentModeForPath('h.html'), DocViewMode.web);
    expect(documentModeForPath('i.epub'), DocViewMode.web);
    expect(documentModeForPath('main.dart'), DocViewMode.text);
    expect(documentModeForPath('script.ps1'), DocViewMode.text);
    expect(documentModeForPath('.gitignore'), DocViewMode.text);
    expect(documentModeForPath('j.xyz'), DocViewMode.unsupported);
  });

  test('无后缀视为未知', () {
    expect(documentModeForPath('noext'), DocViewMode.unsupported);
  });
}
