import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:wakelock/wakelock.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bluetooth_serial/flutter_bluetooth_serial.dart';

import 'DiscoveryPage.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  // Create a global key for navigation
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Eng & Life',
      theme: ThemeData(
        primarySwatch: Colors.blue,
      ),
      navigatorKey: navigatorKey, // Assign the navigator key
      home: MyHomePage(title: 'Eng & Life'),
    );
  }
}

class MyHomePage extends StatefulWidget {
  MyHomePage({Key? key, required this.title}) : super(key: key);

  final String title;

  @override
  _MyHomePageState createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> with TickerProviderStateMixin {
  bool isACK = false; // Variável global
  String calibracao = ''; // Adicione essa linha
  int dia = 0;
  int mes = 0;
  int ano = 0;
  int hora = 0;
  int minuto = 0;
  int segundo = 0;

  Completer<void> ackCompleter = Completer<void>();
  Uint8List? encodedMessage; // Variável para armazenar a mensagem codificada

  // Tab controller for switching between tabs
  late TabController _tabController;
// Declaração da variável de controle
  bool reenviarMensagem = false; // Variável de controle para reenvio de mensagem

  //Lista para escutar o que o ESP enviar
  List<String> _receivedMessages = [];

  // Bluetooth state
  BluetoothState _bluetoothState = BluetoothState.UNKNOWN;

  // List of discovered devices
  List<BluetoothDevice> _devicesList = [];

  // Declare the TextEditingController
  TextEditingController _messageTextFieldController = TextEditingController();

  // Connected device
  BluetoothDevice? _connectedDevice;

  // Connection with the device
  BluetoothConnection? connection;

  // Flag to indicate if device is still connected
  bool get isConnected => connection != null && connection!.isConnected;

  // Flag to indicate if device is still listening
  bool isListening = false;

// Declare a stream subscription for discovery events
  StreamSubscription<BluetoothDiscoveryResult>? _streamSubscription;

  String _connectedDeviceName = '';

  @override
  void initState() {
    super.initState();
    Wakelock.enable();
    // Initialize tab controller
    _tabController = TabController(length: 3, vsync: this);

    // Add a listener to the tab controller
    _tabController.addListener(() {
      // Get the current tab index
      int currentIndex = _tabController.index;

      // Check if the current tab is the Bluetooth tab
      if (currentIndex >= 0) {
        // Start discovery of devices
        _refreshList();
      }
    });

    // Get current state of Bluetooth
    FlutterBluetoothSerial.instance.state.then((state) {
      setState(() {
        _bluetoothState = state;
      });
    });

    // Listen for state changes of Bluetooth
    FlutterBluetoothSerial.instance
        .onStateChanged()
        .listen((BluetoothState state) {
      setState(() {
        _bluetoothState = state;
        if (_bluetoothState == BluetoothState.STATE_OFF) {
          // Turn off Bluetooth
          _disconnect();
          _showToast(context, 'Bluetooth desativado');
        } else if (_bluetoothState == BluetoothState.STATE_ON) {
          // Turn on Bluetooth
          _showToast(context, 'Bluetooth ativado');
          // Start discovery of devices
          //_startDiscovery();
        }
      });
    });
  }

  void _navigateToDiscoveryPage() async {
    final BluetoothDevice? selectedDevice = await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) {
          return DiscoveryPage();
        },
      ),
    );

    if (selectedDevice != null) {
      print('Discovery -> selected ' + selectedDevice.address);
    } else {
      print('Discovery -> no device selected');
    }

    _refreshList(); // Atualiza a lista de dispositivos
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Get the current tab index
    int currentIndex = _tabController.index;

    // Check if the current tab is the Bluetooth tab
    if (currentIndex == 0) {
      // Start discovery of devices
      _refreshList();
    }
  }

  @override
  void dispose() {
    // Dispose tab controller

    FocusScope.of(context).unfocus(); // Desfoca a caixa de texto

    // Dispose connection
    if (isConnected) {
      connection!.dispose();
      connection = null;
    }
    // Stop discovery
    _stopDiscovery();
    _tabController.dispose();
    _messageTextFieldController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        elevation: 5,
        title: Center(
          child: Text(
            widget.title,
            textAlign: TextAlign.center, // Centralize o título
          ),
        ),
        bottom: TabBar(
          controller: _tabController,
          tabs: [
            Tab(icon: Icon(Icons.bluetooth), text: 'Bluetooth'),
            Tab(icon: Icon(Icons.settings), text: 'A300'),
            Tab(icon: Icon(Icons.file_upload), text: 'Controle'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildBluetoothTab(),
          _buildA300Tab(),
          _buildControleTab(),
        ],
      ),
    );
  }

