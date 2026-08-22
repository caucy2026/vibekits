import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../domain/audio_analysis_service.dart';

class AudioDebugWorkspace extends StatefulWidget {
  const AudioDebugWorkspace({super.key, this.initialPath});

  final String? initialPath;

  @override
  State<AudioDebugWorkspace> createState() => _AudioDebugWorkspaceState();
}

class _AudioDebugWorkspaceState extends State<AudioDebugWorkspace> {
  final AudioPlayer _player = AudioPlayer();
  StreamSubscription<PlayerState>? _playerStateSubscription;
  StreamSubscription<Duration>? _positionSubscription;
  AudioAnalysisResult? _result;
  String _path = '';
  String? _previewPath;
  String _message = '';
  bool _busy = false;
  bool _playing = false;
  Duration _position = Duration.zero;
  int _sampleRate = 48000;
  int _channels = 2;
  int _bits = 16;
  bool _signed = true;
  bool _littleEndian = true;

  PcmAudioFormat get _rawFormat => PcmAudioFormat(
    sampleRate: _sampleRate,
    channels: _channels,
    bitsPerSample: _bits,
    signed: _signed,
    littleEndian: _littleEndian,
  );

  @override
  void initState() {
    super.initState();
    _playerStateSubscription = _player.onPlayerStateChanged.listen((
      PlayerState state,
    ) {
      if (mounted) setState(() => _playing = state == PlayerState.playing);
    });
    _positionSubscription = _player.onPositionChanged.listen((Duration value) {
      if (mounted) setState(() => _position = value);
    });
    final String? initialPath = widget.initialPath;
    if (initialPath != null && initialPath.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _analyze(initialPath),
      );
    }
  }

  @override
  void dispose() {
    unawaited(_player.dispose());
    unawaited(_playerStateSubscription?.cancel());
    unawaited(_positionSubscription?.cancel());
    final String? preview = _previewPath;
    if (preview != null) {
      try {
        File(preview).deleteSync();
      } on Object {
        // The OS player may still be releasing the temporary WAV.
      }
    }
    super.dispose();
  }

  Future<void> _pick() async {
    final XFile? file = await openFile(
      acceptedTypeGroups: const <XTypeGroup>[
        XTypeGroup(
          label: 'PCM / WAV 音频',
          extensions: <String>['pcm', 'raw', 'wav', 'wave'],
        ),
      ],
    );
    if (file != null) await _analyze(file.path);
  }

  Future<void> _analyze([String? path]) async {
    final String target = path ?? _path;
    if (target.isEmpty || _busy) return;
    setState(() {
      _busy = true;
      _message = '正在后台分析…';
      _path = target;
    });
    try {
      final AudioAnalysisResult result = await AudioAnalysisService.inspect(
        target,
        rawFormat: _rawFormat,
      );
      if (!mounted) return;
      setState(() {
        _result = result;
        _message = '分析完成 · ${result.frames} 帧';
      });
    } on Object catch (error) {
      if (mounted) setState(() => _message = '$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _togglePlayback() async {
    final AudioAnalysisResult? result = _result;
    if (result == null) return;
    if (_playing) {
      await _player.pause();
      return;
    }
    String playable = result.path;
    if (result.container == 'RAW PCM') {
      final String directory =
          '${File(Platform.resolvedExecutable).parent.path}${Platform.pathSeparator}tmp${Platform.pathSeparator}audio';
      playable =
          '$directory${Platform.pathSeparator}preview_${DateTime.now().microsecondsSinceEpoch}.wav';
      playable = await AudioAnalysisService.pcmToWav(
        result.path,
        playable,
        result.format,
      );
      final String? previous = _previewPath;
      _previewPath = playable;
      if (previous != null && previous != playable) {
        try {
          await File(previous).delete();
        } on Object {
          // Best effort cleanup; app shutdown also removes child playback state.
        }
      }
    }
    await _player.play(DeviceFileSource(playable));
  }

  Future<void> _stopPlayback() async {
    await _player.stop();
    if (mounted) setState(() => _position = Duration.zero);
  }

  @override
  Widget build(BuildContext context) {
    final AudioAnalysisResult? result = _result;
    return Column(
      children: <Widget>[
        _toolbar(result),
        if (_message.isNotEmpty)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            color: Theme.of(context).colorScheme.surfaceContainerHigh,
            child: Text(_message, maxLines: 2, overflow: TextOverflow.ellipsis),
          ),
        Expanded(
          child: result == null
              ? _emptyState()
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: <Widget>[
                    _formatAndMetrics(result),
                    const SizedBox(height: 12),
                    _waveformCard(result),
                    const SizedBox(height: 12),
                    _qualityCard(result),
                    const SizedBox(height: 12),
                    _spectrumCard(result),
                    const SizedBox(height: 12),
                    _findingsCard(result),
                  ],
                ),
        ),
      ],
    );
  }

  Widget _toolbar(AudioAnalysisResult? result) => Container(
    height: 58,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: Theme.of(context).dividerColor)),
    ),
    child: Row(
      children: <Widget>[
        const Icon(Icons.graphic_eq),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            _path.isEmpty ? 'PCM / WAV 波形与声音分析' : _path,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        OutlinedButton.icon(
          onPressed: _busy ? null : _pick,
          icon: const Icon(Icons.audio_file_outlined),
          label: const Text('打开音频'),
        ),
        const SizedBox(width: 8),
        IconButton(
          tooltip: '按当前参数重新分析',
          onPressed: _busy || _path.isEmpty ? null : _analyze,
          icon: const Icon(Icons.refresh),
        ),
        FilledButton.icon(
          key: const Key('audio-play-toggle'),
          onPressed: result == null || _busy ? null : _togglePlayback,
          icon: Icon(_playing ? Icons.pause : Icons.play_arrow),
          label: Text(_playing ? '暂停' : '播放'),
        ),
        IconButton(
          tooltip: '停止并回到开头',
          onPressed: result == null || _busy ? null : _stopPlayback,
          icon: const Icon(Icons.stop),
        ),
      ],
    ),
  );

  Widget _emptyState() => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 650),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: <Widget>[
          const Icon(Icons.multitrack_audio, size: 54),
          const SizedBox(height: 14),
          const Text(
            '打开 PCM 或 WAV，立即看波形、听声音并检查信号质量',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          const Text(
            'RAW PCM 没有格式头，需要在下方选择采样率、声道、位深和字节序；WAV 会自动识别。',
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 18),
          FilledButton.icon(
            onPressed: _pick,
            icon: const Icon(Icons.folder_open),
            label: const Text('选择音频文件'),
          ),
          const SizedBox(height: 20),
          _rawControls(),
        ],
      ),
    ),
  );

  Widget _rawControls() => Wrap(
    spacing: 8,
    runSpacing: 8,
    alignment: WrapAlignment.center,
    children: <Widget>[
      _choice<int>('采样率', _sampleRate, const <int>[
        8000,
        16000,
        32000,
        44100,
        48000,
        96000,
      ], (int value) => setState(() => _sampleRate = value)),
      _choice<int>('声道', _channels, const <int>[
        1,
        2,
        4,
        6,
        8,
      ], (int value) => setState(() => _channels = value)),
      _choice<int>('位深', _bits, const <int>[
        8,
        16,
        24,
        32,
      ], (int value) => setState(() => _bits = value)),
      FilterChip(
        label: Text(_signed ? '有符号' : '无符号'),
        selected: _signed,
        onSelected: (_) => setState(() => _signed = !_signed),
      ),
      FilterChip(
        label: Text(_littleEndian ? '小端 LE' : '大端 BE'),
        selected: _littleEndian,
        onSelected: (_) => setState(() => _littleEndian = !_littleEndian),
      ),
    ],
  );

  Widget _choice<T>(
    String label,
    T value,
    List<T> values,
    ValueChanged<T> changed,
  ) => DropdownButton<T>(
    value: value,
    underline: const SizedBox.shrink(),
    items: values
        .map(
          (T item) =>
              DropdownMenuItem<T>(value: item, child: Text('$label $item')),
        )
        .toList(),
    onChanged: (T? item) {
      if (item != null) changed(item);
    },
  );

  Widget _formatAndMetrics(AudioAnalysisResult result) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  '${result.container} · ${result.format.sampleRate} Hz · ${result.format.channels} ch · ${result.format.bitsPerSample} bit',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(_duration(result.durationSeconds)),
            ],
          ),
          if (result.container == 'RAW PCM') ...<Widget>[
            const Divider(),
            _rawControls(),
          ],
          const Divider(),
          Wrap(
            spacing: 22,
            runSpacing: 8,
            children: <Widget>[
              Text('峰值 ${_db(result.peak.reduce(math.max))} dBFS'),
              Text('RMS ${_db(result.rms.reduce(math.max))} dBFS'),
              Text('削波 ${(result.clippedRatio * 100).toStringAsFixed(3)}%'),
              Text('静音 ${(result.silenceRatio * 100).toStringAsFixed(1)}%'),
              Text('播放 ${_duration(_position.inMilliseconds / 1000)}'),
            ],
          ),
        ],
      ),
    ),
  );

  Widget _waveformCard(AudioAnalysisResult result) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            'PCM 波形',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 10),
          SizedBox(
            height: math.max(160, result.format.channels * 90),
            width: double.infinity,
            child: CustomPaint(
              painter: _WaveformPainter(
                result.waveformMin,
                result.waveformMax,
                Theme.of(context).colorScheme.primary,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _qualityCard(AudioAnalysisResult result) {
    final AudioSignalQuality quality = result.quality;
    final Color scoreColor = quality.score >= 80
        ? Colors.green
        : quality.score >= 60
        ? Colors.orange
        : Colors.red;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              children: <Widget>[
                const Expanded(
                  child: Text(
                    'PCM 质量、谐波与杂讯',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
                Text(
                  '${quality.score} 分',
                  style: TextStyle(
                    color: scoreColor,
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: <Widget>[
                Text('主频 ${quality.dominantFrequencyHz.toStringAsFixed(1)} Hz'),
                Text('THD ${quality.thdPercent.toStringAsFixed(3)}%'),
                Text('THD+N ${quality.thdnPercent.toStringAsFixed(3)}%'),
                Text('估算 SNR ${quality.estimatedSnrDb.toStringAsFixed(1)} dB'),
                Text('噪声底 ${quality.noiseFloorDbfs.toStringAsFixed(1)} dBFS'),
                Text(
                  '有效位数 ${quality.estimatedEffectiveBits.toStringAsFixed(1)} bit',
                ),
                Text(
                  '音调可信度 ${(quality.tonalConfidence * 100).toStringAsFixed(0)}%',
                ),
                if (quality.channelCorrelation != null)
                  Text(
                    '声道相关 ${quality.channelCorrelation!.toStringAsFixed(3)}',
                  ),
              ],
            ),
            const Divider(height: 22),
            Text(
              quality.harmonicsDb.isEmpty
                  ? '未检测到可报告的谐波'
                  : List<String>.generate(
                      quality.harmonicsDb.length,
                      (int index) =>
                          '${index + 2}次 ${quality.harmonicsDb[index].toStringAsFixed(1)} dBc',
                    ).join('  ·  '),
            ),
            const SizedBox(height: 6),
            const Text(
              'THD、THD+N 和 SNR 使用文件开头稳态窗口估算；语音、音乐及扫频信号应结合频谱与波形判断。',
              style: TextStyle(color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spectrumCard(AudioAnalysisResult result) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '频谱快照',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 4),
          const Text('对文件开头窗口执行 Hann 加窗 DFT，用于快速发现频率成分。'),
          const SizedBox(height: 10),
          SizedBox(
            height: 180,
            width: double.infinity,
            child: CustomPaint(
              painter: _SpectrumPainter(
                result.spectrum,
                Theme.of(context).colorScheme.secondary,
              ),
            ),
          ),
        ],
      ),
    ),
  );

  Widget _findingsCard(AudioAnalysisResult result) => Card(
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '信号健康',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          for (final String finding in result.findings)
            ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                finding.startsWith('未发现')
                    ? Icons.check_circle_outline
                    : Icons.warning_amber,
                color: finding.startsWith('未发现') ? Colors.green : Colors.orange,
              ),
              title: Text(finding),
            ),
        ],
      ),
    ),
  );

  static double _db(double value) =>
      value <= 0 ? -120 : 20 * math.log(value) / math.ln10;
  static String _duration(double seconds) {
    final Duration value = Duration(milliseconds: (seconds * 1000).round());
    final String minutes = value.inMinutes.toString().padLeft(2, '0');
    final String remainder = (value.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$remainder.${(value.inMilliseconds % 1000 ~/ 100)}';
  }
}

