import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:dhikra/services/quran_asr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('يكمل التنزيل من حيث انقطع حتى يتمّ الملف سليماً', () async {
    final data = Uint8List.fromList(List.generate(3 * 1024 * 1024, (i) => Random(i).nextInt(256)));
    final sha = sha256.convert(data).toString();
    var requests = 0, ranged = 0;
    // خادم بسيط فوق المقبس مباشرة: كل اتصال يقطع بعد 700 كيلوبايت، كما على شبكة خلوية ضعيفة.
    final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((sock) {
      final buf = BytesBuilder();
      late final StreamSubscription<Uint8List> sub;
      sub = sock.listen((d) async {
        buf.add(d);
        final head = String.fromCharCodes(buf.toBytes());
        if (!head.contains('\r\n\r\n')) return;
        await sub.cancel();
        requests++;
        final m = RegExp(r'[Rr]ange: bytes=(\d+)-').firstMatch(head);
        final from = m == null ? 0 : int.parse(m.group(1)!);
        if (m != null) ranged++;
        final end = min(from + 700 * 1024, data.length);
        sock.add('HTTP/1.1 ${m == null ? '200 OK' : '206 Partial Content'}\r\n'
                'Content-Length: ${data.length - from}\r\nConnection: close\r\n\r\n'
            .codeUnits);
        sock.add(data.sublist(from, end));
        await sock.flush();
        await sock.close();
        sock.destroy();
      });
    });
    final dir = await Directory.systemTemp.createTemp('model');
    final dest = '${dir.path}/m.bin';
    double last = 0;
    final err = await QuranAsrModel.download((p) => last = p,
        from: 'http://127.0.0.1:${server.port}/m.bin',
        to: dest,
        expectedSize: data.length,
        expectedSha: sha,
        retryDelay: Duration.zero);
    await server.close();
    expect(err, isNull);
    expect(File(dest).readAsBytesSync(), data);
    expect(File('$dest.part').existsSync(), isFalse);
    expect(ranged, greaterThanOrEqualTo(4));
    expect(requests, ranged + 1);
    expect(last, 1);
    await dir.delete(recursive: true);
  });
}
