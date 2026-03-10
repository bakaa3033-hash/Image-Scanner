import 'dart:io';
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
        colorSchemeSeed: Colors.deepPurple,
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorSchemeSeed: Colors.deepPurple,
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
  final String _apiKey = "";

  final ImagePicker picker = ImagePicker();

  Future<void> pickImage(ImageSource source) async {
    // Using max quality to ensure small symbols are not lost in compression
    final pickedFile = await picker.pickImage(
      source: source,
      imageQuality: 100,
    );

    if (pickedFile != null) {
      setState(() {
        imageFile = File(pickedFile.path);
        isScanning = true;
        extractedText = "";
      });
      await processImageWithGemini();
    }
  }

  Future<void> processImageWithGemini() async {
    if (imageFile == null) return;

    try {
      // Using gemini-2.0-flash-exp for superior handwriting and symbol recognition
      final model = GenerativeModel(model: 'gemini-2.0-flash-exp', apiKey: _apiKey);
      final imageBytes = await imageFile!.readAsBytes();
      
      final prompt = TextPart(
          "This image contains isolated, widely separated handwritten characters, numbers, and symbols. "
          "Please identify and extract every single mark you see, including: "
          "- Currency symbols (specifically look for \$, £, €, etc.) "
          "- Individual letters (like 'a', 'b', etc.) "
          "- Numbers (like '1', '0', etc.) "
          "Do not skip any characters just because they are scattered. "
          "Provide only the extracted text exactly as it appears, without any commentary."
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
      // Fallback to ML Kit if Gemini fails or rate limit is hit
      await readTextWithMLKit();
    }
  }

  Future<void> readTextWithMLKit() async {
    if (imageFile == null) return;

    final inputImage = InputImage.fromFile(imageFile!);
    final textRecognizer = TextRecognizer();

    try {
      final RecognizedText recognizedText =
          await textRecognizer.processImage(inputImage);
      setState(() {
        extractedText = recognizedText.text.isEmpty ? "No text recognized." : recognizedText.text;
        isScanning = false;
      });
    } catch (e) {
      setState(() {
        extractedText = "Error occurred: $e";
        isScanning = false;
      });
    } finally {
      textRecognizer.close();
    }
  }

  void copyToClipboard() {
    if (extractedText.isNotEmpty) {
      Clipboard.setData(ClipboardData(text: extractedText));
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Text copied to clipboard!"),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Image Scanner Pro", style: TextStyle(fontWeight: FontWeight.bold)),
        centerTitle: true,
        elevation: 2,
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Image Preview Area
              Container(
                height: 300,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surfaceVariant,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(20),
                  child: imageFile != null
                      ? Image.file(imageFile!, fit: BoxFit.contain)
                      : Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Image.asset(
                                'lib/logo.png',
                                height: 120,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.image_outlined, size: 64, color: Colors.grey),
                              ),
                              const SizedBox(height: 15),
                              const Text(
                                "AI-Powered Scanning",
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w500,
                                  color: Colors.grey,
                                ),
                              ),
                            ],
                          ),
                        ),
                ),
              ),

              const SizedBox(height: 25),

              // Action Buttons
              Row(
                children: [
                  Expanded(
                    child: FilledButton.icon(
                      onPressed: isScanning ? null : () => pickImage(ImageSource.camera),
                      icon: const Icon(Icons.camera_alt),
                      label: const Text("Camera"),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 15),
                  Expanded(
                    child: FilledButton.tonalIcon(
                      onPressed: isScanning ? null : () => pickImage(ImageSource.gallery),
                      icon: const Icon(Icons.photo_library),
                      label: const Text("Gallery"),
                      style: FilledButton.styleFrom(
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 30),

              // Result Section Header
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    "Extracted Text",
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  if (extractedText.isNotEmpty && !isScanning)
                    IconButton.filledTonal(
                      onPressed: copyToClipboard,
                      icon: const Icon(Icons.copy),
                      tooltip: "Copy text",
                    ),
                ],
              ),

              const SizedBox(height: 10),

              // Text Display Area
              Container(
                constraints: const BoxConstraints(minHeight: 150),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(15),
                  border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
                ),
                child: isScanning
                    ? const Center(
                        child: Column(
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 10),
                            Text("AI is processing handwriting & symbols..."),
                          ],
                        ),
                      )
                    : SelectableText(
                        extractedText.isEmpty ? "Tap a button to scan with Gemini 2.0..." : extractedText,
                        style: const TextStyle(fontSize: 16, height: 1.5),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
