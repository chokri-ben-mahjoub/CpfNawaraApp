import 'package:flutter/material.dart';

import '../../../../core/theme/app_theme.dart';

/// Largeur à partir de laquelle les listes d'administration s'affichent en
/// tableau (web, PC, tablette) plutôt qu'en cartes (téléphone).
const adminTableBreakpoint = 720.0;

/// Colonne d'un [AdminTable].
class AdminColumn<T> {
  final String label;
  final Widget Function(T item) cell;
  final bool numeric;
  const AdminColumn(this.label, this.cell, {this.numeric = false});
}

/// Liste adaptative : tableau large sur grand écran, cartes empilées sur
/// téléphone.
class AdminTable<T> extends StatelessWidget {
  final List<T> items;
  final List<AdminColumn<T>> columns;
  final Widget Function(BuildContext context, T item) card;
  final void Function(T item)? onTap;

  const AdminTable({super.key, required this.items, required this.columns, required this.card, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < adminTableBreakpoint) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                card(context, items[i]),
              ],
            ],
          );
        }
        return Card(
          clipBehavior: Clip.antiAlias,
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: DataTable(
                showCheckboxColumn: false,
                headingRowColor: WidgetStatePropertyAll(scheme.surfaceContainerHigh),
                headingTextStyle: TextStyle(fontWeight: FontWeight.w800, color: scheme.onSurface, fontSize: 13),
                columns: [for (final c in columns) DataColumn(label: Text(c.label), numeric: c.numeric)],
                rows: [
                  for (final item in items)
                    DataRow(
                      onSelectChanged: onTap == null ? null : (_) => onTap!(item),
                      cells: [for (final c in columns) DataCell(c.cell(item))],
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Carte cliquable d'une liste d'administration (affichage téléphone).
class AdminCard extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  const AdminCard({super.key, required this.leading, required this.title, this.subtitle, this.trailing, this.onTap});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Card(
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: leading,
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: subtitle == null ? null : Text(subtitle!, style: TextStyle(color: scheme.onSurfaceVariant)),
        trailing: trailing ?? (onTap == null ? null : const Icon(Icons.chevron_right)),
        onTap: onTap,
      ),
    );
  }
}

/// Puce de sélection (paramètre, type...) : coche/décoche sa présence dans
/// une liste. Si [onEdit] est fourni (élément personnalisé, modifiable),
/// affiche un petit crayon pour le renommer, changer son unité ou le
/// supprimer directement depuis cette liste, sans quitter l'écran.
class SelectableEditableChip extends StatelessWidget {
  final String label;
  final bool selected;
  final ValueChanged<bool> onSelected;
  final Future<void> Function()? onEdit;

  const SelectableEditableChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onSelected,
    this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    if (onEdit == null) {
      return FilterChip(
        label: Text(label),
        selected: selected,
        selectedColor: accentColor.withValues(alpha: 0.18),
        onSelected: onSelected,
      );
    }
    return InputChip(
      label: Text(label),
      selected: selected,
      selectedColor: accentColor.withValues(alpha: 0.18),
      onSelected: onSelected,
      deleteIcon: const Icon(Icons.edit_outlined, size: 16),
      onDeleted: onEdit,
    );
  }
}

/// Pastille d'icône colorée (début de ligne).
class IconBadge extends StatelessWidget {
  final IconData icon;
  final Color color;
  final double size;
  const IconBadge(this.icon, {super.key, this.color = accentColor, this.size = 42});

  @override
  Widget build(BuildContext context) => Container(
    width: size,
    height: size,
    decoration: BoxDecoration(color: color.withValues(alpha: 0.13), borderRadius: BorderRadius.circular(13)),
    child: Icon(icon, color: color, size: size * 0.52),
  );
}

/// Titre de section dans un écran d'administration.
class AdminSectionTitle extends StatelessWidget {
  final String text;
  final Widget? trailing;
  const AdminSectionTitle(this.text, {super.key, this.trailing});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.fromLTRB(4, 18, 4, 10),
    child: Row(
      children: [
        Expanded(
          child: Text(text, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
        ),
        ?trailing,
      ],
    ),
  );
}

/// Feuille du bas pour un formulaire d'administration (titre + contenu
/// défilant), plein écran sur téléphone, centrée et limitée sur grand écran.
Future<T?> showAdminSheet<T>(BuildContext context, {required Widget Function(BuildContext) builder}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    constraints: const BoxConstraints(maxWidth: 640),
    shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(sheetContext).viewInsets.bottom),
      child: SingleChildScrollView(padding: const EdgeInsets.fromLTRB(20, 20, 20, 24), child: builder(sheetContext)),
    ),
  );
}

/// Confirmation d'une action destructive.
Future<bool> confirmDanger(
  BuildContext context, {
  required String title,
  required String body,
  required String confirm,
  required String cancel,
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(cancel)),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: Theme.of(dialogContext).colorScheme.error),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(confirm),
        ),
      ],
    ),
  );
  return result == true;
}

/// Lecture d'un nombre saisi (virgule ou point décimal).
double? parseDecimal(String text) {
  final t = text.trim().replaceAll(' ', '').replaceAll(',', '.');
  if (t.isEmpty) return null;
  return double.tryParse(t);
}

/// Nombre affiché sans décimales inutiles (pour pré-remplir un champ).
String decimalText(double? v) {
  if (v == null) return '';
  if (v == v.roundToDouble()) return v.toInt().toString();
  return double.parse(v.toStringAsPrecision(8)).toString();
}
