import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:sqlite3/sqlite3.dart';

final banco = sqlite3.open('veiculos.db');
final sessoes = <String, DateTime>{};
final aleatorio = Random.secure();

void prepararBanco() {
  banco.execute('''
    CREATE TABLE IF NOT EXISTS veiculos (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      marca TEXT NOT NULL,
      modelo TEXT NOT NULL,
      ano INTEGER NOT NULL CHECK (ano > 0)
    )
  ''');
}
Future<void> responder(HttpRequest pedido, int status, Object? corpo) async {
  pedido.response.statusCode = status;
  if (corpo != null) {
    pedido.response.headers.contentType = ContentType(
      'application',
      'json',
      charset: 'utf-8',
    );
    pedido.response.write(jsonEncode(corpo));
  }
  await pedido.response.close();
}

Future<Map<String, dynamic>> lerObjeto(HttpRequest pedido) async {
  final dados = jsonDecode(await utf8.decoder.bind(pedido).join());
  if (dados is! Map<String, dynamic>) {
    throw const FormatException('Envie um objeto JSON.');
  }
  return dados;
}

Future<void> login(HttpRequest pedido) async {
  final dados = await lerObjeto(pedido);
  if (dados['usuario'] != 'aluno' || dados['senha'] != '123456') {
    await responder(pedido, 401, {'erro': 'Credenciais inválidas.'});
    return;
  }
  final agora = DateTime.now();
  sessoes.removeWhere((_, validade) => !validade.isAfter(agora));
  final token = base64UrlEncode(
    List<int>.generate(32, (_) => aleatorio.nextInt(256)),
  );
  sessoes[token] = agora.add(const Duration(minutes: 30));
  await responder(pedido, 200, {'access_token': token});
}

bool autorizado(HttpRequest pedido) {
  final cabecalho = pedido.headers.value(HttpHeaders.authorizationHeader) ?? '';
  if (!cabecalho.startsWith('Bearer ')) return false;
  final validade = sessoes[cabecalho.substring(7)];
  return validade != null && validade.isAfter(DateTime.now());
}
Future<(String, String, int)> lerVeiculo(HttpRequest pedido) async {
  final dados = await lerObjeto(pedido);
  final marca = dados['marca'];
  final modelo = dados['modelo'];
  final ano = dados['ano'];
  if (marca is! String ||
      marca.trim().isEmpty ||
      modelo is! String ||
      modelo.trim().isEmpty ||
      ano is! int ||
      ano <= 0) {
    throw const FormatException(
      'Informe marca, modelo e ano inteiro positivo.',
    );
  }
  return (marca.trim(), modelo.trim(), ano);
}

Future<void> catalogo(HttpRequest pedido, int? id) async {
  switch ((pedido.method, id)) {
    case ('GET', null):
      final linhas = banco.select(
        'SELECT id, marca, modelo, ano FROM veiculos ORDER BY id',
      );
      await responder(pedido, 200, [
        for (final linha in linhas) Map<String, Object?>.from(linha),
      ]);
    case ('POST', null):
      final (marca, modelo, ano) = await lerVeiculo(pedido);
      banco.execute(
        'INSERT INTO veiculos (marca, modelo, ano) VALUES (?, ?, ?)',
        [marca, modelo, ano],
      );
      await responder(pedido, 201, {'id': banco.lastInsertRowId});
    case ('PUT', final int alvo):
      final (marca, modelo, ano) = await lerVeiculo(pedido);
      banco.execute(
        'UPDATE veiculos SET marca = ?, modelo = ?, ano = ? WHERE id = ?',
        [marca, modelo, ano, alvo],
      );
      await responderAlteracao(pedido);
    case ('DELETE', final int alvo):
      banco.execute('DELETE FROM veiculos WHERE id = ?', [alvo]);
      await responderAlteracao(pedido);
    default:
      await responder(pedido, 405, {'erro': 'Método não permitido.'});
  }
}

Future<void> responderAlteracao(HttpRequest pedido) async {
  if (banco.updatedRows == 0) {
    await responder(pedido, 404, {'erro': 'Veículo não encontrado.'});
    return;
  }
  await responder(pedido, 204, null);
}
Future<void> atender(HttpRequest pedido) async {
  final headers = pedido.response.headers;
  headers.set('Access-Control-Allow-Origin', '*');
  headers.set('Access-Control-Allow-Headers', 'Authorization, Content-Type');
  headers.set(
    'Access-Control-Allow-Methods',
    'GET, POST, PUT, DELETE, OPTIONS',
  );
  final caminho = pedido.uri.path;
  final item = RegExp(r'^/veiculos/([0-9]+)$').firstMatch(caminho);
  try {
    if (pedido.method == 'OPTIONS') {
      await responder(pedido, 204, null);
    } else if (caminho == '/login' && pedido.method == 'POST') {
      await login(pedido);
    } else if (caminho == '/veiculos' || item != null) {
      if (!autorizado(pedido)) {
        headers.set(HttpHeaders.wwwAuthenticateHeader, 'Bearer');
        await responder(pedido, 401, {
          'erro': 'Entre novamente para continuar.',
        });
        return;
      }
      final id = item == null ? null : int.tryParse(item.group(1)!);
      if (item != null && id == null) {
        await responder(pedido, 404, {'erro': 'Veículo não encontrado.'});
        return;
      }
      await catalogo(pedido, id);
    } else {
      await responder(pedido, 404, {'erro': 'Rota não encontrada.'});
    }
  } on FormatException catch (erro) {
    await responder(pedido, 400, {'erro': erro.message});
  } catch (erro) {
    stderr.writeln(erro);
    await responder(pedido, 500, {'erro': 'Falha interna do servidor.'});
  }
}

Future<void> main() async {
  prepararBanco();
  final porta = int.parse(Platform.environment['PORT'] ?? '8080');
  final servidor = await HttpServer.bind(InternetAddress.anyIPv4, porta);
  print('API local disponível na porta $porta');
  await for (final pedido in servidor) {
    await atender(pedido);
  }
}