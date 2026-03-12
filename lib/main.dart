import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:google_generative_ai/google_generative_ai.dart';

void main() {
  runApp(const ImageScannerApp());
}

class ImageScannerApp extends StatelessWidget {
  const ImageScannerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Image Scanner',
      theme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blueAccent,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.blueAccent,
        brightness: Brightness.dark,
      ),
      home: const ScannerScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen> {
  File? imageFile;
  String extractedText = "";
  bool isScanning = false;
  // Your API Key
  final String _apiKey = "AIzaSyCebFLDRc5d6n6M8L4cRAXJs_jOZGi-BMk"; 

  RecognizedText? _mlKitResult;
  ui.Image? _uiImage;
  final ImagePicker picker = ImagePicker();

  Future<void> pickImage(ImageSource source) async {
    final pickedFile = await picker.pickImage(
      source: source,
      imageQuality: 100,
    );

    if (pickedFile != null) {
      final bytes = await File(pickedFile.path).readAsBytes();
      final codec = await ui.instantiateImageCodec(bytes);
      final frameInfo = await codec.getNextFrame();

      setState(() {
        imageFile = File(pickedFile.path);
        _uiImage = frameInfo.image;
        isScanning = true;
        extractedText = "";
        _mlKitResult = null;
      });

      // Run both: ML Kit for the visual grid, and Background processing for high accuracy
      await Future.wait([
        _processImageInternal(),
        _runMLKitForGrid(),
      ]);
    }
  }

  Future<void> _runMLKitForGrid() async {
    if (imageFile == null) return;
    final inputImage = InputImage.fromFile(imageFile!);
    final textRecognizer = TextRecognizer();
    try {
      final result = await textRecognizer.processImage(inputImage);
      setState(() {
        _mlKitResult = result;
      });
    } finally {
      textRecognizer.close();
    }
  }

  Future<void> _processImageInternal() async {
    if (imageFile == null || _apiKey.isEmpty) return;
    try {
      final model = GenerativeModel(model: 'gemini-1.5-flash', apiKey: _apiKey);
      final imageBytes = await imageFile!.readAsBytes();
      
      // Significantly enhanced prompt for handwritten symbols with escaped $
      final prompt = TextPart(
          "You are a specialized OCR system capable of transcribing messy handwriting and symbols. "
          "Extract EVERY single character and symbol from this image with absolute precision. "
          "Focus intensely on HANDWRITTEN symbols, especially currency signs (\$, £, €, ¥, ₹, etc.), "
          "mathematical symbols (+, -, *, /, =, %, <, >, etc.), and any other special characters. "
          "Transcribe them exactly as they appear in the handwriting. "
          "Maintain the original layout, including indentations, spaces, and line breaks. "
          "Return only the transcribed text. Do not provide any commentary or descriptions."
      );
      
      final imagePart = DataPart('image/jpeg', imageBytes);
      final response = await model.generateContent([
        Content.multi([prompt, imagePart])
      ]);
      
      setState(() {
        extractedText = response.text ?? "No text found.";
        isScanning = false;
      });
    } catch (e) {
      // Fallback to ML Kit results if high-accuracy scan fails
      setState(() {
        if (_mlKitResult != null && _mlKitResult!.text.isNotEmpty) {
          extractedText = _mlKitResult!.text;
        } else {
          extractedText = "No text detected.";
        }
        isScanning = false;
      });
    }
  }

  void _onTapGrid(TapUpDetails details, Size displaySize) {
    if (_mlKitResult == null || _uiImage == null) return;

    final double horizontalScale = displaySize.width / _uiImage!.width;
    final double verticalScale = displaySize.height / _uiImage!.height;

    for (var block in _mlKitResult!.blocks) {
      final rect = Rect.fromLTRB(
        block.boundingBox.left * horizontalScale,
        block.boundingBox.top * verticalScale,
        block.boundingBox.right * horizontalScale,
        block.boundingBox.bottom * verticalScale,
      );

      if (rect.contains(details.localPosition)) {
        Clipboard.setData(ClipboardData(text: block.text));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Copied: ${block.text.split('\n').first}..."),
            backgroundColor: Colors.blueAccent,
            behavior: SnackBarBehavior.floating,
            duration: const Duration(seconds: 1),
          ),
        );
        return;
      }
    }
  }

  void _copyAllText() {
    if (extractedText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: extractedText));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("All text copied to clipboard!"),
          backgroundColor: Colors.blueAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Image Scanner", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          if (extractedText.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.copy_all),
              onPressed: _copyAllText,
              tooltip: "Copy all text",
            ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            children: [
              // Interactive Image Container (The "Grid")
              LayoutBuilder(
                builder: (context, constraints) {
                  double width = constraints.maxWidth;
                  double height = 400;
                  if (_uiImage != null) {
                    double aspectRatio = _uiImage!.width / _uiImage!.height;
                    height = width / aspectRatio;
                    if (height > 500) height = 500;
                  }

                  return Container(
                    height: height,
                    width: width,
                    decoration: BoxDecoration(
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(12),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.1),
                          blurRadius: 10,
                          spreadRadius: 2,
                        )
                      ],
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Stack(
                        children: [
                          if (imageFile != null)
                            Image.file(imageFile!, fit: BoxFit.fill, width: width, height: height),
                          if (imageFile == null)
                            Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.filter_center_focus, size: 64, color: Colors.blueAccent.withOpacity(0.5)),
                                  const SizedBox(height: 16),
                                  const Text("Select an image to scan", style: TextStyle(color: Colors.grey)),
                                ],
                              ),
                            ),

                          // The "Lens" Grid Overlay
                          if (_mlKitResult != null)
                            GestureDetector(
                              onTapUp: (details) => _onTapGrid(details, Size(width, height)),
                              child: CustomPaint(
                                size: Size(width, height),
                                painter: LensGridPainter(result: _mlKitResult!, imageSize: ui.Size(_uiImage!.width.toDouble(), _uiImage!.height.toDouble())),
                              ),
                            ),

                          if (isScanning)
                            Container(
                              color: Colors.black26,
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CircularProgressIndicator(color: Colors.white),
                                    SizedBox(height: 16),
                                    Text("Analyzing image...", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              const SizedBox(height: 20),
              if (imageFile != null)
                const Text("Tap any box in the image to copy specific text", style: TextStyle(fontStyle: FontStyle.italic, color: Colors.grey, fontSize: 12)),
              
              const SizedBox(height: 20),

              Row(
                children: [
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isScanning ? null : () => pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text("Camera"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: ElevatedButton.icon(
                      onPressed: isScanning ? null : () => pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text("Gallery"),
                      style: ElevatedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // Extracted Text Area
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).cardColor,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.blueAccent.withOpacity(0.2)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text("Text Found (Full Scan)", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blueAccent)),
                        if (extractedText.isNotEmpty)
                          IconButton(
                            onPressed: _copyAllText,
                            icon: const Icon(Icons.copy, size: 18),
                            tooltip: "Copy All",
                          ),
                      ],
                    ),
                    const Divider(),
                    if (isScanning)
                      const LinearProgressIndicator(),
                    const SizedBox(height: 8),
                    SelectableText(
                      extractedText.isEmpty ? (isScanning ? "Processing..." : "No text extracted yet.") : extractedText,
                      style: const TextStyle(fontSize: 14, height: 1.6, fontFamily: 'monospace'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 40),
            ],
          ),
        ),
      ),
    );
  }
}

