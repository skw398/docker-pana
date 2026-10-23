import 'package:flutter/widgets.dart';

/// Creates a greeting widget for [name].
Widget greeting(String name) =>
    Text('Hello, $name!', textDirection: TextDirection.ltr);
