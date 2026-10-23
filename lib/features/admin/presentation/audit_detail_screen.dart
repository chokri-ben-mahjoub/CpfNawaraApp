import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/l10n/app_strings.dart';
import '../../../core/team/team_service.dart';
import '../../../core/widgets/hero_header.dart';
import '../../../core/widgets/responsive.dart';
import 'audit_screen.dart';

/// Paramètres de la page de détail : l'entrée et les autres entrées déjà
/// chargées (pour l'historique du même élément).
class AuditDetailArgs {
  final AuditEntry entry;
  final List<AuditEntry> all;
  const AuditDetailArgs(this.entry, this.all);
}

/// Page de détail d'une entrée de la traçabilité : qui, quand, quoi, champs
/// modifiés (avant → après) et historique du même élément.
class AuditDetailScreen extends ConsumerWidget {
  final AuditDetailArgs? args;
  const AuditDetailScreen({super.key, this.args});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final scheme = Theme.of(context).colorScheme;
    String t(String key) => tr(locale, key);

    final a = args;
    if (a == null) {
      // Page rechargée : l'entrée n'est plus en mémoire, retour à la liste.
      return Scaffold(
        appBar: AppBar(title: Text(t('adminAudit'))),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  t('auditEmpty'),
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  onPressed: () => context.go('/admin/audit'),
                  child: Text(t('adminAudit')),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final e = a.entry;
    final action = auditEffectiveAction(e);
    final color = auditActionColor(action, scheme);
    final who = e.name.isEmpty ? e.email : e.name;
    final route = auditRoute(e);
    final fullDate = DateFormat(
      'EEEE d MMMM yyyy',
      locale.languageCode,
    ).format(e.at);
    final time = DateFormat('HH:mm:ss').format(e.at);
    final history =
        a.all
            .where(
              (o) =>
                  o.id != e.id &&
                  o.table == e.table &&
                  o.docId == e.docId &&
                  e.docId.isNotEmpty,
            )
            .toList()
          ..sort((x, y) => y.at.compareTo(x.at));

    String ago() {
      final d = DateTime.now().difference(e.at);
      if (d.inMinutes < 1) return t('auditAgoNow');
      if (d.inMinutes < 60)
        return fill(t('auditAgoMin'), {'n': '${d.inMinutes}'});
      if (d.inHours < 24) return fill(t('auditAgoHour'), {'n': '${d.inHours}'});
      return fill(t('auditAgoDay'), {'n': '${d.inDays}'});
    }

    String summary() {
      final lines = [
        '${t('auditAction')}: ${t(auditActionKey(action))}',
        '${t('auditUser')}: $who (${e.email})',
        '${t('colDate')}: $fullDate $time',
        '${t('auditTable')}: ${t(auditTableKey(e.table))}',
        '${t('auditDetail')}: ${auditSafeText(e.label, t)}',
        for (final c in e.changes)
          auditIsImageChange(c)
              ? '${auditFieldLabel(c.field, t)}: ${t('auditImageChanged')}'
              : '${auditFieldLabel(c.field, t)}: ${c.before.isEmpty ? '—' : c.before} → ${c.after.isEmpty ? '—' : c.after}',
      ];
      return lines.join('\n');
    }

    Widget section(String title, IconData icon, List<Widget> children) =>
        Padding(
          padding: const EdgeInsets.only(top: 14),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(18),
              side: BorderSide(
                color: scheme.outlineVariant.withValues(alpha: 0.6),
              ),
            ),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 20, color: scheme.primary),
                      const SizedBox(width: 8),
                      Text(
                        title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 15,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  ...children,
                ],
              ),
            ),
          ),
        );

    Widget kv(String label, String value, {bool copy = false}) => Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
          if (copy)
            InkWell(
              onTap: () {
                Clipboard.setData(ClipboardData(text: value));
                ScaffoldMessenger.of(context)
                    .showSnackBar(SnackBar(content: Text(t('auditCopied'))));
              },
              child: Padding(
                padding: const EdgeInsets.only(left: 6),
                child: Icon(
                  Icons.copy_rounded,
                  size: 17,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );

    Widget pill(String text, Color c, {bool strike = false}) => Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        text.isEmpty ? '—' : text,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.w800,
          color: c,
          decoration: strike ? TextDecoration.lineThrough : null,
        ),
      ),
    );

    Widget changeCard(AuditChange c) {
      final image = auditIsImageChange(c);
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              auditFieldLabel(c.field, t),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: scheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            if (image)
              Align(
                alignment: Alignment.centerLeft,
                child: pill(t('auditImageChanged'), scheme.primary),
              )
            else
              Wrap(
                spacing: 10,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  pill(c.before, scheme.error, strike: true),
                  Icon(
                    Icons.arrow_forward_rounded,
                    size: 20,
                    color: scheme.onSurfaceVariant,
                  ),
                  pill(c.after, const Color(0xFF2E9E5B)),
                ],
              ),
          ],
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(t('auditDetailTitle')),
        actions: [
          IconButton(
            tooltip: t('auditCopy'),
            icon: const Icon(Icons.copy_all_rounded),
            onPressed: () {
              Clipboard.setData(ClipboardData(text: summary()));
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(t('auditCopied'))));
            },
          ),
        ],
      ),
      body: ListView(
        padding: pagePadding(context, top: 8, bottom: 40),
        children: [
          HeroHeader(
            icon: auditActionIcon(action),
            title: t(auditActionKey(action)),
            subtitle:
                '${t(auditTableKey(e.table))} · ${auditSafeText(e.label, t)}',
            pillLabel: ago(),
            pillColor: color,
            stats: [
              HeroStat(value: who, label: t('auditUser')),
              HeroStat(
                value: DateFormat('dd/MM/yyyy').format(e.at),
                label: t('colDate'),
              ),
              HeroStat(
                value: DateFormat('HH:mm').format(e.at),
                label: t('auditTime'),
              ),
              HeroStat(value: '${e.changes.length}', label: t('auditChanges')),
            ],
          ),
          if (route != null) ...[
            const SizedBox(height: 14),
            SizedBox(
              height: 50,
              child: FilledButton.icon(
                onPressed: () => context.push(route),
                icon: const Icon(Icons.open_in_new_rounded),
                label: Text(
                  t('auditOpen'),
                  style: const TextStyle(fontWeight: FontWeight.w800),
                ),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),
            ),
          ],
          section(t('auditWho'), Icons.person_outline_rounded, [
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: color.withValues(alpha: 0.15),
                  child: Text(
                    who.trim().isEmpty ? '?' : who.trim()[0].toUpperCase(),
                    style: TextStyle(
                      color: color,
                      fontWeight: FontWeight.w800,
                      fontSize: 18,
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        who,
                        style: const TextStyle(
                          fontWeight: FontWeight.w800,
                          fontSize: 16,
                        ),
                      ),
                      if (e.email.isNotEmpty && e.email != who)
                        Text(
                          e.email,
                          style: TextStyle(
                            fontSize: 13,
                            color: scheme.onSurfaceVariant,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ]),
          section(t('auditWhen'), Icons.schedule_rounded, [
            kv(t('colDate'), fullDate),
            kv(t('auditTime'), time),
            kv(t('auditAgo'), ago()),
          ]),
          section(t('auditWhat'), Icons.folder_open_outlined, [
            kv(t('auditAction'), t(auditActionKey(action))),
            kv(t('auditTable'), t(auditTableKey(e.table))),
            kv(t('auditDetail'), auditSafeText(e.label, t)),
            if (e.docId.isNotEmpty)
              kv(t('auditElementId'), e.docId, copy: true),
          ]),
          section(t('auditChanges'), Icons.compare_arrows_rounded, [
            if (e.changes.isEmpty)
              Text(
                t('auditNoChanges'),
                style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
              )
            else
              for (final c in e.changes) changeCard(c),
          ]),
          if (history.isNotEmpty)
            section(t('auditHistory'), Icons.history_rounded, [
              for (final h in history.take(15))
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () => context.pushReplacement(
                    '/admin/audit/detail',
                    extra: AuditDetailArgs(h, a.all),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Row(
                      children: [
                        Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: auditActionColor(
                              auditEffectiveAction(h),
                              scheme,
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '${t(auditActionKey(auditEffectiveAction(h)))} · ${h.name.isEmpty ? h.email : h.name}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w700,
                                  fontSize: 13.5,
                                ),
                              ),
                              Text(
                                DateFormat('dd/MM/yyyy HH:mm').format(h.at),
                                style: TextStyle(
                                  fontSize: 12,
                                  color: scheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: scheme.onSurfaceVariant,
                        ),
                      ],
                    ),
                  ),
                ),
            ]),
        ],
      ),
    );
  }
}
