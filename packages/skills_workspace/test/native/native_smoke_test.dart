import 'package:skills_workspace/src/native/native_smoke.dart';
import 'package:test/test.dart';

void main() {
  test('loads and invokes the private native smoke ABI', () {
    expect(nativePing(), nativePingExpectedValue);
  });
}
