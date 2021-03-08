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
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Tracer',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      home: MyHomePage(title: 'Tracer'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, this.title}) : super(key: key);

  final String? title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const double INITIAL_ZOOM = 0.0; // px / ns
  static const double INITIAL_PAN = 0.0; // ns

  List<Bar> _bars = [];
  double _zoom = INITIAL_ZOOM; // px / ns
  double _pan = INITIAL_PAN; // ns

  void initState() {
    super.initState();
    _setBars();
    if (_zoom == INITIAL_ZOOM) {
      _setZoom(1280 / 10); // px / ns
    }
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
      _bars.add(Bar(1 * 1e9.toInt(), 2 * 1e9.toInt(), "sec"));
      _bars.add(Bar(1 * 1e6.toInt(), 2 * 1e6.toInt(), "ms"));
      _bars.add(Bar(1 * 1e3.toInt(), 2 * 1e3.toInt(), "us"));
      _bars.add(Bar(1 * 1e0.toInt(), 2 * 1e0.toInt(), "ns"));
    });
  }

  void _updateZoom(double delta) {
    setState(() {
      this._zoom *= 1 + (delta / 1e2);
      this._zoom = max(this._zoom, 1e-8);
    });
  }

  void _setZoom(double zoom) {
    // px / ns
    setState(() {
      this._zoom = zoom;
      this._zoom = max(this._zoom, 1e-8);
    });
  }

  void _updatePan(double delta) {
    setState(() {
      this._pan += delta / _zoom; // px / (px / ns) = ns
      this._pan = min(this._pan, 0.5);
    });
  }

  void _resetState() {
    _setBars();
    setState(() {
      this._zoom = INITIAL_ZOOM;
      this._pan = INITIAL_PAN;
    });
  }

  @override
  Widget build(BuildContext context) {
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
        onPressed: _resetState,
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
      double start = bar.startNs.toDouble() * zoom + pan * zoom; // ns * px / ns + ns = px
      double length = (bar.endNs - bar.startNs).toDouble() * zoom; // ns * px / ns = px
      double y = (isr.level.toDouble()) * (barHeight + barPadding) + offsetTop; // 1 * px + px
      canvas.drawRect(Offset(start, y) & Size(length, barHeight), isr.paint);
      // print("Bar($start -> $length)");
    }

    // Find the correct spacing of all the bars.
    var spacing = zoom * 1; // px / ns * ns = px
    while (size.width / spacing > 10) {
      // px / px = 1
      spacing *= 10; // px
    }

    // Find the number of digits the current grid numbers have.
    final ns = (spacing / zoom).round().toInt(); // px / (px / ns) = ns

    final y = size.height - 30;
    for (var x = pan * zoom; x < size.width; x += spacing) {
      // Draw the grid.
      canvas.drawLine(Offset(x, 0), Offset(x, y), Paint()..color = Colors.grey);

      // Draw all the grid timescale annotations.

      // Find the number to display.
      var ns = (-pan + x / zoom).round().toInt(); // --ns + px / (px / ns) = ns
      final levels = ns == 0 ? 0 : (log(ns) / log(10)).round().toInt();
      var displayNs = ns.toDouble();
      while (displayNs >= 1000) {
        displayNs /= 1000.0;
      }
      const NAMES = ["ns", "us", "ms", "s"];

      // Display the number and unit for each bar.
      var builder = ParagraphBuilder(ParagraphStyle());
      builder.pushStyle(TextStyle(fontSize: 18, color: Colors.grey).getTextStyle());
      builder.addText("$displayNs ${NAMES[levels ~/ 3]}");
      var paragraph = builder.build();
      paragraph.layout(ParagraphConstraints(width: double.infinity));
      canvas.drawParagraph(paragraph, Offset(x - paragraph.minIntrinsicWidth, y));
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