// Method to stop discovery
  void _stopDiscovery() async {
    // Cancel the stream subscription if not null
    if (_streamSubscription != null) {
      await _streamSubscription!.cancel();
      _streamSubscription = null;
    }
  }

  // Method to connect to a device
  void _connect(BluetoothDevice device) async {
    setState(() {
      _connectedDeviceName = device.name ?? 'Bluetooth sem nome';
      _connectedDevice = device;
    });

    if (connection != null) {
      // Dispose old connection
      connection!.dispose();
      connection = null;
    }

    try {
      // Connect to the device
      connection = await BluetoothConnection.toAddress(device.address);
      _refreshList();
      _showToast(context, 'Conectado a ${device.name}');

      // Start listening to the device
      _startListening();
    } catch (exception) {
      // Handle exception
      _refreshList();
      _showToast(context, 'Erro ao tentar se conectar, tente novamente!');
    }
  }

  void _onDisconnected() {
    setState(() {
      _connectedDevice = null;
      connection = null;
    });
    _refreshList();
    // Navigate back to the Bluetooth tab
    //_tabController.animateTo(0); // Assuming Bluetooth tab is at index 0
  }

  void _disconnect() async {
    // Dispose connection
    connection!.dispose();
    connection = null;

    setState(() {
      _connectedDevice = null;
    });

    //_showToast(context, 'Desconectado');

    // Change tab to Bluetooth tab
    //_tabController.animateTo(0); // Adicione esta linha
  }

  // Method to start listening to the device
  void _startListening() {
    connection!.input?.listen((Uint8List data) async {
      // Converta a lista de bytes para uma string
      final message = String.fromCharCodes(data);
      print('Mensagem chegando pelo Bluetooth: $message');

      String result = await _validateMessage(message);

      if (result.isNotEmpty&& result!="") {
        String processedText = _processReceivedText(result);
        _receivedMessages.add(processedText);
      }
      setState(() {
        // Update state if needed
      });
    }, onDone: () {
      // Handle disconnection
      if (isConnected) {
        _disconnect();
      }

      _refreshList();
      _showToast(context, "Desconectado");

        _pressCount=1;// Reseta contador da calibração caso desconecte no meio da calibração

    });

    setState(() {
      isListening = true;
    });
  }

  late String ultima;

  Future<bool> _sendMessage(String message) async {
    int crc = calcularCRC(message); // Calcula o CRC da mensagem

    String messageWithCRC = '<$message-$crc>'; // Adiciona o CRC à mensagem no formato correto
    encodedMessage = Uint8List.fromList(utf8.encode(messageWithCRC));

    if (message.isNotEmpty && message != "ACK") {
      if (connection != null) {
        // Envia a mensagem
        connection!.output.add(encodedMessage!);
        await connection!.output.allSent;
        ultima = message;
        print('Mensagem enviada: $messageWithCRC');
        _messageTextFieldController.clear(); // Limpa o texto digitado

        try {
          await ackCompleter.future.timeout(Duration(milliseconds: 2000));
          print('Mensagem($messageWithCRC) enviada e ACK recebido');
          // Mensagem enviada com sucesso, ACK recebido
          reenviarMensagem = false; // Define que a próxima mensagem não precisa ser reenviada
          return true;
        } catch (erro) {
          // Timeout expirado ou erro ao aguardar o ACK
          print('Timeout ao aguardar o ACK: $erro');
        }
      } else {
        //@TODO colocar um aviso popup ou algo assim
        print('Erro: conexão não está estabelecida.');
      }
    } else if (message.isNotEmpty && (message == "ACK" || message == "NACK")) {
      // se receber se usar _sendMessage() para enviar ACK ou NACK envia
      connection!.output.add(encodedMessage!);
      await connection!.output.allSent;
      print('Mensagem enviada: $message');
    }

    if (reenviarMensagem) {
      // Verifica se a mensagem anterior precisa ser reenviada
      reenviarMensagem = false; // Define que a próxima mensagem não precisa ser reenviada
      return await _sendMessage(ultima); // Reenvia a mensagem anterior
    }

    return false;
  }




  int calcularCRC(String str) {
    int crc = 0;

    for (int i = 0; i < str.length; i++) {
      crc += str.codeUnitAt(i);
    }
    //print('CRC CALCULADO: $crc');
    return crc;
  }

  Future<String> _validateMessage(String message) async {
    message = message.trim(); // Remove espaços em branco no início e no final da mensagem
    print('Recebido para validar: $message');

    if (message.length > 0 && message.startsWith('<') && message.endsWith('>')) {
      // Remove os caracteres de formatação '<' e '>'
      String cleanedMessage = message.substring(1, message.length - 1);

      // Separa o dado e o checksum
      List<String> parts = cleanedMessage.split('-');
      String data = parts[0];

      if (data == "ACK") {
        // Tratar diretamente as mensagens de ACK
        print('Recebi o ACK e terminei o ackCompleter');
        ackCompleter.complete(); // Resolva o Completer do envio da mensagem

        print('Mensagem ACK recebida: $message');
        return data;
      }

      if (data == "NACK") {
        print('Mensagem NACK recebida: $message');
        // Tratar diretamente as mensagens de NACK
        if (ultima.isNotEmpty) {
          await _sendMessage("ACK");
          print('Reenviando mensagem anterior: $ultima');
          await _sendMessage(ultima);
        } else {
          print('Não há mensagem anterior para reenviar.');
        }
        return data;
      }

      int? receivedChecksum = int.tryParse(parts[1]);

      // Calcula o checksum do dado recebido
      int calculatedChecksum = calcularCRC(data);

      print('CRC CALCULADO: $calculatedChecksum');
      print('CRC RECEBIDO: $receivedChecksum');

      // Mensagem está ok? Passa mensagem e envia ACK sem aguardar resposta
      if (receivedChecksum != null && receivedChecksum == calculatedChecksum) {
        if (data != "ACK" && data != "") {
          // Se for válida, mas não for mensagem de confirmação
          print('Mensagem está OK: $data: enviando ACK');
          await _sendMessage("ACK");
          return data;
        }
        return data;
      } else {
        // Se a mensagem não for válida, envia NACK
        print('Mensagem com erro de CheckSum($data): enviando NACK');
        await _sendMessage("NACK");
      }
    } else {
      print('Mensagem com formato inválido: $message');
    }
    return '';
  }


  String _processReceivedText(String text) {
    print("Mensagem atual: $text");
    print("Ultima mensagem: $ultima");
    // Verifica se a mensagem recebida é igual à última mensagem enviada e a descarta, se for o caso
    if (text == ultima && text.length == ultima.length) {
      print("Mensagem duplicada. Descartando: $text");
      return "";
      //return "#######\n Mensagem ($text)duplicada! Descartada! \n#######";
    }

    final Map<String, String> codeMap = {
      "#=": "###############################",
      "Arre=":  "Arremesso-------------------->",
      "Ci=":    "                    Calibração Iniciada!\n "
                "\n1° Antes de continuar, certifique-se de encher o equipamento com ração e apertar o botão até encher completamente a rosca!\n"
                "\n2° Tenha em mãos uma balança com precisão de pelo menos 5g\n"
                "\n3° Em seguida, coloque um pote para armazenar a primeira porção de ração, aperto o botão Calibrar e aguarde!\n",
      "Fim1=":  "                   Fim da primeira porção\n "
                "Pese a ração, digite o peso no campo abaixo e aperte enviar.\n",
      "Fim2=":  "                   Fim da Segunda porção\n "
                "Pese a ração, digite o peso no campo abaixo e aperte enviar.\n",
      "RecA=":   "O peso digitado foi=",
      "RecB=":   "O peso digitado foi=",
      "C2="  :  "\nRecoloque o pote para armazenar a segunda porção de ração, aperte o botão Calibrar e aguarde!\n",
      "FimC=":  "Calibração Finalizada!",
      "FimA=":  "Fim do arremesso!",
      "FimP=":  "Fim da porção:",
      "FimR=":  "Fora do periodo de Alimentação!",
      "H=":     "Data e Hora",
      "Hi=":    "Hora do Início da Alimentação",
      "Hf=":    "Hora do Fim da Alimentação",
      "Int=":   "Intervalo----------------------->",
      "IntA=":  "Intervalo entre cada arremesso",
      "ITemp=": "Intervalo entre cada porção",
      "IniA=":  "Iniciando alimentação:",
      "IniP=":  "Programa Inicializado!",
      "Por=":   "Porção-------------------------->",
      "PesA=":  "Liberando---------------------->",
      "QtdA=":  "Cada porção será dividida em:",
      "QtdKg=": "Quantidade de ração diária:",
      "QtdP=":  "Quantidade de porções diária:",
      "QtdRA=": "Quantidade de ração por arremesso:",
      "QtdRP=": "Quantidade de Ração por porções:",
      "TempA=": "Tempo de arremesso--->",
      "T=":     "Temperatura do sensor:",

    };

    for (final code in codeMap.keys) {
      if (text.contains(code)) {
        final index = text.indexOf(code);
        final endIndex = text.indexOf("F\n", index);
        if (endIndex > index || endIndex < 0) {
          final value = endIndex > index
              ? text.substring(index + code.length, endIndex)
              : text.substring(index + code.length);
          String unit = "";

          if (code == "Hi=") {
            final hora = value.substring(0, value.indexOf(":"));
            final minuto = value.substring(value.indexOf(":") + 1);
            final result = "${codeMap[code]}:\n$hora:$minuto";
            print("Input text: $text");
            print("Processed text: $result");
            return result;
          } else if (code == "Hf=") {
            final hora = value.substring(0, value.indexOf(":"));
            final minuto = value.substring(value.indexOf(":") + 1);
            final result = "${codeMap[code]}:\n$hora:$minuto";
            print("Input text: $text");
            print("Processed text: $result");
            return result;
          } else if (code == "Por=") {
            final ini = value.substring(0, value.indexOf(","));
            final fim = value.substring(value.indexOf(",") + 1);
            final result = "${codeMap[code]}$ini de $fim";
            print("Input text: $text");
            print("Processed text: $result");
            return result;
          } else if (code == "Arre=") {
            final ini = value.substring(0, value.indexOf(","));
            final fim = value.substring(value.indexOf(",") + 1);
            final result = "${codeMap[code]}$ini de $fim";
            print("Input text: $text");
            print("Processed text: $result");
            return result;
          } else if (code == "H=") {
            final d = value.substring(0, value.indexOf("_"));
            final m = value.substring(value.indexOf("_") + 1, value.lastIndexOf("_"));
            final a = value.substring(value.lastIndexOf("_") + 1, value.indexOf(" "));
            final h = value.substring(value.indexOf(" ") + 1, value.indexOf(":"));
            final mn = value.substring(value.indexOf(":") + 1, value.lastIndexOf(":"));
            final s = value.substring(value.lastIndexOf(":") + 1);

            final formattedDate = "$d/$m/$a $h:$mn:$s";
            final result = "${codeMap[code]}:\n$formattedDate\n";

            setState(() {
              dia = int.tryParse(d)!;
              mes = int.tryParse(m)!;
              ano = int.tryParse(a)!;
              hora = int.tryParse(h)!;
              minuto = int.tryParse(mn)!;
              segundo = int.tryParse(s)!;
            });

            print("Input text: $text");
            print("Processed text: $result");
            return result;
          } else if (code == "QtdKg=" || code == "QtdRP=" || code == "QtdRA=") {
            unit = "g";
            final result = "${codeMap[code]}\n$value$unit";
            return result;
          } else if (code == "QtdA=") {
            unit = "arremesso(s).";
            final result = "${codeMap[code]}\n$value $unit";
            return result;
          } else if (code == "PesA=") {
            unit = "g de ração";
            final result = "${codeMap[code]}$value$unit";
            return result;
          } else if (code == "TempA=") {
            unit = "s";
            final result = "${codeMap[code]}$value$unit";
            return result;
          } else if (code == "T=") {
            unit = "°C.";
            final result = "${codeMap[code]}\n$value $unit";
            return result;
          } else if (code == "FimC=") {
            final result = "${codeMap[code]} $value ";
            _pressCount=1;
            return result;
          } else if (code == "Ci=") {
            _pressCount=2;
            final result = "${codeMap[code]} $value ";
            return result;
          } else if (code == "Fim1=") {
            _pressCount=3;
            final result = "${codeMap[code]} $value ";
            return result;
          } else if (code == "Fim2=") {
            _pressCount=1;
            final result = "${codeMap[code]} $value ";
            return result;
          } else if (code == "C2=") {
            final result = "${codeMap[code]} $value ";
            return result;
          } else if (code == "RecA=") {
            unit = "g";
            final result = "${codeMap[code]}$value$unit";
            return result;
          } else if (code == "RecB=") {
            unit = "g";
            final result = "${codeMap[code]}$value$unit";
            return result;
          } else if (code == "FimP=") {
            final result = "${codeMap[code]} $value ";
            return result;
          } else if (code == "Int=") {
            unit = "minuto(s)";
            final result = "${codeMap[code]}$value $unit";
            return result;
          } else if (code == "tempACK=") {
            final result = "${codeMap[code]}\n";
            return result;
          } else if (code == "FimR=") {
            final result = "${codeMap[code]}\n";
            return result;
          } else if (code == "FimA=") {
            final result = "${codeMap[code]}\n";
            return result;
          } else if (code == "#=") {
            final result = "${codeMap[code]}\n";
            return result;
          } else if (code == "IniA=") {
            final result = "${codeMap[code]}\n";
            return result;
          } else if (code == "IniP=") {
            final result = "${codeMap[code]}\n";
            return result;
          } else if (code == "QtdP=") {
            unit = "porções.";
            final result = "${codeMap[code]}\n$value $unit";
            return result;
          } else if (code == "ITemp=") {
            final hora = value.substring(0, value.indexOf(":"));
            final minuto = value.substring(value.indexOf(":") + 1, value.lastIndexOf(":"));
            final segundo = value.substring(value.lastIndexOf(":") + 1);
            final result = "${codeMap[code]}:\n$hora:$minuto:$segundo";
            print("Input text: $text");
            print("Processed text: $result");
            return result;
          } else if (code == "IntA=") {
            final minutos = value;
            final result = "${codeMap[code]}:\n$minutos minuto(s)\n";
            print("Input text: $text");
            print("Processed text: $result");
            return result;
          }
        }
      }
    }

    // Se o código não for encontrado, retorna uma mensagem no formato "%%-mensagem"
    final result = "%%-$text";
    print("Input text: $text");
    print("Processed text: $result");
    if (result == "") {
      return "Mensagem vazia";
    }
    return result;
  }

  int _pressCount = 1;

  Future<void> _handleButtonPress() async {
    //_pressCount++;


    switch (_pressCount) {
      case 1:
        _receivedMessages.clear();
        await _sendMessage("Calibrar");
        break;
      case 2:
        _receivedMessages.clear();
        await _sendMessage("Libera");
        //_pressCount++;
        break;
      case 3:
        _receivedMessages.clear();
        await _sendMessage("Libera");
        //_pressCount++;
        break;
    }
  }

  // Method to show a toast message
  void _showToast(BuildContext context, String message) {
    final scaffold = ScaffoldMessenger.of(context);
    scaffold.showSnackBar(
      SnackBar(
        content: Text(message),
        action: SnackBarAction(
          label: 'OK',
          onPressed: () {
            scaffold.hideCurrentSnackBar();
          },
        ),
      ),
    );
  }

  void _refreshList() async {
    final List<BluetoothDevice> devices =
        await FlutterBluetoothSerial.instance.getBondedDevices();
    setState(() {
      _devicesList = devices;
    });
  }

  Widget _buildBluetoothTab() {
    return SingleChildScrollView(
      child: Column(
        children: <Widget>[
          SizedBox(height: 30),
          Text(
            'Estado do Bluetooth:',
            style: TextStyle(fontSize: 24),
          ),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                'OFF ',
                style: TextStyle(fontSize: 24),
              ),
              Switch(
                value: _bluetoothState.isEnabled,
                onChanged: (bool value) {
                  future() async {
                    if (value) {
                      await FlutterBluetoothSerial.instance.requestEnable();
                    } else {
                      await FlutterBluetoothSerial.instance.requestDisable();
                    }
                  }

                  future().then((_) {
                    setState(() {});
                  });
                },
              ),
              Text('ON ', style: TextStyle(fontSize: 24)),
            ],
          ),
          Divider(thickness: 10, color: Colors.blue),
          SizedBox(height: 10),
          const Text(
              'O equipamento não aparece na lista? \nClique em (Buscar Equipamento).',
              style: TextStyle(fontSize: 20)),
          SizedBox(height: 10),
          ElevatedButton(
            child: const Text('Buscar Equipamento'),
            onPressed:
                _navigateToDiscoveryPage, // Substitua pelo nome correto da função
          ),
          SizedBox(height: 20),
          Divider(thickness: 10, color: Colors.blue),
          Text('Selecione o equipamento:', style: TextStyle(fontSize: 20)),
          ListView(
            shrinkWrap: true,
            physics: NeverScrollableScrollPhysics(),
            children: _devicesList
                .map(
                  (device) => Dismissible(
                    key: Key(device.address),
                    onDismissed: (direction) async {
                      // Desconectar do dispositivo, se estiver conectado
                      if (isConnected && device == _connectedDevice) {
                        _disconnect();
                        _refreshList();
                      }

                      // Exibir diálogo para remover manualmente o dispositivo pareado
                      showDialog(
                        context: context,
                        builder: (context) => AlertDialog(
                          title: Text('Deseja remover dispositivo pareado?'),
                          content: Text(
                            'É necessário remover manualmente o dispositivo "${device.name}" nas configurações Bluetooth do seu dispositivo.',
                          ),
                          actions: [
                            TextButton(
                              child: Text('OK'),
                              onPressed: () {
                                Navigator.pop(context);
                              },
                            ),
                          ],
                        ),
                      );

                      // Remover o dispositivo da lista
                      setState(() {
                        _devicesList.remove(device);
                      });
                    },
                    background: Container(
                      color: Colors.red,
                      child: Icon(Icons.delete, color: Colors.white),
                      alignment: Alignment.centerRight,
                      padding: EdgeInsets.only(right: 20),
                    ),
                    child: Card(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          width: 6,
                          color: Colors.blue,
                        ),
                      ),
                      child: ListTile(
                        title: Text(device.name ?? 'Bluetooth sem nome'),
                        subtitle: Text(device.address),
                        trailing: isConnected && device == _connectedDevice
                            ? Icon(Icons.check_circle, color: Colors.green)
                            : Icon(Icons.circle, color: Colors.red),
                        onTap: () {
                          if (isConnected && device == _connectedDevice) {
                            // Disconnect from device
                            _disconnect();
                          } else if (!isConnected) {
                            // Connect to device
                            _connect(device);
                          }
                        },
                      ),
                    ),
                  ),
                )
                .toList(),
          ),

          SizedBox(height: 30),

          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              ElevatedButton.icon(
                onPressed: () async {
                  final List<BluetoothDevice> devices =
                      await FlutterBluetoothSerial.instance.getBondedDevices();
                  setState(() {
                    _devicesList = devices;
                  });
                },
                icon: Icon(Icons.refresh),
                label: Text('Atualizar lista de equipamentos'),
              ),
            ],
          ),
          Divider(thickness: 10, color: Colors.blue),

          SizedBox(height: 50),
        ],
      ),
    );
  }