// Painter for the Google Lens style bounding boxes (Cube/Grid effect)
class LensGridPainter extends CustomPainter {
  final RecognizedText result;
  final ui.Size imageSize;

  LensGridPainter({required this.result, required this.imageSize});

  @override
  void paint(Canvas canvas, Size size) {
    final fillPaint = Paint()
      ..style = PaintingStyle.fill
      ..color = Colors.white.withOpacity(0.12);

    final borderPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..color = Colors.white.withOpacity(0.6);

    final double horizontalScale = size.width / imageSize.width;
    final double verticalScale = size.height / imageSize.height;

    for (var block in result.blocks) {
      final rect = Rect.fromLTRB(
        block.boundingBox.left * horizontalScale,
        block.boundingBox.top * verticalScale,
        block.boundingBox.right * horizontalScale,
        block.boundingBox.bottom * verticalScale,
      );

      // Draw cube/grid like box
      final rRect = RRect.fromRectAndRadius(rect, const Radius.circular(2));
      canvas.drawRRect(rRect, fillPaint);
      canvas.drawRRect(rRect, borderPaint);
      
      // Add small corner markers for a more "Lens/Cube" feel
      _drawCornerMarkers(canvas, rect);
    }
  }

  void _drawCornerMarkers(Canvas canvas, Rect rect) {
    final markerPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..color = Colors.white;

    const double len = 6.0;

    // Top Left
    canvas.drawLine(Offset(rect.left, rect.top), Offset(rect.left + len, rect.top), markerPaint);
    canvas.drawLine(Offset(rect.left, rect.top), Offset(rect.left, rect.top + len), markerPaint);

    // Top Right
    canvas.drawLine(Offset(rect.right, rect.top), Offset(rect.right - len, rect.top), markerPaint);
    canvas.drawLine(Offset(rect.right, rect.top), Offset(rect.right, rect.top + len), markerPaint);

    // Bottom Left
    canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.left + len, rect.bottom), markerPaint);
    canvas.drawLine(Offset(rect.left, rect.bottom), Offset(rect.left, rect.bottom - len), markerPaint);

    // Bottom Right
    canvas.drawLine(Offset(rect.right, rect.bottom), Offset(rect.right - len, rect.bottom), markerPaint);
    canvas.drawLine(Offset(rect.right, rect.bottom), Offset(rect.right, rect.bottom - len), markerPaint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
