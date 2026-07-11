import 'package:flutter/material.dart';
import '../api_client.dart';
import '../models/account.dart';

class AccountsScreen extends StatefulWidget {
  const AccountsScreen({super.key});

  @override
  State<AccountsScreen> createState() => _AccountsScreenState();
}

class _AccountsScreenState extends State<AccountsScreen> {
  late Future<List<Account>> _future;

  @override
  void initState() {
    super.initState();
    _future = apiClient.fetchAccounts();
  }

  void _reload() {
    setState(() {
      _future = apiClient.fetchAccounts();
    });
  }

  Color _hexColor(String hex) {
    final value = hex.replaceFirst('#', '');
    return Color(int.parse('FF$value', radix: 16));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Hesaplar'),
        actions: [
          IconButton(onPressed: _reload, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: FutureBuilder<List<Account>>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snapshot.hasError) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('${snapshot.error}'),
                  const SizedBox(height: 12),
                  FilledButton(onPressed: _reload, child: const Text('Tekrar dene')),
                ],
              ),
            );
          }
          final accounts = snapshot.data ?? [];
          if (accounts.isEmpty) {
            return const Center(child: Text('Hesap yok.'));
          }
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView.separated(
              itemCount: accounts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final a = accounts[i];
                return ListTile(
                  leading: CircleAvatar(
                    radius: 8,
                    backgroundColor: _hexColor(a.color),
                  ),
                  title: Text(a.name),
                  subtitle: Text(a.accountType),
                  trailing: Text(
                    a.formattedBalance,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
