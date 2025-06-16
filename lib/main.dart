import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Gemini AI Diarization & Sentiment',
    theme: ThemeData(primarySwatch: Colors.indigo),
    home: const HomePage(),
  );
}

class HomePage extends StatefulWidget {
  const HomePage({super.key});
  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  // — Fixed prompt
  static const String _prompt = '''
We have provided two audio clips:

1) A reference recording of the TARGET SPEAKER.  
2) A conversation audio that may contain multiple voices.

Please:
- Use the target speaker clip as the voice reference for the target speaker.
- Transcribe the recorded conversation audio file and identify the speakers, especially the target speaker.

''';

  // — UI state
  String _responseText = 'Your response will appear here.';
  bool _isLoading = false;
  String? _errorMessage;

  // — Target-speaker upload state
  Uint8List? _targetAudioData;
  String? _targetAudioMimeType;
  String? _targetFileName;

  // — Conversation recording state
  final _recorder = FlutterSoundRecorder();
  bool _isRecording = false;
  String? _recordedFilePath;

  // — Gemini API config
  final String _apiKey = 'AIzaSyAeqZhg3A8eU5XsY_sc4U9_5fIAVwoG_Hk';
  final String _geminiModel = 'gemini-2.0-flash';

  @override
  void initState() {
    super.initState();
    _initRecorder();
  }

  Future<void> _initRecorder() async {
    await Permission.microphone.request();
    await _recorder.openRecorder();
  }

  /// Let user pick target-speaker file
  Future<void> _pickTargetAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m4a', 'wav', 'mp3', 'aac'],
    );
    if (result == null) return;

    final fileObj = result.files.single;
    final path = fileObj.path;
    Uint8List data;

    if (fileObj.bytes != null) {
      data = fileObj.bytes!;
    } else if (path != null) {
      data = await File(path).readAsBytes();
    } else {
      setState(() {
        _errorMessage = 'Picked file has no data or path.';
      });
      return;
    }

    final ext = (fileObj.extension ?? path!.split('.').last).toLowerCase();
    final mime = ext == 'wav'
        ? 'audio/wav'
        : ext == 'm4a'
        ? 'audio/mp4'
        : 'audio/$ext';

    setState(() {
      _targetAudioData = data;
      _targetAudioMimeType = mime;
      _targetFileName = fileObj.name;
      _errorMessage = null;
    });
  }

  /// Start recording the conversation
  Future<void> _startRecording() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/conversation.m4a';
    await _recorder.startRecorder(
      toFile: path,
      codec: Codec.aacMP4,
    );
    setState(() {
      _isRecording = true;
      _recordedFilePath = path;
    });
  }

  /// Stop recording
  Future<void> _stopRecording() async {
    await _recorder.stopRecorder();
    setState(() => _isRecording = false);
    if (_recordedFilePath != null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Saved conversation to:\n$_recordedFilePath'),
          duration: const Duration(seconds: 3),
        ),
      );
    }
  }

  /// Send prompt + target + conversation to Gemini, display & save response
  Future<void> _sendToGemini() async {
    if (_targetAudioData == null) {
      setState(() => _errorMessage = 'Please upload the target speaker audio.');
      return;
    }
    if (_recordedFilePath == null) {
      setState(() =>
      _errorMessage = 'Please record the conversation first.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _responseText = 'Processing…';
    });

    try {
      final parts = <Map<String, dynamic>>[
        {'text': _prompt},
        {
          'inlineData': {
            'mimeType': _targetAudioMimeType!,
            'data': base64Encode(_targetAudioData!),
          }
        },
        {
          'inlineData': {
            'mimeType': 'audio/m4a',
            'data': base64Encode(
                await File(_recordedFilePath!).readAsBytes()),
          }
        },
      ];

      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$_apiKey',
      );
      final body = jsonEncode({
        'contents': [
          {'role': 'user', 'parts': parts}
        ]
      });

      final res = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (res.statusCode == 200) {
        final jsonRes = jsonDecode(res.body);
        final text = jsonRes['candidates']?[0]?['content']?['parts']?[0]?['text']
        as String? ??
            'No text in response.';

        // Update UI
        setState(() => _responseText = text);

        // Save to a .txt file
        final docsDir = await getApplicationDocumentsDirectory();
        final outFile = File('${docsDir.path}/gemini_response.txt');
        await outFile.writeAsString(text);

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Response saved to:\n${outFile.path}'),
            duration: const Duration(seconds: 3),
          ),
        );
      } else {
        setState(() {
          _errorMessage = 'API Error ${res.statusCode}: ${res.body}';
        });
      }
    } catch (e) {
      setState(() {
        _errorMessage = 'Unexpected error: $e';
      });
    } finally {
      setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext ctx) {
    return Scaffold(
      appBar: AppBar(title: const Text('Diarize & Sentiment Analyzer')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // 1) Upload target speaker
            ElevatedButton.icon(
              onPressed: _isLoading ? null : _pickTargetAudioFile,
              icon: const Icon(Icons.upload_file),
              label: Text(_targetFileName == null
                  ? 'Upload Target Speaker Audio'
                  : 'Target: $_targetFileName'),
            ),
            const SizedBox(height: 16),

            // 2) Record conversation
            ElevatedButton.icon(
              onPressed:
              _isLoading ? null : (_isRecording ? _stopRecording : _startRecording),
              icon: Icon(_isRecording ? Icons.stop : Icons.mic),
              label: Text(
                  _isRecording ? 'Stop Recording' : 'Record Conversation'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _isRecording ? Colors.red : Colors.green,
              ),
            ),
            const SizedBox(height: 32),

            // 3) Send to Gemini
            ElevatedButton(
              onPressed: _isLoading ? null : _sendToGemini,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Send to Gemini'),
            ),
            const SizedBox(height: 24),

            // 4) Error or response
            if (_errorMessage != null)
              Text(_errorMessage!, style: const TextStyle(color: Colors.red))
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  border: Border.all(color: Colors.indigo.shade200),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(_responseText),
              ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    _recorder.closeRecorder();
    super.dispose();
  }
}
