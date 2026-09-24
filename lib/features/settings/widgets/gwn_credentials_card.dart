import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/api/gwn_api_client.dart' show GwnApiClient, gwnKeyFingerprint;
import '../../../core/api/gwn_api_exception.dart';
import '../../../core/api/gwn_endpoints.dart';
import '../../../core/models/gwn_credentials.dart';
import '../../../core/providers.dart';
import '../../../core/utils/format.dart';
import '../../common/widgets.dart';

/// GWN Cloud account used by the school-network dashboards.
///
/// The App ID and Secret Key are written to the platform secure store, never
/// to the database or the repository.
class GwnCredentialsCard extends ConsumerStatefulWidget {
  const GwnCredentialsCard({super.key});

  @override
  ConsumerState<GwnCredentialsCard> createState() => _GwnCredentialsCardState();
}

class _GwnCredentialsCardState extends ConsumerState<GwnCredentialsCard> with AutomaticKeepAliveClientMixin {
  // Settings is a lazy list: without this the card is disposed when it
  // scrolls away and rebuilt from the saved values, silently throwing away a
  // key that had been typed but not yet saved.
  @override
  bool get wantKeepAlive => true;

  final _form = GlobalKey<FormState>();
  late final TextEditingController _appId;
  late final TextEditingController _secret;
  late String _baseUrl;
  bool _showSecret = false;
  bool _busy = false;
  String? _result;
  bool _ok = false;

  @override
  void initState() {
    super.initState();
    final c = ref.read(gwnCredentialsProvider);
    _appId = TextEditingController(text: c?.appId ?? '');
    _secret = TextEditingController(text: c?.secretKey ?? '');
    _baseUrl = c?.baseUrl ?? GwnCredentials.defaultBaseUrl;
  }

  @override
  void dispose() {
    _appId.dispose();
    _secret.dispose();
    super.dispose();
  }

  GwnCredentials get _entered => GwnCredentials(
        appId: GwnCredentials.clean(_appId.text),
        secretKey: GwnCredentials.clean(_secret.text),
        baseUrl: _baseUrl,
      );

