import 'package:flutter_test/flutter_test.dart';
import 'package:puitstrack/core/data/rounds_repository.dart';
import 'package:puitstrack/core/models/well_round.dart';

void main() {
  WellRound round(String id, String well, DateTime day, String time, Map<String, Object?> values) => WellRound(
    id: id,
    wellId: well,
    day: day,
    time: time,
    values: values,
    operatorName: 'op',
    recordedAt: day,
  );
  final d1 = DateTime(2026, 10, 25);
  final d2 = DateTime(2026, 10, 26);

  final state = RoundsState(
    rounds: [
      round('a', 'w1', d1, '18:00', {'csg_a': 0.0, 'well_status': 'roundOpen'}),
      round('b', 'w1', d2, '17:00', {'csg_a': 0.3}),
      round('c', 'w1', d2, '06:30', {'csg_a': 0.1, 'well_status': 'roundOpen'}),
      round('d', 'w2', d2, '07:00', {'well_status': 'roundClosed'}),
      round('e', siteRoundId, d2, '07:30', {'nac_edg_diesel': 90}),
    ],
  );

  test('tournées d\'un puits pour un jour : plusieurs, triées par heure', () {
    expect(state.on('w1', d2).map((r) => r.id), ['c', 'b']);
    expect(state.on('w1', DateTime(2026, 10, 26, 15, 30)).length, 2, reason: 'l\'heure du jour est ignorée');
    expect(state.on('w2', d1), isEmpty);
  });

  test('tout le jour : puits puis heure, le site séparé par son identifiant vide', () {
    expect(state.allOn(d2).map((r) => r.id), ['e', 'c', 'b', 'd']);
    expect(state.allOn(d2).where((r) => r.isSite).single.number('nac_edg_diesel'), 90);
  });

  test('dernière valeur de référence avant la saisie', () {
    expect(state.previous('w1', d2, excludeId: 'c')?.id, 'b', reason: 'même jour, plus tard dans la journée');
    expect(state.previous('w1', d1)?.id, 'a');
    expect(state.previous('w3', d2), isNull);
  });

  test('les champs : un puits a l\'état ouvert/fermé, le site ses installations', () {
    expect(wellRoundFields.map((f) => f.key), containsAll(['whp_transmitter', 'csg_a', 'choke_opening', 'well_status']));
    expect(wellRoundFields.firstWhere((f) => f.key == 'well_status').choices, roundWellStatusChoices);
    expect(siteRoundFields.map((f) => f.key), contains('camp_ro_status'));
    expect({for (final f in [...wellRoundFields, ...siteRoundFields]) f.key}.length, wellRoundFields.length + siteRoundFields.length);
  });
}
