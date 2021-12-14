import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_ml_kit/google_ml_kit.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

List<CameraDescription> cameras = [];

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CV Test',
      theme: ThemeData.dark(),
      debugShowCheckedModeBanner: false,
      home: const MyHomePage(title: 'CV Test'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {

  CameraController? cameraController;
  InputImage? inputImage;

  late ObjectDetector objectDetector;
  LocalModel model = LocalModel("object_labeler.tflite");

  late EntityExtractor entityExtractor;

  List<DetectedObject> detectedObjects = [];

  bool isBusy = false;

  // 0: back camera
  int cameraIndex = 0;

  SpeechToText sTT = SpeechToText();
  bool speechEnabled = false;
  String engLocaleID = '';

  String commands = '';

  initCamera() async {
    cameraController = CameraController(cameras[cameraIndex], ResolutionPreset.medium);
    await cameraController!.initialize();
    if (mounted) {
      setState(() {
        cameraController!.startImageStream(processCameraImage);
      });
    }
  }

  initSTT() async {
    speechEnabled = await sTT.initialize();
    var locales = await sTT.locales();
    for (var locale in locales) {
      // selecting English locale since the default locale on the tested device is Korean
      if(locale.name == '영어 (세계)') {
        engLocaleID = locale.localeId;
        break;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    objectDetector = GoogleMlKit.vision.objectDetector(CustomObjectDetectorOptions(model, trackMutipleObjects: true, classifyObjects: true));
    // entityExtractor = GoogleMlKit.nlp.entityExtractor(EntityExtractorOptions.ENGLISH);
    initCamera();
    initSTT();
  }

  @override
  void dispose() {
    super.dispose();
    cameraController!.stopImageStream();
    objectDetector.close();
    // entityExtractor.close();
  }

  void startListening() async {
    commands = '';
    if(engLocaleID.isNotEmpty) {
      await sTT.listen(onResult: onSpeechResult, cancelOnError: true, localeId: engLocaleID);
    }
  }

  void stopListening() async {
    await sTT.stop();
  }

  void onSpeechResult(SpeechRecognitionResult result) {
    commands = result.recognizedWords;
  }

  Future<void> processImage(InputImage inputImage) async {
    if (isBusy) return;
    
    isBusy = true;
    
    final result = await objectDetector.processImage(inputImage);
    
    isBusy = false;
    
    if (mounted) {
      setState(() {
        detectedObjects = result;
      });
    }
  }

  Future<void> processCameraImage(CameraImage image) async {
    final WriteBuffer allBytes = WriteBuffer();
    for (Plane plane in image.planes) {
      allBytes.putUint8List(plane.bytes);
    }
    final bytes = allBytes.done().buffer.asUint8List();

    final Size imageSize = Size(image.width.toDouble(), image.height.toDouble());

    final camera = cameras[cameraIndex];
    final imageRotation =
        InputImageRotationMethods.fromRawValue(camera.sensorOrientation) ??
            InputImageRotation.Rotation_0deg;

    final inputImageFormat =
        InputImageFormatMethods.fromRawValue(image.format.raw) ??
            InputImageFormat.YUV420;

    final planeData = image.planes.map(
          (Plane plane) {
        return InputImagePlaneMetadata(
          bytesPerRow: plane.bytesPerRow,
          height: plane.height,
          width: plane.width,
        );
      },
    ).toList();

    final inputImageData = InputImageData(
      size: imageSize,
      imageRotation: imageRotation,
      inputImageFormat: inputImageFormat,
      planeData: planeData,
    );

    inputImage = InputImage.fromBytes(bytes: bytes, inputImageData: inputImageData);
    processImage(inputImage!);
  }

  List<Widget> drawObjectBox() {

    String command = commands.trim();

    return detectedObjects.map((result) {

      String objectText = '';

      bool objectMatch = false;

      if(result.getLabels().isNotEmpty) {

        objectText = '${result.getLabels().first.getText()} ${(result.getLabels().first.getConfidence() * 100).toStringAsFixed(0)}%';

        if(command.isNotEmpty) {
          if(command == 'search all') {
            objectMatch = true;
          }
          else {
            result.getLabels().forEach((label) {
              if(label.getText().trim().toLowerCase().contains(command.substring(command.lastIndexOf(' ') + 1).toLowerCase())) {
                objectMatch = true;
              }
            });
          }
        }
      }

      Color matchColor = objectMatch
        ? Colors.green
        : Colors.red;

      return Positioned(
        left: result.getBoundinBox().left,
        top: result.getBoundinBox().top,
        width: result.getBoundinBox().width,
        height: result.getBoundinBox().height,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: const BorderRadius.all(Radius.circular(10.0)),
            border: Border.all(color: matchColor, width: 2.0),
          ),
          child: Text(
            objectText,
            style: TextStyle(
              color: matchColor,
              fontSize: 18.0,
            ),
          ),
        ),
      );
    }).toList();
  }

  @override
  Widget build(BuildContext context) {

    Size size = MediaQuery.of(context).size;
    List<Widget> list = [];

    list.add(
      Positioned(
        top: 0.0,
        left: 0.0,
        width: size.width,
        height: size.height,
        child: SizedBox(
          height: size.height,
          child: (!cameraController!.value.isInitialized)
            ? Container()
            : AspectRatio(
              aspectRatio: cameraController!.value.aspectRatio,
              child: CameraPreview(cameraController!),
            ),
        ),
      ),
    );

    if (detectedObjects.isNotEmpty) {
      list.addAll(drawObjectBox());
    }

    if(speechEnabled && sTT.isListening) {
      list.add(
        Positioned(
          top: 0.0,
          left: 0.0,
          width: size.width,
          height: size.height,
          child: Container(
            height: size.height,
            color: Colors.black54,
            child: const Center(
              child: CircularProgressIndicator(
                backgroundColor: Colors.transparent,
                color: Colors.blue,
              ),
            ),
          ),
        ),
      );
    }

    if(commands.isNotEmpty && commands.trim() != 'search all') {
      list.add(
        Positioned(
            top: 50,
            left: 0,
            right: 0,
            child: Text(
              commands,
              style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
              ),
              textAlign: TextAlign.center,
            )
        ),
      );
    }

    return SafeArea(
      child: Scaffold(
        backgroundColor: Colors.black,
        body: Container(
          color: Colors.black,
          child: Stack(
            children: list,
          ),
        ),
        floatingActionButton: FloatingActionButton(
          backgroundColor: Colors.blue,
          onPressed: () {
            if(speechEnabled) {
              print('STT isListening = ${sTT.isListening}');
              sTT.isListening ? stopListening() : startListening();
            }
          },
          child: Icon(sTT.isListening ? Icons.mic_off : Icons.mic, color: Colors.white,),
        ),
      ),
    );
  }
}
