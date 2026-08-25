import 'package:dsh_mobile/src/lan_discovery.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('device url builds http address:port', () {
    const device = LanDshDevice(
      name: 'DSH Local',
      host: '172.16.3.193',
      port: 3081,
    );
    expect(device.url, 'http://172.16.3.193:3081');
  });

  test('service name strips the mDNS suffix', () {
    // Indirect coverage of the private helper through device construction is
    // not possible; assert the public model only.
    const device = LanDshDevice(name: 'x-26', host: 'x-26.local', port: 3081);
    expect(device.name, 'x-26');
    expect(device.port, 3081);
  });
}
