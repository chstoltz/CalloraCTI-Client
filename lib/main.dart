import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await windowManager.ensureInitialized();

  WindowOptions windowOptions = const WindowOptions(
    size: Size(400, 600),
    center: true,
    backgroundColor: Colors.transparent,
    skipTaskbar: false,
    titleBarStyle: TitleBarStyle.normal,
  );
  windowManager.waitUntilReadyToShow(windowOptions, () async {
    await windowManager.show();
    await windowManager.focus();
  });

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'CalloraCTI Desktop Client',
      localizationsDelegates: [
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ],
      supportedLocales: [
        const Locale('de', 'DE'),
        const Locale('en', 'US'),
      ],
      home: const HomePage(),
    );
  }
}

class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  _HomePageState createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> with WindowListener {
  String firstButtonLabel = "Leitung 1";
  Color firstButtonColor = Colors.green;

  List<Map<String, dynamic>> dynamicButtons = [];
  String apiUrl = "";
  String ownExtension = "";

  final TextEditingController _apiUrlController = TextEditingController();
  final TextEditingController _ownExtensionController = TextEditingController();

  late TcpServer server;

 @override
void initState() {
  super.initState();
  _loadSavedSettings();

  windowManager.addListener(this);

  // Server initialisieren
  server = TcpServer(22222);
  server.start(); // Startet den Server ohne Argumente

  // Hinzufügen des Handlers für den "first"-Button
  server.addHandler('first', (String action, String value) {
    handleFirstButton(action, value);
  });
}