// Method to build the A300 tab
  Widget _buildA300Tab() {
    return SingleChildScrollView(
      child: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey, width: 5),
                  borderRadius: BorderRadius.circular(30.0),
                ),
                padding: EdgeInsets.all(10.0),
                child: Column(
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.only(
                          topLeft: Radius.circular(25),
                          topRight: Radius.circular(25.0),
                        ),
                        color: Colors
                            .green, // Definir a cor de fundo da AppBar como verde
                      ),
                      child: AppBar(
                        backgroundColor: Colors.transparent,
                        // Definir a cor de fundo da AppBar como transparente
                        elevation: 0,
                        // Remover sombra da AppBar
                        centerTitle: true,
                        title: Text(
                          'Mensagens recebidas do $_connectedDeviceName',
                          style: TextStyle(fontSize: 18),
                        ),
                      ),
                    ),
                    Divider(thickness: 2, color: Colors.grey),
                    SizedBox(height: 2),
                    Container(
                      height: 250,
                      child: isConnected
                          ? ListView.builder(
                        itemCount: _receivedMessages.length,
                        itemBuilder: (context, index) {
                          String processedText = _receivedMessages[index];
                          return Text(
                            processedText,
                            style: TextStyle(
                              fontSize: 16,
                              fontFamily: 'Noto Sans',
                            ),
                          );
                        },
                      )
                          : Center(
                        child: Text(
                          'Equipamento Desconectado',
                          style: TextStyle(
                            fontSize: 16,
                            fontFamily: 'Noto Sans',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Container(
              decoration: BoxDecoration(),
              child: ElevatedButton(
                child: Text('Limpar mensagens'),
                onPressed: () {
                  setState(() {
                    _receivedMessages.clear();
                  });
                },
                style: ElevatedButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(30.0),
                  ),
                  backgroundColor: Colors.green,
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(10.0),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    decoration: BoxDecoration(),
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25.0),
                        ),
                        backgroundColor: Colors.green,
                      ),
                      child: Text('Configurar A300'),
                      onPressed: isConnected
                          ? () async {
                        if (isConnected) {
                          // Navega para a página ConfigurationPage e espera pela string de retorno
                          String? calibracao = await Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (context) => ConfigurationPage(),
                            ),
                          );

                          // Verifica se a string de retorno não é nula
                          if (calibracao != null) {
                            // Atualize a variável calibracao com a string retornada
                            setState(() async {
                              this.calibracao = calibracao;
                              try {
                                await _sendMessage(calibracao);
                              } catch (error) {
                                // Lidar com o erro (timeout ou outro erro)
                                print('Erro ao enviar a mensagem: $error');
                              }
                            });
                          }
                        }
                      }
                          : null,
                    ),
                  ),
                  SizedBox(width: 50),
                  Container(
                    decoration: BoxDecoration(),
                    child: ElevatedButton(
                      child: Text('Calibrar'),
                      onPressed: ()  {
                        _handleButtonPress();
                      },
                      style: ElevatedButton.styleFrom(
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(25.0),
                        ),
                        backgroundColor: Colors.green,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            GestureDetector(
              onDoubleTap: () {
                FocusScope.of(context).unfocus();
              },
              child: Container(
                constraints: BoxConstraints(maxWidth: 270, maxHeight: 50),
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey, width: 1),
                  borderRadius: BorderRadius.circular(5),
                  color: Colors.grey[200],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: TextField(
                          controller: _messageTextFieldController,
                          decoration: InputDecoration(
                            hintText: 'Digite o peso',
                            border: InputBorder.none,
                          ),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(8.0),
                      child: ElevatedButton(
                        child: Text('Enviar'),
                        onPressed: isConnected
                            ? () async {
                          if (isConnected) {
                            String message =
                                _messageTextFieldController.text;
                            try {
                              await _sendMessage(
                                  message);} catch (error) {
                              // Lidar com o erro (timeout ou outro erro)
                              print('Erro ao enviar a mensagem: $message');
                            } // Chamar a função _sendMessage() com a mensagem digitada
                            _messageTextFieldController.clear();
                            FocusScope.of(context).unfocus();
                          }
                        }
                            : null,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildControleTab() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          SizedBox(height: 20),
          ElevatedButton(
            child: Text('Ligar'),
            onLongPress: isConnected
                ? () async {
                  try { await _sendMessage("Ligar");} catch (error) {
                    // Lidar com o erro (timeout ou outro erro)
                    print('Erro ao enviar a mensagem: $error');
                  }
                  }
                : null,
            onPressed: () {},
          ),
        ],
      ),
    );
  }

  // Method to show a popup message
  void _showPopup(String message) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text('Aviso'),
          content: Text(message),
          actions: [
            TextButton(
              child: Text('OK'),
              onPressed: () {
                _refreshList();
                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }
}

// Configuration page
class ConfigurationPage extends StatefulWidget {
  @override
  _ConfigurationPageState createState() => _ConfigurationPageState();
}

class _ConfigurationPageState extends State<ConfigurationPage> {
  TimeOfDay selectedTime = TimeOfDay.now();
  TimeOfDay selectedTimeFim = TimeOfDay.now();
  final pesoController = TextEditingController();
  String porcao = '1';
  String subdivisaoPorcoes = '1';
  String intervaloSubdivisao = '0';
  String tempoIntervalo = "1";

  int ano = 0;
  int mes = 0;
  int dia = 0;
  int hora = 0;
  int minuto = 0;
  int segundo = 0;

  //@TODO verificar se é preciso receber o valor atual do ESP
  int horaIni = 0;
  int minutoIni = 0;
  int horaFim = 0;
  int minutoFim = 0;
  int peso = 0;
  int porcoes = 1;
  int arremessos = 1;
  int intervalo = 1;
  bool checkboxValue =
      false; // Variável booleana para armazenar o estado do Checkbox
  String calibracao = '';

  Future<void> _selectTime() async {
    TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: selectedTime,
    );
    if (time != null) {
      setState(() {
        selectedTime = time;
      });
    }
  }

  Future<void> _selectTimeFim() async {
    TimeOfDay? time = await showTimePicker(
      context: context,
      initialTime: selectedTimeFim,
    );
    if (time != null) {
      setState(() {
        selectedTimeFim = time;
      });
    }
  }

  void _getDateTime() {
    DateTime now = DateTime.now();
    setState(() {
      ano = now.year;
      mes = now.month;
      dia = now.day;
      hora = now.hour;
      minuto = now.minute;
      segundo = now.second;
    });
  }

  @override
  void dispose() {
    pesoController.dispose();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    _getDateTime();

    // Configura um timer para atualizar a hora a cada segundo
    Timer.periodic(Duration(seconds: 1), (_) {
      _getDateTime();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.green,
        title: Text('Configurar A300'),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(10.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: <Widget>[
              Column(
                children: <Widget>[
                  Container(
                    margin: EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        autofocus: true,
                        style: TextStyle(fontSize: 16),
                        readOnly: true,
                        onTap: _selectTime,
                        controller: TextEditingController(
                          text: '${selectedTime.hour.toString().padLeft(2, '0')}:${selectedTime.minute.toString().padLeft(2, '0')}',
                        ),
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Hora para o início da alimentação',
                          labelStyle: TextStyle(fontSize: 20),
                          hintText: 'Informe a hora de início',
                          hintStyle: TextStyle(fontSize: 16),
                          prefixIcon: Icon(Icons.access_time, size: 24),
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        style: TextStyle(fontSize: 16),
                        readOnly: true,
                        onTap: _selectTimeFim,
                        controller: TextEditingController(
                          text: '${selectedTimeFim.hour.toString().padLeft(2, '0')}:${selectedTimeFim.minute.toString().padLeft(2, '0')}',
                        ),
                        keyboardType: TextInputType.datetime,
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Hora para o fim da alimentação',
                          labelStyle: TextStyle(fontSize: 20),
                          hintText: 'Informe a hora de término',
                          hintStyle: TextStyle(fontSize: 16),
                          prefixIcon: Icon(Icons.access_time_filled_outlined , size: 24),
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        autofocus: true,
                        style: TextStyle(fontSize: 16),
                        controller: pesoController,
                        keyboardType: TextInputType.number,
                        inputFormatters: <TextInputFormatter>[
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        decoration: InputDecoration(
                          border: OutlineInputBorder(),
                          labelText: 'Peso diário de ração em gramas',
                          labelStyle: TextStyle(fontSize: 17),
                          hintText: 'Informe o peso',
                          hintStyle: TextStyle(fontSize: 16),
                          prefixIcon: Icon(Icons.scale_outlined, size: 24),
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  Container(
                    margin: EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        style: TextStyle(fontSize: 16),
                        decoration: InputDecoration(
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                          isDense: true,
                          border: OutlineInputBorder(),
                          labelStyle: TextStyle(fontSize: 20),
                          hintStyle: TextStyle(fontSize: 16),
                          labelText: 'Dividir em quantas porções?',
                          suffixIcon: Icon(Icons.arrow_drop_down, size: 24),
                          prefixIcon: Icon(Icons.format_list_numbered, size: 24),
                        ),
                        controller: TextEditingController(text: porcao),
                        readOnly: true,
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: Text('Selecione o número de porções'),
                                content: DropdownButton<String>(
                                  value: porcao,
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      porcao = newValue ?? '';
                                      porcoes = newValue != null ? int.parse(newValue) : 1;
                                      Navigator.of(context).pop();
                                    });
                                  },
                                  items: List<DropdownMenuItem<String>>.generate(30, (index) {
                                    int value = index + 1;
                                    return DropdownMenuItem<String>(
                                      value: value.toString(),
                                      child: Text(value.toString()),
                                    );
                                  }).toList(),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),

                  Container(
                    margin: EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        style: TextStyle(fontSize: 16),
                        decoration: InputDecoration(
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                          labelText: 'Deseja subdividir cada porção?',
                          suffixIcon: Icon(Icons.arrow_drop_down, size: 24),
                          border: OutlineInputBorder(),
                          labelStyle: TextStyle(fontSize: 20),
                          hintStyle: TextStyle(fontSize: 16),
                          prefixIcon: Icon(Icons.format_list_bulleted, size: 24),
                        ),
                        controller: TextEditingController(text: subdivisaoPorcoes),
                        readOnly: true,
                        onTap: () {
                          showDialog(
                            context: context,
                            builder: (BuildContext context) {
                              return AlertDialog(
                                title: Text('Selecione em quantas vezes subdividir'),
                                content: DropdownButton<String>(
                                  value: subdivisaoPorcoes,
                                  onChanged: (String? newValue) {
                                    setState(() {
                                      subdivisaoPorcoes = newValue ?? '';
                                      arremessos = int.parse(newValue ?? '1');
                                      Navigator.of(context).pop();
                                    });
                                  },
                                  items: List<DropdownMenuItem<String>>.generate(5, (index) {
                                    int value = index + 1;
                                    return DropdownMenuItem<String>(
                                      value: value.toString(),
                                      child: Text(value.toString()),
                                    );
                                  }).toList(),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ),

                  Container(
                    margin: EdgeInsets.only(bottom: 12),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: TextField(
                        style: TextStyle(fontSize: 16),
                        decoration: InputDecoration(
                          contentPadding: EdgeInsets.symmetric(vertical: 8),
                          labelText: 'Intervalo entre subdivisões(minutos)?',
                          suffixIcon: Icon(Icons.arrow_drop_down, size: 24),
                          border: OutlineInputBorder(),
                          labelStyle: TextStyle(fontSize: 20),
                          hintStyle: TextStyle(fontSize: 16),
                          prefixIcon: Icon(Icons.more_time, size: 24),
                        ),
                        controller: TextEditingController(text: tempoIntervalo.toString()),
                        readOnly: true,
                        onTap: () {
                          if (arremessos > 1) {
                            showDialog(
                              context: context,
                              builder: (BuildContext context) {
                                return AlertDialog(
                                  title: Text('Selecione o intervalo em minutos'),
                                  content: DropdownButton<String>(
                                    value: tempoIntervalo.toString(),
                                    onChanged: (String? newValue) {
                                      setState(() {
                                        tempoIntervalo = newValue ?? '';
                                        intervalo = int.parse(newValue ?? '1');
                                        Navigator.of(context).pop();
                                      });
                                    },
                                    items: List<DropdownMenuItem<String>>.generate(5, (index) {
                                      int value = index + 1;
                                      return DropdownMenuItem<String>(
                                        value: value.toString(),
                                        child: Text(value.toString()),
                                      );
                                    }).toList(),
                                  ),
                                );
                              },
                            );
                          }
                        },
                      ),
                    ),
                  ),

                  Text(" $dia/$mes/$ano "),
                  Text("$hora:$minuto:$segundo"),
                ],
              ),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: <Widget>[
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25.0),
                      ),
                      backgroundColor: Colors.green,
                    ),
                    child: Text('Cancelar'),
                    onPressed: () {
                      Navigator.pop(context);
                    },
                  ),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(25.0),
                      ),
                      backgroundColor: Colors.green,
                    ),
                    child: Text('Salvar'),
                    onPressed: () {
                      peso = int.tryParse(pesoController.text) ?? 0;
                      horaIni = selectedTime.hour;
                      minutoIni = selectedTime.minute;
                      horaFim = selectedTimeFim.hour;
                      minutoFim = selectedTimeFim.minute;

                      if (arremessos <= 1) {
                        setState(() {
                          intervalo = 0;
                        });
                      }

                      calibracao =
                      'S,$horaIni,$minutoIni,$horaFim,$minutoFim,$peso,$porcoes,$arremessos,$intervalo,'
                          '$ano,$mes,$dia,$hora,$minuto,$segundo,F';

                      Navigator.pop(context, calibracao);
                    },
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// Calibration page
class CalibrationPage extends StatefulWidget {
  @override
  _CalibrationPageState createState() => _CalibrationPageState();
}

class _CalibrationPageState extends State<CalibrationPage> {
  // TODO: Add calibration fields and logic

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Calibrar'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton(
              child: Text('Lançar'),
              onPressed: () {
                // TODO: Send launch command to the device
              },
            ),
            SizedBox(height: 20),
            ElevatedButton(
              child: Text('Salvar'),
              onPressed: () {
                // TODO: Send calibration command to the device
              },
            ),
            SizedBox(height: 20),
            ElevatedButton(
              child: Text('Cancelar'),
              onPressed: () {
                // Go back to previous page
                Navigator.pop(context);
              },
            ),
          ],
        ),
      ),
    );
  }
}
