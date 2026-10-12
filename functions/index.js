'use strict';

// PuitsTrack — opérations d'administration réservées au serveur (Firebase
// Admin SDK), appelées depuis l'app (Administration › Utilisateurs) par un
// administrateur de l'entreprise.
//
// Facultatives : sans elles (forfait gratuit Spark), l'app fonctionne avec
// les règles Firestore seules ; un membre désactivé n'a plus accès aux
// données mais peut encore se connecter. Avec elles (forfait Blaze), la
// désactivation bloque aussi la connexion, la suppression efface le compte,
// et l'administrateur peut choisir un nouveau mot de passe.
//
// Déploiement : powershell -ExecutionPolicy Bypass -File tool\deploy.ps1 -Functions

const { onCall, HttpsError } = require('firebase-functions/v2/https');
const { setGlobalOptions } = require('firebase-functions/v2');
const { initializeApp } = require('firebase-admin/app');
const { getAuth } = require('firebase-admin/auth');
const { getFirestore, FieldValue } = require('firebase-admin/firestore');

initializeApp();
setGlobalOptions({ region: 'europe-west1', maxInstances: 10 });

const db = getFirestore();
const ROLES = ['admin', 'ingenieur', 'operateur', 'lecteur'];

/** Appelant connecté, administrateur actif de [companyId]. */
async function requireAdmin(request, companyId) {
  if (!request.auth) throw new HttpsError('unauthenticated', 'Connexion requise.');
  if (typeof companyId !== 'string' || companyId.length === 0) {
    throw new HttpsError('invalid-argument', 'Entreprise manquante.');
  }
  const me = await db.doc(`companies/${companyId}/members/${request.auth.uid}`).get();
  if (!me.exists || me.get('actif') !== true || me.get('role') !== 'admin') {
    throw new HttpsError('permission-denied', "Réservé aux administrateurs de l'entreprise.");
  }
  return me;
}

/**
 * Compte [uid] rattaché à [companyId] (accounts/{uid}) : un administrateur
 * n'agit que sur les comptes de sa propre entreprise.
 */
async function requireOwnAccount(request, companyId, uid) {
  if (typeof uid !== 'string' || uid.length === 0) throw new HttpsError('invalid-argument', 'Compte manquant.');
  if (uid === request.auth.uid) {
    throw new HttpsError('failed-precondition', 'Action impossible sur son propre compte.');
  }
  const account = await db.doc(`accounts/${uid}`).get();
  if (!account.exists || account.get('companyId') !== companyId) {
    throw new HttpsError('permission-denied', "Ce compte n'appartient pas à l'entreprise.");
  }
  return account;
}

function audit(companyId, me, request, action, docId, label) {
  return db.collection(`companies/${companyId}/audit`).add({
    uid: request.auth.uid,
    email: request.auth.token.email || '',
    nom: me.get('nom') || '',
    action,
    table: 'users',
    docId,
    label,
    changedAt: Date.now(),
    at: FieldValue.serverTimestamp(),
  });
}

/** Présence des fonctions (l'app choisit la voie serveur si elle répond). */
exports.ping = onCall(() => ({ ok: true, version: 1 }));

/** Crée un compte (e-mail + mot de passe provisoire) dans l'entreprise. */
exports.createMember = onCall(async (request) => {
  const { companyId, email, password, name = '', role, service = '' } = request.data || {};
  const me = await requireAdmin(request, companyId);
  if (!ROLES.includes(role)) throw new HttpsError('invalid-argument', 'Rôle inconnu.');
  if (typeof email !== 'string' || !email.includes('@')) throw new HttpsError('invalid-argument', 'E-mail invalide.');
  if (typeof password !== 'string' || password.length < 6) {
    throw new HttpsError('invalid-argument', 'Mot de passe trop court (6 caractères minimum).');
  }
  let user;
  try {
    user = await getAuth().createUser({
      email: email.trim().toLowerCase(),
      password,
      displayName: name || undefined,
    });
  } catch (e) {
    if (e.code === 'auth/email-already-exists') {
      throw new HttpsError('already-exists', 'Un compte existe déjà avec cet e-mail.');
    }
    throw e;
  }
  const batch = db.batch();
  batch.set(db.doc(`companies/${companyId}/members/${user.uid}`), {
    email: user.email,
    nom: name,
    role,
    actif: true,
    service,
    createdAt: FieldValue.serverTimestamp(),
    updatedAt: FieldValue.serverTimestamp(),
  });
  batch.set(db.doc(`accounts/${user.uid}`), { companyId, email: user.email });
  await batch.commit();
  await audit(companyId, me, request, 'user_create', user.uid, `${user.email} · ${role}`);
  return { uid: user.uid };
});

/** Active / désactive un membre : la connexion du compte suit. */
exports.setMemberActive = onCall(async (request) => {
  const { companyId, uid, active } = request.data || {};
  const me = await requireAdmin(request, companyId);
  await requireOwnAccount(request, companyId, uid);
  await getAuth().updateUser(uid, { disabled: !active });
  if (!active) await getAuth().revokeRefreshTokens(uid);
  await db.doc(`companies/${companyId}/members/${uid}`).set(
    { actif: !!active, updatedAt: FieldValue.serverTimestamp() },
    { merge: true },
  );
  await audit(companyId, me, request, 'user_update', uid, active ? 'actif' : 'inactif (connexion bloquée)');
  return { ok: true };
});

/** Supprime un membre et son compte. */
exports.deleteMember = onCall(async (request) => {
  const { companyId, uid } = request.data || {};
  const me = await requireAdmin(request, companyId);
  await requireOwnAccount(request, companyId, uid);
  const member = await db.doc(`companies/${companyId}/members/${uid}`).get();
  try {
    await getAuth().deleteUser(uid);
  } catch (e) {
    if (e.code !== 'auth/user-not-found') throw e;
  }
  const batch = db.batch();
  batch.delete(db.doc(`companies/${companyId}/members/${uid}`));
  batch.delete(db.doc(`accounts/${uid}`));
  await batch.commit();
  await audit(companyId, me, request, 'user_remove', uid, member.exists ? member.get('email') || uid : uid);
  return { ok: true };
});

/** Nouveau mot de passe choisi par l'administrateur. */
exports.setMemberPassword = onCall(async (request) => {
  const { companyId, uid, password } = request.data || {};
  const me = await requireAdmin(request, companyId);
  await requireOwnAccount(request, companyId, uid);
  if (typeof password !== 'string' || password.length < 6) {
    throw new HttpsError('invalid-argument', 'Mot de passe trop court (6 caractères minimum).');
  }
  await getAuth().updateUser(uid, { password });
  await getAuth().revokeRefreshTokens(uid);
  await audit(companyId, me, request, 'user_update', uid, 'mot de passe réinitialisé');
  return { ok: true };
});