  void _loadSavedSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      apiUrl = prefs.getString('apiUrl') ?? '';
      ownExtension = prefs.getString('ownExtension') ?? '';
      _apiUrlController.text = apiUrl;
      _ownExtensionController.text = ownExtension;
    });

    if (apiUrl.isNotEmpty && ownExtension.isNotEmpty) {
      _fetchDynamicButtons();
    }
  }

  void handleFirstButton(String action, String value) {
    setState(() {
      if (action == 'color') {
        firstButtonColor = _getColorFromString(value);
      } else if (action == 'number') {
        firstButtonLabel = value;
      }
    });
  }

  void handleDynamicButton(int index, String action, String value) {
  setState(() {
    if (action == 'color') {
      dynamicButtons[index]['color'] = _getColorFromString(value);
    } else if (action == 'number') {
      dynamicButtons[index]['label'] = value;
    }
  });
}

  Color _getColorFromString(String color) {
    switch (color.toLowerCase()) {
      case 'red':
        return Colors.red;
      case 'yellow':
        return Colors.yellow;
      case 'green':
        return Colors.green;
      default:
        return Colors.green;
    }
  }

  Future<void> _fetchDynamicButtons() async {
  if (apiUrl.isEmpty || ownExtension.isEmpty) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Bitte API-URL und Nebenstelle eingeben!')),
    );
    return;
  }

  try {
    final response = await http.get(Uri.parse('$apiUrl?nst=$ownExtension'));
    if (response.statusCode == 200) {
      // Vor dem Aktualisieren der dynamischen Buttons alte Handler entfernen
      dynamicButtons.forEach((button) {
        server.removeHandler(button['ziel'].toString());
      });

      // Aktualisieren der Buttons basierend auf der API-Antwort
      List<dynamic> responseData = jsonDecode(response.body);
      setState(() {
        dynamicButtons = responseData.map((data) {
          return {
            'ziel': data['ziel'], // Buttonnummer (z.B. 620)
            'label': data['label'],
            'color': Colors.green,
          };
        }).toList();
      });

      // Hinzufügen der neuen TCP-Handler
      for (var button in dynamicButtons) {
        String buttonNumber = button['ziel'].toString();
        server.addHandler(buttonNumber, (String action, String value) {
          int index = dynamicButtons.indexWhere((btn) => btn['ziel'] == buttonNumber);
          if (index != -1) {
            handleDynamicButton(index, action, value);
          }
        });
      }
    } else {
      throw Exception("API Fehler: ${response.statusCode}");
    }
  } catch (e) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Fehler beim Abrufen der Buttons: $e')),
    );
  }
}



  void _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    prefs.setString('apiUrl', apiUrl);
    prefs.setString('ownExtension', ownExtension);
  }

  Future<void> _sendExitRequest() async {
    if (apiUrl.isNotEmpty && ownExtension.isNotEmpty) {
      try {
        final response = await http.get(Uri.parse('$apiUrl?del=$ownExtension'));
        if (response.statusCode == 200) {
          print('Exit-Request erfolgreich gesendet.');
        } else {
          print('Fehler beim Senden des Exit-Requests: ${response.statusCode}');
        }
      } catch (e) {
        print('Fehler beim Senden des Exit-Requests: $e');
      }
    }
  }

  void _showOptionsMenu(BuildContext context) {
    _apiUrlController.text = apiUrl;
    _ownExtensionController.text = ownExtension;

    showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          title: const Text('Einstellungen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: _apiUrlController,
                decoration: const InputDecoration(labelText: 'API-URL'),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: _ownExtensionController,
                decoration: const InputDecoration(labelText: 'Eigene Nebenstelle'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() {
                  apiUrl = _apiUrlController.text;
                  ownExtension = _ownExtensionController.text;
                });
                Navigator.of(dialogContext).pop();
                _fetchDynamicButtons();
                _saveSettings();
              },
              child: const Text('Speichern'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
              },
              child: const Text('Abbrechen'),
            ),
          ],
        );
      },
    );
  }

  void _exitApp() async {
    await _sendExitRequest();
    await windowManager.close();
  }

  @override
  void onWindowClose() async {
    await _sendExitRequest();
    await windowManager.destroy();
  }

  @override
  Widget build(BuildContext context) {
    double buttonWidth = 300;

    return Scaffold(
      appBar: AppBar(
        title: const Text('CalloraCTI'),
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8.0),
                child: Container(
                  width: buttonWidth,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: firstButtonColor,
                      padding: const EdgeInsets.symmetric(vertical: 15),
                    ),
                    onPressed: () {},
                    child: Text(
                      firstButtonLabel,
                      style: const TextStyle(fontSize: 20),
                    ),
                  ),
                ),
              ),
              // Horizontale Linie
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 8.0),
              child: Divider(
                color: Colors.grey, // Farbe der Linie
                thickness: 1,       // Dicke der Linie
                indent: 20,         // Einzug links
                endIndent: 20,      // Einzug rechts
              ),
            ),
              ...dynamicButtons.asMap().entries.map((entry) {
                int index = entry.key;
                Map<String, dynamic> button = entry.value;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: Container(
                    width: buttonWidth,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: button['color'],
                        padding: const EdgeInsets.symmetric(vertical: 15),
                      ),
                      onPressed: () {},
                      child: Text(
                        button['label'],
                        style: const TextStyle(fontSize: 20),
                      ),
                    ),
                  ),
                );
              }).toList(),
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    TextButton(
                      onPressed: () => _showOptionsMenu(context),
                      child: const Text(
                        "Einstellungen",
                        style: TextStyle(fontSize: 20),
                      ),
                    ),
                    const SizedBox(height: 16),
                    ElevatedButton(
                      onPressed: _exitApp,
                      child: const Text(
                        "Beenden",
                        style: TextStyle(fontSize: 18),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    server.stop();
    windowManager.removeListener(this);
    super.dispose();
  }
}

class TcpServer {
  final int port;
  late ServerSocket _serverSocket;
  Map<String, void Function(String, String)> _buttonHandlers = {};

  TcpServer(this.port);

  Future<void> start() async {
    try {
      _serverSocket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      print('Server läuft auf Port $port');

      _serverSocket.listen((Socket client) {
        print('Verbindung von ${client.remoteAddress}:${client.remotePort}');
        client.listen((List<int> data) {
          String message = utf8.decode(data).trim();
          print('Empfangene Nachricht: $message');

          var parts = message.split(' ');
          if (parts.length >= 3) {
            String command = parts[0];
            String action = parts[1];
            String value = parts[2];

            // Handler aufrufen, wenn vorhanden
            if (_buttonHandlers.containsKey(command)) {
              _buttonHandlers[command]!(action, value);
            } else {
              print('Kein Handler für $command gefunden');
            }
          }
        }, onError: (error) {
          print('Fehler bei der Datenübertragung: $error');
        }, onDone: () {
          print('Verbindung geschlossen');
          client.close();
        });
      });
    } catch (e) {
      print('Fehler beim Starten des Servers: $e');
    }
  }

  void addHandler(String buttonNumber, void Function(String, String) handler) {
    _buttonHandlers[buttonNumber] = handler;
  }

  void removeHandler(String buttonNumber) {
    _buttonHandlers.remove(buttonNumber);
  }

  void stop() {
    _serverSocket.close();
  }
}
