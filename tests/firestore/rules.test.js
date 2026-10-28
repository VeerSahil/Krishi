import { after, before, test } from 'node:test';
import { readFile } from 'node:fs/promises';
import { initializeTestEnvironment, assertFails, assertSucceeds } from '@firebase/rules-unit-testing';
import { collection, doc, getDoc, getDocs, query, setDoc, updateDoc, where } from 'firebase/firestore';

let environment;
const projectId = 'demo-krishi-workflow';
const firestore = uid => environment.authenticatedContext(uid).firestore();

before(async () => {
  // Refuse to use a real Firebase project or silently fall back to cloud access.
  const emulator = process.env.FIRESTORE_EMULATOR_HOST;
  if (!emulator || !/^127\.0\.0\.1:\d+$/.test(emulator)) {
    throw new Error('Run these tests through firebase emulators:exec using the local demo project.');
  }
  const [host, port] = emulator.split(':');
  environment = await initializeTestEnvironment({
    projectId,
    firestore: { host, port: Number(port), rules: await readFile(new URL('../../firestore.rules', import.meta.url), 'utf8') },
  });
  await environment.withSecurityRulesDisabled(async context => {
    const db = context.firestore();
    for (const [uid, role] of [['farmer', 'farmer'], ['other', 'farmer'], ['admin', 'admin'],
      ['team', 'team'], ['team-other', 'team']]) {
      await setDoc(doc(db, 'users', uid), { name: uid, role });
    }
    await setDoc(doc(db, 'farm_inputs', 'visit'), {
      userId: 'farmer', assignedTeamId: 'team', status: 'awaiting_review', moisture: 45,
    });
    await setDoc(doc(db, 'survey_predictions', 'visit'), { recommended_crop: 'Wheat' });
    await setDoc(doc(db, 'farms', 'plot-00001'), { farmerId: 'farmer', assignedTeamId: 'team', assessment: { grade: 'C' } });
    await setDoc(doc(db, 'farm_assessments', 'report'), { farmerId: 'farmer', teamId: 'team', grade: 'C' });
    await setDoc(doc(db, 'support_threads', 'help'), { userId: 'farmer', message: 'Visit question' });
    await setDoc(doc(db, 'reviews', 'review'), { rating: 5 });
  });
});

after(async () => { if (environment) await environment.cleanup(); });

test('anonymous clients cannot read profiles, surveys, drafts, support or reviews', async () => {
  const db = environment.unauthenticatedContext().firestore();
  for (const [name, id] of [['users', 'farmer'], ['farm_inputs', 'visit'],
    ['survey_predictions', 'visit'], ['support_threads', 'help'], ['reviews', 'review']]) {
    await assertFails(getDoc(doc(db, name, id)));
  }
});

test('profiles are readable only by their owner and admin', async () => {
  await assertSucceeds(getDoc(doc(firestore('farmer'), 'users', 'farmer')));
  await assertSucceeds(getDoc(doc(firestore('admin'), 'users', 'farmer')));
  await assertFails(getDoc(doc(firestore('other'), 'users', 'farmer')));
  await assertFails(getDoc(doc(firestore('team'), 'users', 'farmer')));
});

test('signup can create a farmer profile but cannot grant admin or team access', async () => {
  await assertSucceeds(setDoc(doc(firestore('new-farmer'), 'users', 'new-farmer'), {
    name: 'New farmer', role: 'farmer', email: 'farmer@example.invalid',
  }));
  for (const role of ['admin', 'team']) {
    const uid = 'attempt-' + role;
    await assertFails(setDoc(doc(firestore(uid), 'users', uid), { name: uid, role }));
  }
  await assertFails(setDoc(doc(firestore('farmer'), 'users', 'another-user'), { role: 'farmer' }));
});

test('profile contact updates cannot change roles or add privileged fields', async () => {
  await assertSucceeds(updateDoc(doc(firestore('farmer'), 'users', 'farmer'), { phone: 'test-phone' }));
  await assertFails(updateDoc(doc(firestore('farmer'), 'users', 'farmer'), { role: 'admin' }));
  await assertFails(updateDoc(doc(firestore('team'), 'users', 'team'), { role: 'admin' }));
  await assertFails(updateDoc(doc(firestore('farmer'), 'users', 'farmer'), { privileged: true }));
});

test('survey reads are limited to the owning farmer, assigned team and admin', async () => {
  for (const uid of ['farmer', 'team', 'admin']) {
    await assertSucceeds(getDoc(doc(firestore(uid), 'farm_inputs', 'visit')));
  }
  for (const uid of ['other', 'team-other']) {
    await assertFails(getDoc(doc(firestore(uid), 'farm_inputs', 'visit')));
  }
  await assertSucceeds(getDocs(query(collection(firestore('farmer'), 'farm_inputs'), where('userId', '==', 'farmer'))));
  await assertSucceeds(getDocs(query(collection(firestore('team'), 'farm_inputs'), where('assignedTeamId', '==', 'team'))));
  await assertFails(getDocs(collection(firestore('farmer'), 'farm_inputs')));
});

test('draft crop recommendations are private until backend publication', async () => {
  await assertSucceeds(getDoc(doc(firestore('admin'), 'survey_predictions', 'visit')));
  for (const uid of ['farmer', 'other', 'team', 'team-other']) {
    await assertFails(getDoc(doc(firestore(uid), 'survey_predictions', 'visit')));
  }
});

test('farmer support is visible only to its owner and admin', async () => {
  for (const uid of ['farmer', 'admin']) {
    await assertSucceeds(getDoc(doc(firestore(uid), 'support_threads', 'help')));
  }
  for (const uid of ['other', 'team']) {
    await assertFails(getDoc(doc(firestore(uid), 'support_threads', 'help')));
  }
});

test('even admin clients must use backend APIs to write workflow records', async () => {
  for (const uid of ['farmer', 'team', 'admin']) {
    for (const name of ['farm_inputs', 'survey_predictions', 'support_threads', 'reviews']) {
      await assertFails(setDoc(doc(firestore(uid), name, 'direct-client-write'), { userId: uid }));
    }
  }
  await assertSucceeds(getDoc(doc(firestore('farmer'), 'reviews', 'review')));
  await assertFails(getDoc(doc(firestore('admin'), 'unknown_collection', 'record')));
});


test('staff world and assessment history are private to admin and assigned inspectors', async () => {
  for (const [name, id] of [['farms', 'plot-00001'], ['farm_assessments', 'report']]) {
    await assertSucceeds(getDoc(doc(firestore('admin'), name, id)));
    await assertSucceeds(getDoc(doc(firestore('team'), name, id)));
    for (const uid of ['farmer', 'other', 'team-other']) {
      await assertFails(getDoc(doc(firestore(uid), name, id)));
      await assertFails(setDoc(doc(firestore(uid), name, id), { grade: 'A' }));
    }
    await assertFails(updateDoc(doc(firestore('admin'), name, id), { grade: 'A' }));
    await assertFails(updateDoc(doc(firestore('team'), name, id), { grade: 'A' }));
  }
});

test('team world queries must constrain assignment', async () => {
  await assertSucceeds(getDocs(query(collection(firestore('team'), 'farms'), where('assignedTeamId', '==', 'team'))));
  await assertFails(getDocs(collection(firestore('team'), 'farms')));
  await assertFails(getDocs(query(collection(firestore('farmer'), 'farms'), where('farmerId', '==', 'farmer'))));
});