class _WaveformPainter extends CustomPainter {
  const _WaveformPainter(this.minimum, this.maximum, this.color);
  final List<List<double>> minimum;
  final List<List<double>> maximum;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (minimum.isEmpty || minimum.first.isEmpty) return;
    final Paint grid = Paint()
      ..color = color.withValues(alpha: 0.15)
      ..strokeWidth = 1;
    final Paint wave = Paint()
      ..color = color
      ..strokeWidth = 1;
    final double channelHeight = size.height / minimum.length;
    for (int channel = 0; channel < minimum.length; channel++) {
      final double center = channelHeight * (channel + 0.5);
      canvas.drawLine(Offset(0, center), Offset(size.width, center), grid);
      final int bins = minimum[channel].length;
      for (int index = 0; index < bins; index++) {
        final double x = size.width * index / math.max(1, bins - 1);
        canvas.drawLine(
          Offset(x, center - maximum[channel][index] * channelHeight * 0.46),
          Offset(x, center - minimum[channel][index] * channelHeight * 0.46),
          wave,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _WaveformPainter oldDelegate) =>
      oldDelegate.minimum != minimum || oldDelegate.color != color;
}

class _SpectrumPainter extends CustomPainter {
  const _SpectrumPainter(this.values, this.color);
  final List<double> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.isEmpty) return;
    final double maximum = values
        .reduce(math.max)
        .clamp(0.000001, double.infinity);
    final double width = size.width / values.length;
    final Paint paint = Paint()..color = color;
    for (int index = 0; index < values.length; index++) {
      final double height = values[index] / maximum * size.height;
      canvas.drawRect(
        Rect.fromLTWH(
          index * width,
          size.height - height,
          math.max(1, width - 1),
          height,
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _SpectrumPainter oldDelegate) =>
      oldDelegate.values != values || oldDelegate.color != color;
}
