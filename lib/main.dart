import 'dart:collection';
import 'dart:ui';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'dart:math';

import 'package:tracer/greeter.dart';
// import 'package:flutter_palette/flutter_palette.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // This widget is the root of your application.
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracer',
      theme: ThemeData(
        // This is the theme of your application.
        //
        // Try running your application with "flutter run". You'll see the
        // application has a blue toolbar. Then, without quitting the app, try
        // changing the primarySwatch below to Colors.green and then invoke
        // "hot reload" (press "r" in the console where you ran "flutter run",
        // or simply save your changes to "hot reload" in a Flutter IDE).
        // Notice that the counter didn't reset back to zero; the application
        // is not restarted.
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Tracer'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, this.title}) : super(key: key);

  // This widget is the home page of your application. It is stateful, meaning
  // that it has a State object (defined below) that contains fields that affect
  // how it looks.

  // This class is the configuration for the state. It holds the values (in this
  // case the title) provided by the parent (in this case the App widget) and
  // used by the build method of the State. Fields in a Widget subclass are
  // always marked "final".

  final String? title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  List<Bar> _bars = [];
  double _zoom = 1.0 / 1e6;
  double _pan = 0;

  void initState() {
    super.initState();
    _setBars();
  }

  void _setBars() {
    setState(() {
      _bars = [];
      // var rng = new Random();
      // for (int j = 0; j < 1000; j += 100) {
      //   for (int i = 0; i < 10; i++) {
      //     int start = rng.nextInt(100) + j;
      //     int end = rng.nextInt(100) + j;
      //     _bars.add(Bar(start * 1e6.toInt(), end * 1e6.toInt(), i.toString()));
      //   }
      // }
      _bars.add(Bar(1 * 1e6.toInt(), 2 * 1e6.toInt(), "TEST"));
    });
  }

  void _updateZoom(double delta) {
    setState(() {
      this._zoom += delta / 1e8;
      this._zoom = max(this._zoom, 1e-8);
    });
  }

  void _updatePan(double delta) {
    setState(() {
      this._pan += delta;
      this._pan = min(this._pan, 40);
    });
  }

  @override
  Widget build(BuildContext context) {
    // This method is rerun every time setState is called, for instance as done
    // by the _incrementCounter method above.
    //
    // The Flutter framework has been optimized to make rerunning build methods
    // fast, so that you can just rebuild anything that needs updating rather
    // than having to individually change instances of widgets.
    return Scaffold(
      appBar: AppBar(),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Expanded(
            child: Listener(
              onPointerMove: (pointerSignal) {
                _updatePan(pointerSignal.delta.dx);
              },
              onPointerSignal: (pointerSignal) {
                if (pointerSignal is PointerScrollEvent) {
                  _updateZoom(pointerSignal.scrollDelta.dy);
                }
              },
              child: CustomPaint(
                painter: OpenPainter(this._bars, this._zoom, this._pan),
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _setBars,
        tooltip: 'Increment',
        child: Icon(Icons.add),
      ),
    );
  }
}

class OpenPainter extends CustomPainter {
  final List<Bar> bars;
  final double zoom;
  final double pan;
  // final ColorPalette palette = ColorPalette.polyad(
  //   Color(0xFF00FFFF),
  //   numberOfColors: 10,
  //   hueVariability: 15,
  //   saturationVariability: 10,
  //   brightnessVariability: 10,
  // );
  final List<Color> palette = [
    Color(0xFF1f77b4),
    Color(0xFFff7f0e),
    Color(0xFF2ca02c),
    Color(0xFFd62728),
    Color(0xFF9467bd),
    Color(0xFF8c564b),
    Color(0xFFe377c2),
    Color(0xFF7f7f7f),
    Color(0xFFbcbd22),
    Color(0xFF17becf),
  ];
  OpenPainter(this.bars, this.zoom, this.pan);

  @override
  void paint(Canvas canvas, Size size) {
    print("Canvas $zoom ${size.toString()}");

    double barHeight = 20;
    double barPadding = 8;
    double offsetTop = 20;

    HashMap<String, EventStyle> isrs = HashMap();

    print("NEW!");
    for (final bar in bars) {
      EventStyle? potIsr = isrs[bar.isr];
      EventStyle isr;
      if (potIsr != null) {
        isr = potIsr;
      } else {
        isr = EventStyle(
            isrs.length,
            Paint()
              ..color = palette[isrs.length]
              ..style = PaintingStyle.fill);
        isrs[bar.isr] = isr;
      }
      double start = bar.startNs.toDouble() * zoom + pan;
      double length = (bar.endNs - bar.startNs).toDouble() * zoom;
      double y = (isr.level.toDouble()) * (barHeight + barPadding) + offsetTop;
      canvas.drawRect(Offset(start, y) & Size(length, barHeight), isr.paint);
      // print("Bar($start -> $length)");
    }

    // var unit = 1e9;
    // for(; unit < 1e-6; unit / 10) {
    //  if(unit * zoom + pan)
    // }

    var widthNs = pxToNs(size.width, zoom);
    var levels = log(widthNs) ~/ log(10);
    print("WIDTH $widthNs");
    print("LEV: $levels");
    print(Greeter.greet("Noah"));

    // var spacing = 1e6 * zoom;
    // print(size.width / spacing);
    // while ((size.width / spacing) > 10) {
    //   spacing /= 10;
    //   print("while");
    // }
    // print("SPACING $spacing");
    for (int i = 0; i < 10; i++) {
      // Draw the grid.
      double divisor = pow(10, levels).toDouble();
      print(divisor);
      double x = i.toDouble() * 1e6 * zoom + pan;
      print(x);
      double y = size.height - 30;
      canvas.drawLine(Offset(x, 0), Offset(x, y), Paint()..color = Colors.grey);

      // Draw the time span annotations.
      var builder = ParagraphBuilder(ParagraphStyle());
      builder.pushStyle(
          TextStyle(fontSize: 18, color: Colors.grey).getTextStyle());
      builder.addText("$i ms");
      var paragraph = builder.build();
      paragraph.layout(ParagraphConstraints(width: double.infinity));
      canvas.drawParagraph(
          paragraph, Offset(x - paragraph.minIntrinsicWidth, y));
    }
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => true;
}

class EventStyle {
  int level;
  Paint paint;

  EventStyle(this.level, this.paint);
}

class Bar {
  int startNs = 0;
  int endNs = 0;
  String isr = "";

  Bar(this.startNs, this.endNs, this.isr);
}

double pxToNs(double px, double zoom) {
  return px / (1e3 * zoom);
}

double nsToPx(double ns, double zoom) {
  return ns * (1e3 * zoom);
}
