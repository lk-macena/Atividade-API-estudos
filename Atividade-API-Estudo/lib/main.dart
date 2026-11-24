import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

const apiUrl = String.fromEnvironment(
  'API_URL',
  defaultValue: 'http://127.0.0.1:8080',
);

typedef Veiculo = Map<String, dynamic>;

void main() => runApp(const MaterialApp(home: Catalogo()));

class Catalogo extends StatefulWidget {
  const Catalogo({super.key});
  @override
  State<Catalogo> createState() => _CatalogoState();
}

class _CatalogoState extends State<Catalogo> {
  final usuario = TextEditingController(text: 'aluno');
  final senha = TextEditingController();
  String? token;
  List<Veiculo> veiculos = [];
  bool ocupado = false;
  String erro = '';

  @override
  void dispose() {
    usuario.dispose();
    senha.dispose();
    super.dispose();
  }
  Future<Object?> solicitar(
    String metodo,
    String caminho,
    int status, {
    Veiculo? dados,
  }) async {
    final pedido = http.Request(metodo, Uri.parse('$apiUrl$caminho'));
    if (token != null) pedido.headers['Authorization'] = 'Bearer $token';
    if (dados != null) {
      pedido.headers['Content-Type'] = 'application/json; charset=utf-8';
      pedido.body = jsonEncode(dados);
    }
    final resposta = await pedido
        .send()
        .then(http.Response.fromStream)
        .timeout(const Duration(seconds: 10));
    final texto = utf8.decode(resposta.bodyBytes);
    final json = texto.isEmpty ? null : jsonDecode(texto);
    if (resposta.statusCode != status) {
      if (resposta.statusCode == 401 && caminho != '/login') {
        token = null;
        veiculos = [];
      }
      throw Exception(
        json is Map ? json['erro'] : 'HTTP ${resposta.statusCode}',
      );
    }
    return json;
  }

  Future<void> executar(Future<void> Function() operacao) async {
    if (ocupado) return;
    setState(() {
      ocupado = true;
      erro = '';
    });
    try {
      await operacao();
    } catch (falha) {
      erro = falha.toString();
    } finally {
      if (mounted) setState(() => ocupado = false);
    }
  }

  Future<void> entrar() => executar(() async {
    final login = await solicitar(
      'POST',
      '/login',
      200,
      dados: {'usuario': usuario.text.trim(), 'senha': senha.text},
    ) as Veiculo;
    if (!mounted) return;
    token = login['access_token'] as String;
    senha.clear();
    await listar();
  });

  Future<void> listar() async {
    final lista = await solicitar('GET', '/veiculos', 200) as List;
    veiculos = lista.cast<Veiculo>();
  }
  Future<void> editar([Veiculo? original]) async {
    final dados = await showDialog<Veiculo>(
      context: context,
      builder: (_) => FormularioVeiculo(original: original),
    );
    if (!mounted || dados == null) return;
    await executar(() async {
      if (original == null) {
        await solicitar('POST', '/veiculos', 201, dados: dados);
      } else {
        await solicitar(
          'PUT',
          '/veiculos/${original['id']}',
          204,
          dados: dados,
        );
      }
      await listar();
    });
  }

  Future<void> excluir(Veiculo veiculo) async {
    final confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Excluir veículo?'),
        content: Text('${veiculo['marca']} ${veiculo['modelo']}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Excluir'),
          ),
        ],
      ),
    );
    if (!mounted || confirmou != true) return;
    await executar(() async {
      await solicitar('DELETE', '/veiculos/${veiculo['id']}', 204);
      await listar();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Catálogo de veículos')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (ocupado) const LinearProgressIndicator(),
          if (erro.isNotEmpty) Text(erro),
          if (token == null) ...[
            TextField(
              controller: usuario,
              decoration: const InputDecoration(labelText: 'Usuário'),
            ),
            TextField(
              controller: senha,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Senha'),
            ),
            FilledButton(
              onPressed: ocupado ? null : entrar,
              child: const Text('Entrar'),
            ),
          ] else ...[
            FilledButton(
              onPressed: ocupado ? null : () => editar(),
              child: const Text('Cadastrar veículo'),
            ),
            TextButton(
              onPressed: ocupado ? null : () => executar(listar),
              child: const Text('Atualizar'),
            ),
            if (veiculos.isEmpty && !ocupado && erro.isEmpty)
              const Text('Nenhum veículo cadastrado.'),
            for (final veiculo in veiculos)
              ListTile(
                title: Text('${veiculo['marca']} ${veiculo['modelo']}'),
                subtitle: Text('${veiculo['ano']}'),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: 'Editar',
                      icon: const Icon(Icons.edit),
                      onPressed: ocupado ? null : () => editar(veiculo),
                    ),
                    IconButton(
                      tooltip: 'Excluir',
                      icon: const Icon(Icons.delete),
                      onPressed: ocupado ? null : () => excluir(veiculo),
                    ),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }
}
class FormularioVeiculo extends StatefulWidget {
  const FormularioVeiculo({super.key, this.original});
  final Veiculo? original;
  @override
  State<FormularioVeiculo> createState() => _FormularioVeiculoState();
}

class _FormularioVeiculoState extends State<FormularioVeiculo> {
  final form = GlobalKey<FormState>();
  late final marca = TextEditingController(
    text: widget.original?['marca'] as String?,
  );
  late final modelo = TextEditingController(
    text: widget.original?['modelo'] as String?,
  );
  late final ano = TextEditingController(
    text: widget.original?['ano']?.toString(),
  );

  @override
  void dispose() {
    marca.dispose();
    modelo.dispose();
    ano.dispose();
    super.dispose();
  }

  String? obrigatorio(String? valor) =>
      (valor ?? '').trim().isEmpty ? 'Preencha este campo.' : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        widget.original == null ? 'Cadastrar veículo' : 'Editar veículo',
      ),
      content: Form(
        key: form,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: marca,
                validator: obrigatorio,
                decoration: const InputDecoration(labelText: 'Marca'),
              ),
              TextFormField(
                controller: modelo,
                validator: obrigatorio,
                decoration: const InputDecoration(labelText: 'Modelo'),
              ),
              TextFormField(
                controller: ano,
                keyboardType: TextInputType.number,
                validator: (valor) =>
                    (int.tryParse(valor?.trim() ?? '') ?? 0) > 0
                    ? null
                    : 'Informe um ano inteiro positivo.',
                decoration: const InputDecoration(labelText: 'Ano'),
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            if (!form.currentState!.validate()) return;
            Navigator.pop<Veiculo>(context, {
              'marca': marca.text.trim(),
              'modelo': modelo.text.trim(),
              'ano': int.parse(ano.text.trim()),
            });
          },
          child: const Text('Salvar'),
        ),
      ],
    );
  }
}