
# `Controle_Alimentador`

[![pub package](https://img.shields.io/pub/v/flutter_bluetooth_serial.svg)](https://pub.dartlang.org/packages/flutter_bluetooth_serial)

Interface de comunicação com controles ACK/NACK e checkSum para garantir entrega das mensagens entre ESP32 e o celular via comunicação bluetooth usando como base o flutter_bluetooth_serial.


## Features
Utilizei a biblioteca flutter_bluetooth_serial para estabelecer a comunicação entre equipamentos. Uma das principais funcionalidades do programa reside nas funções responsáveis pelo gerenciamento da troca de mensagens entre os equipamentos. As mensagens trocadas seguem um formato padronizado, sendo estruturadas como "<mensagem-CheckSum>". Ao receber uma mensagem, o programa verifica se ela está de acordo com o formato esperado. Caso esteja, a mensagem é separada do CheckSum e é realizado o cálculo do checksum da mensagem recebida. Em seguida, compara-se o checksum calculado com o checksum recebido.

Se o checksum coincidir, é enviado um ACK (acknowledgement) como resposta, indicando que a mensagem foi recebida e está correta. Por outro lado, se algo estiver errado, é enviado um NACK (negative acknowledgement) para informar que ocorreu um problema e solicitar o reenvio da mensagem. É importante destacar que o programa não envia um ACK em resposta a um ACK, a menos que seja um NACK. Nesse caso específico, será enviado uma confirmação ACK.

Essa abordagem garante a integridade e a confiabilidade das mensagens transmitidas entre os equipamentos, pois verifica-se a consistência do formato e realiza-se a verificação de erros com o uso do CheckSum.

