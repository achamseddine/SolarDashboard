import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/deye_api_client.dart';
import '../../../core/api/json_utils.dart';
import '../../../core/models/credentials.dart';
import '../../../core/providers.dart';
import '../../common/widgets.dart';

/// DeyeCloud account form with test / save / clear.
class CredentialsCard extends ConsumerStatefulWidget {
  const CredentialsCard({super.key});

  @override
  ConsumerState<CredentialsCard> createState() => _CredentialsCardState();
}

class _CredentialsCardState extends ConsumerState<CredentialsCard> {
  final _form = GlobalKey<FormState>();
  final _appId = TextEditingController();
  final _appSecret = TextEditingController();
  final _email = TextEditingController();
  final _password = TextEditingController();
  final _companyId = TextEditingController();
  DeyeRegion _region = DeyeRegion.eu;
  bool _showSecret = false;
  bool _showPassword = false;
  bool _busy = false;
  String? _testResult;
  bool _testOk = false;

  @override
  void initState() {
    super.initState();
    final c = ref.read(credentialsProvider);
    if (c != null) {
      _appId.text = c.appId;
      _appSecret.text = c.appSecret;
      _email.text = c.email;
      _password.text = c.passwordSha256;
      _companyId.text = c.companyId ?? '';
      _region = c.region;
    }
  }

  @override
  void dispose() {
    for (final c in [_appId, _appSecret, _email, _password, _companyId]) {
      c.dispose();
    }
    super.dispose();
  }

  DeyeCredentials _fromForm() => DeyeCredentials(
        appId: _appId.text.trim(),
        appSecret: _appSecret.text.trim(),
        email: _email.text.trim(),
        passwordSha256: DeyeCredentials.normalisePassword(_password.text),
        companyId: _companyId.text.trim().isEmpty ? null : _companyId.text.trim(),
        region: _region,
      );

  Future<void> _test() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _testResult = null;
    });
    final creds = _fromForm();
    final client = DeyeApiClient(credentials: creds, tokenCache: MemoryTokenCache(), maxRetries: 1, log: (m) => ref.read(appLogProvider.notifier).add(m));
    try {
      await client.authenticate();
      final info = await client.accountInfo();
      final orgs = firstList(info, ['orgInfoList', 'companyList', 'orgList']);
      final names = [for (final o in orgs) '${asString(pick(o, ['companyName', 'orgName', 'name'])) ?? '?'} (id ${asString(pick(o, ['companyId', 'orgId', 'id'])) ?? '?'})'];
      setState(() {
        _testOk = true;
        _testResult = 'Login OK. ${names.isEmpty ? 'Account reachable.' : 'Organisations: ${names.join(', ')}'}${creds.companyId == null && names.isNotEmpty ? '\nEnter the company id above to see the organisation plants.' : ''}';
      });
    } catch (e) {
      setState(() {
        _testOk = false;
        _testResult = 'Failed: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      final creds = _fromForm();
      await ref.read(credentialsProvider.notifier).save(creds);
      _password.text = creds.passwordSha256;
      if (ref.read(settingsProvider).demoMode) {
        await ref.read(settingsProvider.notifier).update((s) => s.copyWith(demoMode: false));
      }
      await ref.read(syncEngineProvider).syncNow();
      if (mounted) ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(content: Text('Credentials saved – synchronisation started')));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    await ref.read(credentialsProvider.notifier).clear();
    for (final c in [_appId, _appSecret, _email, _password, _companyId]) {
      c.clear();
    }
    setState(() => _testResult = null);
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final saved = ref.watch(credentialsProvider);
    return SectionCard(
      title: 'DeyeCloud account',
      subtitle: saved == null ? 'Not configured' : 'Configured for ${saved.email} · ${saved.region.name.toUpperCase()} · company ${saved.companyId ?? '– (personal)'}',
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Create an application at developer.deyecloud.com/app to obtain the App ID and App Secret. The e-mail and password are those of the DeyeCloud account that owns the school plants; the company id selects the organisation (business) account.', style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant)),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                _field(_appId, 'App ID', width: 220, validator: _required),
                _field(_appSecret, 'App Secret', width: 300, obscure: !_showSecret, validator: _required, toggle: () => setState(() => _showSecret = !_showSecret), shown: _showSecret),
                _field(_email, 'E-mail', width: 260, validator: (v) => v == null || !v.contains('@') ? 'Enter the account e-mail' : null, keyboard: TextInputType.emailAddress),
                _field(_password, 'Password or SHA-256 hash', width: 300, obscure: !_showPassword, validator: _required, toggle: () => setState(() => _showPassword = !_showPassword), shown: _showPassword, hint: 'Plain password or 64-hex digest'),
                _field(_companyId, 'Company id (optional)', width: 200, keyboard: TextInputType.number),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<DeyeRegion>(
                    initialValue: _region,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Data centre', border: OutlineInputBorder(), isDense: true),
                    items: [for (final r in DeyeRegion.values) DropdownMenuItem(value: r, child: Text(r.label, overflow: TextOverflow.ellipsis))],
                    onChanged: (v) => setState(() => _region = v ?? DeyeRegion.eu),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                OutlinedButton.icon(onPressed: _busy ? null : _test, icon: const Icon(Icons.wifi_tethering, size: 18), label: const Text('Test connection')),
                FilledButton.icon(onPressed: _busy ? null : _save, icon: const Icon(Icons.save_outlined, size: 18), label: const Text('Save and sync')),
                if (saved != null) TextButton.icon(onPressed: _busy ? null : _clear, icon: const Icon(Icons.delete_outline, size: 18), label: const Text('Clear credentials')),
                if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            if (_testResult != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_testOk ? Icons.check_circle_outline : Icons.error_outline, size: 18, color: _testOk ? Colors.green : scheme.error),
                  const SizedBox(width: 6),
                  Expanded(child: SelectableText(_testResult!, style: t.bodySmall)),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text('Credentials are stored in the device secure store (Android Keystore / OS keyring), never in the database.', style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant)),
          ],
        ),
      ),
    );
  }

  static String? _required(String? v) => v == null || v.trim().isEmpty ? 'Required' : null;

  Widget _field(TextEditingController c, String label, {required double width, bool obscure = false, String? Function(String?)? validator, VoidCallback? toggle, bool shown = false, String? hint, TextInputType? keyboard}) {
    return SizedBox(
      width: width,
      child: TextFormField(
        controller: c,
        obscureText: obscure,
        validator: validator,
        keyboardType: keyboard,
        autocorrect: false,
        enableSuggestions: false,
        decoration: InputDecoration(
          labelText: label,
          hintText: hint,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: toggle == null ? null : IconButton(icon: Icon(shown ? Icons.visibility_off : Icons.visibility, size: 18), onPressed: toggle),
        ),
      ),
    );
  }
}
