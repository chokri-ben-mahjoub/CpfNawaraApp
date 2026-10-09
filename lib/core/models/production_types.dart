/// Identifiants fixes des 3 débits de production (voir
/// `lib/core/data/local_database.dart`), partagés entre la fiche puits (carte
/// Production) et le tableau de bord (courbe d'ensemble).
const oilFlowTypeId = 't_oil_flow';
const gasFlowTypeId = 't_gas_flow';
const waterFlowTypeId = 't_water_flow';

/// Pression de fond dynamique (Pwf), saisie à la demande lors d'un test de
/// puits — combinée à la pression de gisement du puits pour calculer le PI.
const bottomHolePressureTypeId = 't_pwf';
