import 'dart:io';
import 'dart:typed_data';

import 'package:anx_reader/service/tts/local/local_tts_model_catalog.dart';
import 'package:anx_reader/service/tts/local/local_tts_model_manager.dart';
import 'package:anx_reader/service/tts/local/wav_encoder.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('localTtsVoiceId / parseLocalTtsVoiceId', () {
    test('round-trips model id and speaker id', () {
      final voiceId = localTtsVoiceId('vits-melo-tts-zh_en', 3);
      expect(voiceId, 'vits-melo-tts-zh_en#3');

      final parsed = parseLocalTtsVoiceId(voiceId);
      expect(parsed, isNotNull);
      expect(parsed!.modelId, 'vits-melo-tts-zh_en');
      expect(parsed.speakerId, 3);
    });

    test('rejects malformed voice ids', () {
      expect(parseLocalTtsVoiceId(''), isNull);
      expect(parseLocalTtsVoiceId('#0'), isNull);
      expect(parseLocalTtsVoiceId('model#'), isNull);
      expect(parseLocalTtsVoiceId('model#abc'), isNull);
      expect(parseLocalTtsVoiceId('model#-1'), isNull);
      expect(parseLocalTtsVoiceId('plain-id'), isNull);
    });

    test('handles model ids containing hashes', () {
      final parsed = parseLocalTtsVoiceId('weird#model#12');
      expect(parsed, isNotNull);
      expect(parsed!.modelId, 'weird#model');
      expect(parsed.speakerId, 12);
    });
  });

  group('kLocalTtsModelCatalog', () {
    test('contains exactly one default model', () {
      final defaults = kLocalTtsModelCatalog.where((e) => e.isDefault);
      expect(defaults.length, 1);
      expect(defaultLocalTtsModel.id, 'vits-melo-tts-zh_en');
    });

    test('model ids are unique and non-empty', () {
      final ids = kLocalTtsModelCatalog.map((e) => e.id).toSet();
      expect(ids.length, kLocalTtsModelCatalog.length);
      for (final id in ids) {
        expect(id.isNotEmpty, isTrue);
        expect(findLocalTtsModel(id), isNotNull);
      }
    });

    test('download urls cover direct GitHub and mirrors', () {
      final urls = downloadUrlsFor(kLocalTtsModelCatalog.first);
      expect(urls.length, kLocalTtsModelMirrorPrefixes.length);
      expect(
        urls.first,
        'https://github.com/k2-fsa/sherpa-onnx/releases/download/tts-models/'
        '${kLocalTtsModelCatalog.first.id}.tar.bz2',
      );
      expect(urls[1], startsWith('https://ghfast.top/https://github.com/'));
      expect(urls[2], startsWith('https://gh-proxy.com/https://github.com/'));
    });
  });

  group('discoverLocalTtsModelFiles', () {
    late Directory tempDir;

    setUp(() async {
      tempDir = await Directory.systemTemp.createTemp('local_tts_test');
    });

    tearDown(() {
      tempDir.deleteSync(recursive: true);
    });

    test('returns null for missing or empty directories', () {
      expect(discoverLocalTtsModelFiles('${tempDir.path}/nope'), isNull);
      expect(discoverLocalTtsModelFiles(tempDir.path), isNull);
    });

    test('discovers a melo-style layout with dict and rule fsts', () {
      final modelDir = Directory('${tempDir.path}/vits-melo-tts-zh_en');
      modelDir.createSync(recursive: true);
      Directory('${modelDir.path}/dict').createSync();
      File('${modelDir.path}/model.onnx').writeAsBytesSync([1, 2, 3]);
      File('${modelDir.path}/tokens.txt').writeAsStringSync('a b c');
      File('${modelDir.path}/lexicon.txt').writeAsStringSync('x');
      File('${modelDir.path}/date.fst').writeAsBytesSync([1]);
      File('${modelDir.path}/number.fst').writeAsBytesSync([2]);

      final files = discoverLocalTtsModelFiles(modelDir.path);
      expect(files, isNotNull);
      expect(files!.modelOnnx, '${modelDir.path}/model.onnx');
      expect(files.tokensTxt, '${modelDir.path}/tokens.txt');
      expect(files.lexicon, '${modelDir.path}/lexicon.txt');
      expect(files.dictDir, '${modelDir.path}/dict');
      expect(files.ruleFsts,
          '${modelDir.path}/date.fst,${modelDir.path}/number.fst');
    });

    test('descends into a single nested directory', () {
      final modelDir = Directory('${tempDir.path}/nested/piper');
      modelDir.createSync(recursive: true);
      File('${modelDir.path}/en_US-amy-medium.onnx').writeAsBytesSync([1]);
      File('${modelDir.path}/tokens.txt').writeAsStringSync('a');
      Directory('${modelDir.path}/espeak-ng-data').createSync();

      final files = discoverLocalTtsModelFiles('${tempDir.path}/nested');
      expect(files, isNotNull);
      expect(files!.modelOnnx, '${modelDir.path}/en_US-amy-medium.onnx');
      expect(files.dataDir, '${modelDir.path}/espeak-ng-data');
      expect(files.lexicon, isNull);
      expect(files.dictDir, isNull);
    });

    test('prefers model.onnx over a vocoder onnx', () {
      final modelDir = Directory('${tempDir.path}/with_vocoder');
      modelDir.createSync(recursive: true);
      File('${modelDir.path}/hifigan_v2.onnx').writeAsBytesSync([1]);
      File('${modelDir.path}/model.onnx').writeAsBytesSync([2]);
      File('${modelDir.path}/tokens.txt').writeAsStringSync('a');

      final files = discoverLocalTtsModelFiles(modelDir.path);
      expect(files!.modelOnnx, '${modelDir.path}/model.onnx');
    });

    test('returns null when tokens.txt is missing', () {
      final modelDir = Directory('${tempDir.path}/no_tokens');
      modelDir.createSync(recursive: true);
      File('${modelDir.path}/model.onnx').writeAsBytesSync([1]);

      expect(discoverLocalTtsModelFiles(modelDir.path), isNull);
    });
  });

  group('encodeWavPcm16', () {
    test('writes a valid RIFF/WAVE header', () {
      final wav = encodeWavPcm16(Float32List.fromList([0.0]), 22050);

      expect(wav.length, 46);
      expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(wav.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(wav.sublist(12, 16)), 'fmt ');
      expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
      final bytes = ByteData.sublistView(wav);
      expect(bytes.getUint32(4, Endian.little), 38); // riff chunk size
      expect(bytes.getUint16(20, Endian.little), 1); // PCM
      expect(bytes.getUint16(22, Endian.little), 1); // mono
      expect(bytes.getUint32(24, Endian.little), 22050); // sample rate
      expect(bytes.getUint32(28, Endian.little), 22050 * 2); // byte rate
      expect(bytes.getUint32(40, Endian.little), 2); // data chunk size
    });

    test('converts samples to clamped 16-bit little-endian PCM', () {
      final wav = encodeWavPcm16(
        Float32List.fromList([0.0, 0.5, -0.5, 2.0, -2.0]),
        44100,
      );

      final bytes = ByteData.sublistView(wav);
      int sampleAt(int index) =>
          bytes.getInt16(44 + index * 2, Endian.little);

      expect(sampleAt(0), 0);
      expect(sampleAt(1), closeTo(32767 * 0.5, 1));
      expect(sampleAt(2), closeTo(-32767 * 0.5, 1));
      expect(sampleAt(3), 32767); // clamped
      expect(sampleAt(4), -32767); // clamped
    });

    test('handles empty samples', () {
      final wav = encodeWavPcm16(Float32List(0), 16000);
      expect(wav.length, 44);
      final bytes = ByteData.sublistView(wav);
      expect(bytes.getUint32(40, Endian.little), 0);
    });
  });
}