  Future<void> _test() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    final client = GwnApiClient(
      credentials: _entered,
      lastSuccess: ref.read(gwnLastAuthProvider),
      onAuthenticated: (a) => ref.read(gwnLastAuthProvider.notifier).record(a),
    );
    try {
      await client.authenticate();
      final networks = await client.listNetworks();
      // Pull one network's detail and devices too: which fields the account
      // actually returns is the thing worth knowing, and it cannot be
      // guessed from the outside.
      if (networks.isNotEmpty) {
        final id = networks.first.id;
        try {
          await client.listDevices(id);
        } catch (_) {}
        try {
          await client.networkDaily(id, '', DateTime.now().toIso8601String().substring(0, 10));
        } catch (_) {}
      }
      setState(() {
        _ok = true;
        _result = [
          'Connected. ${networks.length} networks visible.',
          'Paths: ${client.lastProbe.entries.map((e) => '${e.key} → ${e.value}').join(', ')}',
          if (client.fieldsSeen.isNotEmpty)
            'Fields returned:\n${client.fieldsSeen.entries.map((e) => '  • ${e.key}: ${e.value.join(', ')}').join('\n')}',
        ].join('\n');
      });
    } catch (e) {
      setState(() {
        _ok = false;
        _result = e is GwnApiException ? e.message : '$e';
      });
    } finally {
      client.close();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _save() async {
    if (!(_form.currentState?.validate() ?? false)) return;
    setState(() => _busy = true);
    try {
      await ref.read(gwnCredentialsProvider.notifier).save(_entered);
      await ref.read(networkSyncReportProvider.notifier).sync();
      if (mounted) {
        setState(() {
          _ok = true;
          _result = 'Saved and synchronised.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _ok = false;
          _result = e is GwnApiException ? e.message : '$e';
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// Thirty-two random characters typed on a tablet keyboard is a typo
  /// waiting to happen, and the field is narrower than the key, so a
  /// mistake at the end is invisible. Pasting avoids both.
  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      setState(() {
        _ok = false;
        _result = 'The clipboard is empty. Copy the Secret Key from GWN Cloud first.';
      });
      return;
    }
    final key = GwnCredentials.clean(text);
    _secret.text = key;
    final n = key.length;
    final expected = GwnCredentials.usualKeyLength;
    setState(() {
      _ok = n == expected;
      _result = n == expected
          ? 'Pasted $n characters. Test the connection, or Save and sync.'
          : 'Pasted $n characters — GWN issues $expected, so ${n < expected ? 'this is ${expected - n} short' : 'this has ${n - expected} too many'}. '
              'Copy the key again from GWN Cloud.';
    });
  }

  Future<void> _clear() async {
    await ref.read(gwnCredentialsProvider.notifier).clear();
    _appId.clear();
    _secret.clear();
    setState(() => _result = null);
  }

  String? _required(String? v) => v == null || v.trim().isEmpty ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final t = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    final saved = ref.watch(gwnCredentialsProvider);
    final lastAuth = ref.watch(gwnLastAuthProvider);
    return SectionCard(
      title: 'GWN Cloud account (school networks)',
      // What is stored, described without being revealed: after a Save this
      // is how an operator checks that what reached the secure store is what
      // they meant to put there.
      subtitle: saved == null
          ? 'Not configured — the network dashboards show demo data'
          : [
              'Configured · ${saved.baseUrl} · App ID ${saved.appId}',
              'stored key ${GwnCredentials.clean(saved.secretKey).length} characters',
              if (GwnCredentials.clean(saved.secretKey).length >= 16)
                'fingerprint ${gwnKeyFingerprint(GwnCredentials.clean(saved.secretKey))}',
              if (lastAuth != null) 'last worked ${Fmt.ago(lastAuth.ts)} with fingerprint ${lastAuth.fingerprint}',
            ].join(' · '),
      child: Form(
        key: _form,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The App ID and Secret Key come from the GWN Cloud account that manages the school networks. They feed the '
              'Connectivity tabs: infrastructure health, internet reliability, Wi-Fi use and the adoption index.',
              style: t.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: [
                SizedBox(
                  width: 220,
                  child: TextFormField(
                    controller: _appId,
                    validator: _required,
                    keyboardType: TextInputType.number,
                    autocorrect: false,
                    enableSuggestions: false,
                    decoration: const InputDecoration(labelText: 'App ID', border: OutlineInputBorder(), isDense: true),
                  ),
                ),
                SizedBox(
                  width: 340,
                  // The count under the field is the only way to see that the
                  // whole key arrived: the field is narrower than the key, so
                  // the last characters sit out of view.
                  child: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _secret,
                    builder: (context, value, _) {
                      final raw = value.text;
                      final key = GwnCredentials.clean(raw);
                      final stripped = raw.trim().length - key.length;
                      return TextFormField(
                        controller: _secret,
                        validator: _required,
                        obscureText: !_showSecret,
                        // A credential must not be offered to the keyboard's
                        // autocorrect, which can rewrite what was typed.
                        autocorrect: false,
                        enableSuggestions: false,
                        keyboardType: TextInputType.visiblePassword,
                        style: const TextStyle(fontFamily: 'monospace'),
                        decoration: InputDecoration(
                          labelText: 'Secret Key',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          helperText: key.isEmpty
                              ? 'Paste the key issued in GWN Cloud'
                              : [
                                  '${key.length} characters',
                                  if (key.length < GwnCredentials.usualKeyLength) '${GwnCredentials.usualKeyLength - key.length} short',
                                  if (key.length > GwnCredentials.usualKeyLength) '${key.length - GwnCredentials.usualKeyLength} too many',
                                  if (stripped > 0) '$stripped invisible character${stripped == 1 ? '' : 's'} removed',
                                  if (key.length >= 16) 'fingerprint ${gwnKeyFingerprint(key)}',
                                ].join(' · '),
                          helperStyle: key.isNotEmpty && key.length != GwnCredentials.usualKeyLength
                              ? TextStyle(color: Theme.of(context).colorScheme.error)
                              : null,
                          suffixIconConstraints: const BoxConstraints(minWidth: 76, minHeight: 40),
                          suffixIcon: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                tooltip: 'Paste',
                                visualDensity: VisualDensity.compact,
                                icon: const Icon(Icons.content_paste, size: 18),
                                onPressed: _busy ? null : _paste,
                              ),
                              IconButton(
                                tooltip: _showSecret ? 'Hide' : 'Show',
                                visualDensity: VisualDensity.compact,
                                icon: Icon(_showSecret ? Icons.visibility_off : Icons.visibility, size: 18),
                                onPressed: () => setState(() => _showSecret = !_showSecret),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
                SizedBox(
                  width: 260,
                  child: DropdownButtonFormField<String>(
                    initialValue: GwnEndpoints.hosts.values.contains(_baseUrl) ? _baseUrl : GwnEndpoints.hosts.values.first,
                    isExpanded: true,
                    decoration: const InputDecoration(labelText: 'Region', border: OutlineInputBorder(), isDense: true),
                    items: [
                      for (final e in GwnEndpoints.hosts.entries)
                        DropdownMenuItem(value: e.value, child: Text(e.key, overflow: TextOverflow.ellipsis)),
                    ],
                    onChanged: (v) => setState(() => _baseUrl = v ?? GwnCredentials.defaultBaseUrl),
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
                if (saved != null) TextButton.icon(onPressed: _busy ? null : _clear, icon: const Icon(Icons.delete_outline, size: 18), label: const Text('Clear')),
                if (_busy) const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)),
              ],
            ),
            if (_result != null) ...[
              const SizedBox(height: 10),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(_ok ? Icons.check_circle_outline : Icons.error_outline, size: 18, color: _ok ? Colors.green : scheme.error),
                  const SizedBox(width: 6),
                  Expanded(child: SelectableText(_result!, style: t.bodySmall)),
                ],
              ),
            ],
            const SizedBox(height: 8),
            Text(
              'Stored in the device secure store, never in the database. The Open API paths this build tries are listed '
              'in GwnEndpoints; "Test connection" reports which one the account accepted.',
              style: t.labelSmall?.copyWith(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
