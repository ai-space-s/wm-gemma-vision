import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '8BitDo Micro Controller Demo',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const ControllerInputScreen(),
    );
  }
}

class ControllerInputScreen extends StatefulWidget {
  const ControllerInputScreen({super.key});

  @override
  State<ControllerInputScreen> createState() => _ControllerInputScreenState();
}

class _ControllerInputScreenState extends State<ControllerInputScreen> {
  // Position for the moveable object
  double _posX = 200.0;
  double _posY = 200.0;

  // Button states
  Map<String, bool> _buttonStates = {
    'A': false,
    'B': false,
    'X': false,
    'Y': false,
    'Start': false,
    'Select': false,
    'L': false,
    'R': false,
    'Up': false,
    'Down': false,
    'Left': false,
    'Right': false,
    'Heart': false,
  };

  String _lastButtonPressed = 'None';
  final double _moveSpeed = 10.0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('8BitDo Micro Controller')),
      body: KeyboardListener(
        focusNode: FocusNode()..requestFocus(),
        onKeyEvent: _handleKeyEvent,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.grey[100],
          child: Stack(
            children: [
              // Moveable object
              Positioned(
                left: _posX,
                top: _posY,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.blue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.games, color: Colors.white),
                ),
              ),

              // UI overlay
              Positioned(
                top: 10,
                left: 10,
                right: 10,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Last Button: $_lastButtonPressed',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          'Position: (${_posX.toInt()}, ${_posY.toInt()})',
                          style: const TextStyle(fontSize: 16),
                        ),
                        const SizedBox(height: 10),
                        _buildButtonGrid(),
                      ],
                    ),
                  ),
                ),
              ),

              // Instructions
              const Positioned(
                bottom: 20,
                left: 20,
                right: 20,
                child: Card(
                  child: Padding(
                    padding: EdgeInsets.all(16.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Instructions:',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(height: 8),
                        Text(
                          '• D-pad: Move blue circle\n'
                          '• A (G), B (J), X (H), Y (I): Action buttons\n'
                          '• L (K), R (M): Shoulder buttons\n'
                          '• + (O), - (N): Start/Select\n'
                          '• Heart (S): Special button',
                          style: TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildButtonGrid() {
    return Wrap(
      spacing: 8,
      runSpacing: 4,
      children: _buttonStates.entries.map((entry) {
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: entry.value ? Colors.green : Colors.grey[300],
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            entry.key,
            style: TextStyle(
              color: entry.value ? Colors.white : Colors.black,
              fontWeight: FontWeight.bold,
            ),
          ),
        );
      }).toList(),
    );
  }

  void _handleKeyEvent(KeyEvent event) {
    if (event is KeyDownEvent) {
      _handleButtonPress(event.logicalKey);
    } else if (event is KeyUpEvent) {
      _handleButtonRelease(event.logicalKey);
    }
  }

  void _handleButtonPress(LogicalKeyboardKey key) {
    setState(() {
      // Handle D-pad movement
      if (key == LogicalKeyboardKey.arrowUp) {
        _buttonStates['Up'] = true;
        _posY = (_posY - _moveSpeed).clamp(
          0.0,
          MediaQuery.of(context).size.height - 100,
        );
        _lastButtonPressed = 'Up';
      } else if (key == LogicalKeyboardKey.arrowDown) {
        _buttonStates['Down'] = true;
        _posY = (_posY + _moveSpeed).clamp(
          0.0,
          MediaQuery.of(context).size.height - 100,
        );
        _lastButtonPressed = 'Down';
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        _buttonStates['Left'] = true;
        _posX = (_posX - _moveSpeed).clamp(
          0.0,
          MediaQuery.of(context).size.width - 40,
        );
        _lastButtonPressed = 'Left';
      } else if (key == LogicalKeyboardKey.arrowRight) {
        _buttonStates['Right'] = true;
        _posX = (_posX + _moveSpeed).clamp(
          0.0,
          MediaQuery.of(context).size.width - 40,
        );
        _lastButtonPressed = 'Right';
      }
      // Handle action buttons (8BitDo Micro defaults)
      else if (key == LogicalKeyboardKey.keyG) {
        // A button
        _buttonStates['A'] = true;
        _lastButtonPressed = 'A';
      } else if (key == LogicalKeyboardKey.keyJ) {
        // B button
        _buttonStates['B'] = true;
        _lastButtonPressed = 'B';
      } else if (key == LogicalKeyboardKey.keyH) {
        // X button
        _buttonStates['X'] = true;
        _lastButtonPressed = 'X';
      } else if (key == LogicalKeyboardKey.keyI) {
        // Y button
        _buttonStates['Y'] = true;
        _lastButtonPressed = 'Y';
      }
      // Handle shoulder buttons
      else if (key == LogicalKeyboardKey.keyL) {
        // L2 button
        _buttonStates['L'] = true;
        _lastButtonPressed = 'L';
      } else if (key == LogicalKeyboardKey.keyR) {
        // R2 button
        _buttonStates['R'] = true;
        _lastButtonPressed = 'R';
      } else if (key == LogicalKeyboardKey.keyK) {
        // L button
        _buttonStates['L'] = true;
        _lastButtonPressed = 'L';
      } else if (key == LogicalKeyboardKey.keyM) {
        // R button
        _buttonStates['R'] = true;
        _lastButtonPressed = 'R';
      }
      // Handle Start/Select
      else if (key == LogicalKeyboardKey.keyO) {
        // + button (Start)
        _buttonStates['Start'] = true;
        _lastButtonPressed = 'Start';
      } else if (key == LogicalKeyboardKey.keyN) {
        // - button (Select)
        _buttonStates['Select'] = true;
        _lastButtonPressed = 'Select';
      }
      // Handle Heart button
      else if (key == LogicalKeyboardKey.keyS) {
        // Heart button
        _buttonStates['Heart'] = true;
        _lastButtonPressed = 'Heart';
      }
    });
  }

  void _handleButtonRelease(LogicalKeyboardKey key) {
    setState(() {
      // Reset button states when released
      if (key == LogicalKeyboardKey.arrowUp) {
        _buttonStates['Up'] = false;
      } else if (key == LogicalKeyboardKey.arrowDown) {
        _buttonStates['Down'] = false;
      } else if (key == LogicalKeyboardKey.arrowLeft) {
        _buttonStates['Left'] = false;
      } else if (key == LogicalKeyboardKey.arrowRight) {
        _buttonStates['Right'] = false;
      } else if (key == LogicalKeyboardKey.keyG) {
        // A button
        _buttonStates['A'] = false;
      } else if (key == LogicalKeyboardKey.keyJ) {
        // B button
        _buttonStates['B'] = false;
      } else if (key == LogicalKeyboardKey.keyH) {
        // X button
        _buttonStates['X'] = false;
      } else if (key == LogicalKeyboardKey.keyI) {
        // Y button
        _buttonStates['Y'] = false;
      } else if (key == LogicalKeyboardKey.keyL) {
        // L2 button
        _buttonStates['L'] = false;
      } else if (key == LogicalKeyboardKey.keyR) {
        // R2 button
        _buttonStates['R'] = false;
      } else if (key == LogicalKeyboardKey.keyK) {
        // L button
        _buttonStates['L'] = false;
      } else if (key == LogicalKeyboardKey.keyM) {
        // R button
        _buttonStates['R'] = false;
      } else if (key == LogicalKeyboardKey.keyO) {
        // + button (Start)
        _buttonStates['Start'] = false;
      } else if (key == LogicalKeyboardKey.keyN) {
        // - button (Select)
        _buttonStates['Select'] = false;
      } else if (key == LogicalKeyboardKey.keyS) {
        // Heart button
        _buttonStates['Heart'] = false;
      }
    });
  }
}
