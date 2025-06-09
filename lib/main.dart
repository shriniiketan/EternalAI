import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_sound/flutter_sound.dart';
import 'package:path_provider/path_provider.dart';

void main() => runApp(const MyApp());

class MyApp extends StatelessWidget {
  const MyApp({super.key});
  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Gemini AI Voice/Audio Playground',
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
  // — UI state
  final _promptCtrl = TextEditingController();
  String _responseText = 'Your Gemini API response will appear here.';
  bool _isLoading = false;
  String? _errorMessage;

  // — File picker state
  Uint8List? _selectedAudioData;
  String? _selectedAudioMimeType;

  // — General recording
  final _recorder = FlutterSoundRecorder();
  bool _isRecording = false;
  String? _recordedFilePath;

  // — Target-speaker recording
  final _targetRecorder = FlutterSoundRecorder();
  bool _isTargetRecording = false;
  String? _targetFilePath;

  // — Gemini API config (fill these in!)
  final String _apiKey = 'AIzaSyCMvEw-OApWR6rrTrdRJ36gv7gOKtdVthY';
  final String _geminiModel = 'gemini-2.5-pro-preview-06-05';

  @override
  void initState() {
    super.initState();
    _initAudio();
  }

  Future<void> _initAudio() async {
    await Permission.microphone.request();
    await _recorder.openRecorder();
    await _targetRecorder.openRecorder();
  }

  Future<void> _pickAudioFile() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['m4a', 'wav', 'mp3', 'aac'],
    );
    if (result != null && result.files.single.bytes != null) {
      final ext = result.files.single.extension!;
      setState(() {
        _selectedAudioData = result.files.single.bytes;
        _selectedAudioMimeType = ext == 'wav' ? 'audio/wav' : 'audio/$ext';
        _recordedFilePath = null;
        _targetFilePath = null;
      });
    }
  }

  Future<void> _startGeneralRecording() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/general_record.m4a';
    await _recorder.startRecorder(toFile: path, codec: Codec.aacMP4);
    setState(() {
      _isRecording = true;
      _selectedAudioData = null;
      _selectedAudioMimeType = null;
      _recordedFilePath = path;
    });
  }

  Future<void> _stopGeneralRecording() async {
    await _recorder.stopRecorder();
    setState(() => _isRecording = false);
  }

  Future<void> _startTargetRecording() async {
    final dir = await getTemporaryDirectory();
    final path = '${dir.path}/target_record.m4a';
    await _targetRecorder.startRecorder(toFile: path, codec: Codec.aacMP4);
    setState(() {
      _isTargetRecording = true;
      _selectedAudioData = null;
      _selectedAudioMimeType = null;
      _targetFilePath = path;
    });
  }

  Future<void> _stopTargetRecording() async {
    await _targetRecorder.stopRecorder();
    setState(() => _isTargetRecording = false);
  }

  Future<void> _sendPromptToGemini() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _responseText = 'Generating response...';
    });

    try {
      final parts = <Map<String, dynamic>>[];

      // 1) Text part
      final prompt = _promptCtrl.text.trim();
      if (prompt.isNotEmpty) parts.add({'text': prompt});

      // 2) Audio part (general > target > picked file)
      Uint8List? audioBytes;
      String? mimeType;
      if (_isRecording && _recordedFilePath != null) {
        audioBytes = await File(_recordedFilePath!).readAsBytes();
        mimeType = 'audio/m4a';
      } else if (_isTargetRecording && _targetFilePath != null) {
        audioBytes = await File(_targetFilePath!).readAsBytes();
        mimeType = 'audio/m4a';
      } else if (_selectedAudioData != null && _selectedAudioMimeType != null) {
        audioBytes = _selectedAudioData;
        mimeType = _selectedAudioMimeType;
      }

      if (audioBytes != null && mimeType != null) {
        final b64 = base64Encode(audioBytes);
        parts.add({
          'inlineData': {'mimeType': mimeType, 'data': b64}
        });
      }

      if (parts.isEmpty) {
        setState(() {
          _errorMessage = 'Please enter a prompt or include audio.';
          _isLoading = false;
        });
        return;
      }

      // Build request JSON exactly as in Swift
      final url = Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/$_geminiModel:generateContent?key=$_apiKey');
      final body = jsonEncode({
        'contents': [
          {'role': 'user', 'parts': parts}
        ]
      });

      final res = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: body,
      );

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body);
        final text = json['candidates']?[0]?['content']?['parts']?[0]?['text'];
        setState(() {
          _responseText =
              (text as String?) ?? 'No text found in API response.';
        });
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
      appBar: AppBar(title: const Text('Gemini AI Voice/Audio')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Title
            Text(
              'Gemini AI Voice/Audio Playground',
              style: const TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: Colors.indigo,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),

            // Prompt input
            TextField(
              controller: _promptCtrl,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: 'Enter your prompt',
                border: OutlineInputBorder(),
              ),
              enabled: !_isLoading,
            ),
            const SizedBox(height: 16),

            // File / Recording buttons
            Row(
              children: [
                // Pick from files
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading || _isRecording || _isTargetRecording
                        ? null
                        : _pickAudioFile,
                    icon: const Icon(Icons.folder),
                    label: const Text('Select from Files'),
                  ),
                ),
                const SizedBox(width: 8),

                // General “Record” / “Stop Recording”
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading || _isTargetRecording
                        ? null
                        : () => _isRecording
                        ? _stopGeneralRecording()
                        : _startGeneralRecording(),
                    icon: Icon(_isRecording ? Icons.stop : Icons.mic),
                    label:
                    Text(_isRecording ? 'Stop Recording' : 'Record'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      _isRecording ? Colors.red : Colors.green,
                    ),
                  ),
                ),
                const SizedBox(width: 8),

                // Target-speaker “Start” / “Stop”
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _isLoading || _isRecording
                        ? null
                        : () => _isTargetRecording
                        ? _stopTargetRecording()
                        : _startTargetRecording(),
                    icon: Icon(
                        _isTargetRecording ? Icons.stop : Icons.person),
                    label: Text(_isTargetRecording
                        ? 'Stop Speaker'
                        : 'Target Speaker'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Send button
            ElevatedButton(
              onPressed: _isLoading ? null : _sendPromptToGemini,
              child: _isLoading
                  ? const CircularProgressIndicator(color: Colors.white)
                  : const Text('Send to Gemini'),
            ),
            const SizedBox(height: 16),

            // Error or Response
            if (_errorMessage != null)
              Text(
                _errorMessage!,
                style: const TextStyle(color: Colors.red),
              )
            else
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.indigo.shade200),
                ),
                child: Text(
                  _responseText,
                  style: const TextStyle(color: Colors.black87),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
