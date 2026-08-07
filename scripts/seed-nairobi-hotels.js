#!/usr/bin/env node
'use strict';

/**
 * seed-nairobi-hotels.js
 * -----------------------------------------------------------------------
 * One-off script that seeds 4 realistic Nairobi hotels into the live
 * palmnazi system, each with several rooms and a dining menu, so the
 * Phase 5 UI (destination browsing, multi-service booking, payments,
 * messaging) has real, browsable/bookable data to test against.
 *
 * Two halves, matching the app's own split architecture:
 *   1. Places/Cities are owned by the external REST API
 *      (https://pnrcapi.vercel.app — see lib/services/api_client.dart,
 *      lib/admin/admin_api_service.dart). This script logs in as a real
 *      admin account and drives the exact same POST/PATCH/PUT sequence
 *      the admin wizard uses (lib/admin/admin_place_wizard_screen.dart's
 *      11 steps), skipping only the manual-form parts.
 *   2. Rooms / MenuSections / MenuItems are Firestore-authoritative (see
 *      lib/services/room_service.dart / menu_service.dart) — this script
 *      writes them directly via the Firebase Admin SDK, which bypasses
 *      firestore.rules entirely (that's expected/normal for a trusted
 *      server-side script; the Flutter app itself never does this).
 *
 * NOT run automatically. Run manually, once you have:
 *   - A real admin (Admin or MainAdmin role) email/password for the
 *     backend REST API.
 *   - A Firebase service-account JSON key for this project (Firebase
 *     Console → Project Settings → Service Accounts → Generate new
 *     private key). Keep it OUTSIDE the repo or in a gitignored path.
 *
 * Usage:
 *   cd scripts
 *   npm install
 *   SEED_ADMIN_EMAIL="you@example.com" \
 *   SEED_ADMIN_PASSWORD="..." \
 *   GOOGLE_APPLICATION_CREDENTIALS="/absolute/path/to/service-account.json" \
 *   node seed-nairobi-hotels.js
 *
 * Add DRY_RUN=1 to log what would happen without writing anything.
 *
 * Idempotent: re-running skips any hotel that already exists (matched by
 * name within the Nairobi city), and skips Rooms/MenuSections/MenuItems
 * that already exist for a given place (matched by name).
 * -----------------------------------------------------------------------
 */

const admin = require('firebase-admin');

const API_BASE = 'https://pnrcapi.vercel.app';
const DRY_RUN = process.env.DRY_RUN === '1';

const ADMIN_EMAIL = process.env.SEED_ADMIN_EMAIL;
const ADMIN_PASSWORD = process.env.SEED_ADMIN_PASSWORD;

function log(...args) {
  console.log('[seed]', ...args);
}
function warn(...args) {
  console.warn('[seed:warn]', ...args);
}

// ── REST API helpers ─────────────────────────────────────────────────────

let accessToken = null;

async function api(method, path, body) {
  const res = await fetch(`${API_BASE}${path}`, {
    method,
    headers: {
      'Content-Type': 'application/json',
      ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
    },
    body: body !== undefined ? JSON.stringify(body) : undefined,
  });
  const text = await res.text();
  let json;
  try {
    json = text ? JSON.parse(text) : {};
  } catch {
    json = { raw: text };
  }
  if (!res.ok) {
    throw new Error(`${method} ${path} → ${res.status}: ${JSON.stringify(json)}`);
  }
  return json;
}

function unwrap(json) {
  // Mirrors _unwrapObject/_unwrapList in admin_api_service.dart — the
  // backend wraps responses as either the object directly, or
  // { data: {...} }, depending on endpoint.
  return json && typeof json === 'object' && 'data' in json ? json.data : json;
}

async function login() {
  if (!ADMIN_EMAIL || !ADMIN_PASSWORD) {
    throw new Error(
      'Set SEED_ADMIN_EMAIL and SEED_ADMIN_PASSWORD (a real Admin/MainAdmin account) before running this script.',
    );
  }
  const json = await api('POST', '/api/auth/login', {
    email: ADMIN_EMAIL,
    password: ADMIN_PASSWORD,
  });
  accessToken = json.accessToken || unwrap(json).accessToken;
  if (!accessToken) throw new Error('Login succeeded but no accessToken in response.');
  log('Logged in as', ADMIN_EMAIL);
}

async function findCityByName(name) {
  const json = await api('GET', '/api/cities');
  const cities = Array.isArray(unwrap(json)) ? unwrap(json) : unwrap(json).cities || [];
  return cities.find((c) => (c.name || '').toLowerCase() === name.toLowerCase());
}

async function ensureNairobi() {
  const existing = await findCityByName('Nairobi');
  if (existing) {
    log('Nairobi city already exists:', existing.id);
    return existing;
  }
  if (DRY_RUN) {
    log('[dry-run] would create Nairobi city');
    return { id: 'dry-run-city-id', name: 'Nairobi' };
  }
  const created = unwrap(
    await api('POST', '/api/cities', {
      name: 'Nairobi',
      country: 'Kenya',
      region: 'Nairobi County',
      slug: 'nairobi',
      latitude: -1.286389,
      longitude: 36.817223,
      coverImage:
        'https://images.unsplash.com/photo-1611348586804-61bf6c080437?w=1600',
      description:
        "Kenya's capital — a hub of business, culture, and safari gateways, home to some of East Africa's finest hotels.",
      isActive: true,
    }),
  );
  log('Created Nairobi city:', created.id);
  return created;
}

async function findCategoryByName(name) {
  const json = await api('GET', '/api/categories?isActive=true&includeChildren=true');
  const list = Array.isArray(unwrap(json)) ? unwrap(json) : unwrap(json).categories || [];
  return list.find((c) => (c.name || '').toLowerCase().includes(name.toLowerCase()));
}

async function findExistingPlace(cityId, name) {
  const json = await api(
    'GET',
    `/api/places?cityId=${encodeURIComponent(cityId)}&search=${encodeURIComponent(name)}`,
  );
  const list = Array.isArray(unwrap(json)) ? unwrap(json) : unwrap(json).places || [];
  return list.find((p) => (p.name || '').toLowerCase() === name.toLowerCase());
}

// ── Per-room-type / per-dish stock images ────────────────────────────────
//
// Distinct, real Unsplash photos so rooms/dishes don't all show the same
// single place-cover placeholder. Rooms are matched by roomType (a "Deluxe
// Room" and a "Garden View Room" are both DOUBLE, so they intentionally
// share a look — that's realistic, two hotels' standard doubles do look
// similar); dishes get one photo each, individually chosen. If a URL ever
// 404s, the app's own Image.network errorBuilder falls back to an icon —
// nothing breaks, it just shows a placeholder for that one photo.

const ROOM_TYPE_IMAGES = {
  SINGLE: ['https://images.unsplash.com/photo-1631049307264-da0ec9d70304?w=1200'],
  DOUBLE: ['https://images.unsplash.com/photo-1590490360182-c33d57733427?w=1200'],
  TWIN: ['https://images.unsplash.com/photo-1566665797739-1674de7a421a?w=1200'],
  SUITE: ['https://images.unsplash.com/photo-1595576508898-0ad5c879a061?w=1200'],
  FAMILY: ['https://images.unsplash.com/photo-1560448204-e02f11c3d0e2?w=1200'],
  PENTHOUSE: ['https://images.unsplash.com/photo-1631889993959-41b4e9c6e3cb?w=1200'],
  DORMITORY: ['https://images.unsplash.com/photo-1555854877-bab0e564b8d5?w=1200'],
};

const DISH_IMAGES = {
  'Grilled Nile Perch': 'https://images.unsplash.com/photo-1519708227418-c8fd9a32b7a2?w=1200',
  'Kempinski Breakfast Buffet': 'https://images.unsplash.com/photo-1533089860892-a7c6f0a88666?w=1200',
  'Nyama Choma Platter': 'https://images.unsplash.com/photo-1544025162-d76694265947?w=1200',
  'Swahili Coconut Fish Curry': 'https://images.unsplash.com/photo-1585937421612-70a008356fbe?w=1200',
  'Continental Breakfast': 'https://images.unsplash.com/photo-1533920379829-13cbb60ee089?w=1200',
  'Beef Samosas (3pc)': 'https://images.unsplash.com/photo-1601050690597-df0568f70950?w=1200',
  'Karen Blixen Steak': 'https://images.unsplash.com/photo-1600891964599-f61ba0e24092?w=1200',
  'High Tea Set': 'https://images.unsplash.com/photo-1571934811356-5cc061b6821f?w=1200',
  'Safari Breakfast': 'https://images.unsplash.com/photo-1533089860892-a7c6f0a88666?w=1200',
  'Slow-Roasted Lamb Shoulder': 'https://images.unsplash.com/photo-1544025162-d76694265947?w=1200',
  'Avocado & Quinoa Bowl': 'https://images.unsplash.com/photo-1512621776951-a57141f2eefd?w=1200',
  'Artisan Pastry Basket': 'https://images.unsplash.com/photo-1509440159596-0249088772ff?w=1200',
};

// ── Hotel definitions ────────────────────────────────────────────────────
//
// Realistic Nairobi hotels, deliberately varied (price tier, room mix,
// cuisine) so the UI has something genuine to browse/filter/book across.

const HOTELS = [
  {
    // A real place named "Villa Rosa Kempinski" already exists in this
    // system (id below) with zero rooms/dining — seed straight onto it
    // instead of creating a confusing near-duplicate "... Nairobi" place.
    existingPlaceId: 'cmnlqb3430001jp0ajttlw20a',
    name: 'Villa Rosa Kempinski Nairobi',
    shortDescription: 'Nairobi’s only true 5-star luxury hotel, in Westlands.',
    description:
      'An opulent city-centre landmark offering some of the largest rooms in Nairobi, a rooftop pool with skyline views, and award-winning dining — the address of choice for business and leisure travellers alike.',
    address: 'Chiromo Road, Westlands',
    latitude: -1.2634,
    longitude: 36.8087,
    phone: '+254 20 226 6000',
    email: 'reservations.nairobi@kempinski.com',
    website: 'https://www.kempinski.com/en/nairobi',
    coverImage:
      'https://images.unsplash.com/photo-1566073771259-6a8506099945?w=1600',
    images: [
      'https://images.unsplash.com/photo-1564501049412-61c2a3083791?w=1200',
      'https://images.unsplash.com/photo-1551882547-ff40c63fe5fa?w=1200',
    ],
    minPrice: 22000,
    maxPrice: 95000,
    currency: 'KES',
    starRating: 5,
    amenities: ['Rooftop Pool', 'Spa', 'Gym', 'Free WiFi', 'Airport Shuttle', 'Business Centre'],
    rooms: [
      { name: 'Deluxe Room', roomType: 'DOUBLE', basePrice: 22000, maxGuests: 2 },
      { name: 'Executive Suite', roomType: 'SUITE', basePrice: 48000, maxGuests: 3 },
      { name: 'Presidential Suite', roomType: 'PENTHOUSE', basePrice: 95000, maxGuests: 4 },
    ],
    dining: {
      sectionName: 'All-Day Dining',
      items: [
        { name: 'Grilled Nile Perch', price: 3200, mealType: 'DINNER' },
        { name: 'Kempinski Breakfast Buffet', price: 2800, mealType: 'BREAKFAST' },
        { name: 'Nyama Choma Platter', price: 4500, mealType: 'DINNER' },
      ],
    },
  },
  {
    name: 'Sarova Stanley',
    shortDescription: 'Historic landmark hotel in the heart of the CBD since 1902.',
    description:
      'One of Nairobi’s oldest and most storied hotels, blending colonial-era heritage with modern comfort, steps from the city’s business and shopping districts.',
    address: 'Kimathi Street, CBD',
    latitude: -1.2837,
    longitude: 36.8228,
    phone: '+254 20 275 7000',
    email: 'stanley@sarovahotels.com',
    website: 'https://www.sarovahotels.com/stanley-nairobi',
    coverImage:
      'https://images.unsplash.com/photo-1551632811-561732d1e306?w=1600',
    images: [
      'https://images.unsplash.com/photo-1445019980597-93fa8acb246c?w=1200',
    ],
    minPrice: 14000,
    maxPrice: 38000,
    currency: 'KES',
    starRating: 4,
    amenities: ['Pool', 'Gym', 'Free WiFi', '24-Hour Front Desk'],
    rooms: [
      { name: 'Classic Room', roomType: 'DOUBLE', basePrice: 14000, maxGuests: 2 },
      { name: 'Stanley Suite', roomType: 'SUITE', basePrice: 32000, maxGuests: 2 },
      { name: 'Family Room', roomType: 'FAMILY', basePrice: 24000, maxGuests: 4 },
    ],
    dining: {
      sectionName: 'Thorn Tree Cafe',
      items: [
        { name: 'Swahili Coconut Fish Curry', price: 2600, mealType: 'LUNCH' },
        { name: 'Continental Breakfast', price: 1800, mealType: 'BREAKFAST' },
        { name: 'Beef Samosas (3pc)', price: 900, mealType: 'SNACK' },
      ],
    },
  },
  {
    name: 'Fairmont The Norfolk',
    shortDescription: 'Iconic safari-heritage hotel bordering the University of Nairobi.',
    description:
      'A legendary East African institution since 1904, set in lush gardens with a colonial-safari ambience, favoured by adventurers and dignitaries alike.',
    address: 'Harry Thuku Road, CBD',
    latitude: -1.2795,
    longitude: 36.8172,
    phone: '+254 20 226 5555',
    email: 'norfolk@fairmont.com',
    website: 'https://www.fairmont.com/norfolk-nairobi',
    coverImage:
      'https://images.unsplash.com/photo-1582719478250-c89cae4dc85b?w=1600',
    images: [
      'https://images.unsplash.com/photo-1590490360182-c33d57733427?w=1200',
    ],
    minPrice: 18000,
    maxPrice: 55000,
    currency: 'KES',
    starRating: 5,
    amenities: ['Garden Pool', 'Spa', 'Gym', 'Free WiFi', 'Airport Shuttle'],
    rooms: [
      { name: 'Garden View Room', roomType: 'DOUBLE', basePrice: 18000, maxGuests: 2 },
      { name: 'Colonial Suite', roomType: 'SUITE', basePrice: 42000, maxGuests: 3 },
      { name: 'Single Traveller Room', roomType: 'SINGLE', basePrice: 15000, maxGuests: 1 },
    ],
    dining: {
      sectionName: 'The Ibis Grill',
      items: [
        { name: 'Karen Blixen Steak', price: 3800, mealType: 'DINNER' },
        { name: 'High Tea Set', price: 2200, mealType: 'SNACK' },
        { name: 'Safari Breakfast', price: 2400, mealType: 'BREAKFAST' },
      ],
    },
  },
  {
    name: 'Tribe Hotel',
    shortDescription: 'Boutique contemporary-art hotel in Village Market, Gigiri.',
    description:
      'A design-forward boutique hotel set among Nairobi’s embassy district, known for its curated contemporary African art collection and rooftop infinity pool.',
    address: 'Village Market, Limuru Road, Gigiri',
    latitude: -1.2306,
    longitude: 36.8064,
    phone: '+254 20 720 6000',
    email: 'reservations@tribe-hotel.com',
    website: 'https://www.tribe-hotel.com',
    coverImage:
      'https://images.unsplash.com/photo-1611892440504-42a792e24d32?w=1600',
    images: [
      'https://images.unsplash.com/photo-1611892440504-42a792e24d32?w=1200',
    ],
    minPrice: 20000,
    maxPrice: 60000,
    currency: 'KES',
    starRating: 5,
    amenities: ['Infinity Pool', 'Spa', 'Gym', 'Free WiFi', 'Art Gallery'],
    rooms: [
      { name: 'Studio Room', roomType: 'DOUBLE', basePrice: 20000, maxGuests: 2 },
      { name: 'Loft Suite', roomType: 'SUITE', basePrice: 42000, maxGuests: 2 },
      { name: 'Tribe Exclusive Penthouse', roomType: 'PENTHOUSE', basePrice: 60000, maxGuests: 4 },
    ],
    dining: {
      sectionName: 'Tatu Restaurant',
      items: [
        { name: 'Slow-Roasted Lamb Shoulder', price: 3600, mealType: 'DINNER' },
        { name: 'Avocado & Quinoa Bowl', price: 1900, mealType: 'LUNCH' },
        { name: 'Artisan Pastry Basket', price: 1200, mealType: 'BREAKFAST' },
      ],
    },
  },
];

// ── Place creation (REST API) ────────────────────────────────────────────

async function createOrGetPlace(city, accommodationCategory, hotel) {
  if (hotel.existingPlaceId) {
    log(`Using existing real place for "${hotel.name}":`, hotel.existingPlaceId);
    const json = await api('GET', `/api/places/${hotel.existingPlaceId}`);
    return { place: unwrap(json), isNew: false };
  }

  const existing = await findExistingPlace(city.id, hotel.name);
  if (existing) {
    log(`Place "${hotel.name}" already exists:`, existing.id);
    return { place: existing, isNew: false };
  }

  if (DRY_RUN) {
    log(`[dry-run] would create place "${hotel.name}"`);
    return { place: { id: `dry-run-${hotel.name}` }, isNew: true };
  }

  log(`Creating place "${hotel.name}"…`);
  let place = unwrap(
    await api('POST', '/api/places', {
      name: hotel.name,
      cityId: city.id,
      primaryCategory: accommodationCategory.slug,
    }),
  );
  const id = place.id;

  await api('PATCH', `/api/places/${id}`, {
    shortDescription: hotel.shortDescription,
    description: hotel.description,
  });

  await api('PATCH', `/api/places/${id}/location`, {
    address: hotel.address,
    latitude: hotel.latitude,
    longitude: hotel.longitude,
  });

  await api('PATCH', `/api/places/${id}/contact`, {
    contact: { phone: hotel.phone, email: hotel.email, website: hotel.website },
  });

  await api('PATCH', `/api/places/${id}/attributes`, {
    attributes: {
      starRating: hotel.starRating,
      generalAmenities: hotel.amenities,
      checkInTime: '14:00',
      checkOutTime: '11:00',
    },
  });

  await api('PATCH', `/api/places/${id}/media`, {
    coverImage: hotel.coverImage,
    images: hotel.images.map((url, i) => ({ url, order: i + 1 })),
  });

  await api('PATCH', `/api/places/${id}/booking`, {
    isBookable: true,
    pricing: { min: hotel.minPrice, max: hotel.maxPrice, unit: 'PER_NIGHT', currency: hotel.currency },
    bookingSettings: { cancellationPolicy: 'moderate' },
  });

  await api('PUT', `/api/places/${id}/categories`, {
    categoryIds: [accommodationCategory.id],
  });

  try {
    await api('GET', `/api/places/${id}/submit`); // validate
    place = unwrap(await api('POST', `/api/places/${id}/submit`, {}));
    log(`Submitted "${hotel.name}" — status=${place.status || 'unknown'}`);
  } catch (err) {
    warn(`Could not submit "${hotel.name}" (left as draft):`, err.message);
  }

  return { place, isNew: true };
}

// ── Rooms / dining (Firestore, via Admin SDK) ────────────────────────────

async function seedRoomsAndDining(db, placeId, hotel) {
  const roomsCol = db.collection('Rooms');
  const existingRooms = await roomsCol.where('placeId', '==', placeId).get();
  const existingRoomByName = new Map(
    existingRooms.docs.map((d) => [d.data().name, d]),
  );

  for (const room of hotel.rooms) {
    const images = ROOM_TYPE_IMAGES[room.roomType] || [hotel.coverImage];
    const existingDoc = existingRoomByName.get(room.name);

    if (existingDoc) {
      if (DRY_RUN) {
        log(`  [dry-run] would update images for room "${room.name}"`);
        continue;
      }
      await roomsCol.doc(existingDoc.id).update({
        images,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      log(`  Updated images for room "${room.name}"`);
      continue;
    }

    if (DRY_RUN) {
      log(`  [dry-run] would create room "${room.name}"`);
      continue;
    }
    await roomsCol.add({
      placeId,
      name: room.name,
      description: `${room.name} at ${hotel.name}.`,
      roomType: room.roomType,
      maxGuests: room.maxGuests,
      maxAdults: room.maxGuests,
      maxChildren: 0,
      hasBalcony: room.roomType === 'SUITE' || room.roomType === 'PENTHOUSE',
      hasKitchen: room.roomType === 'PENTHOUSE',
      hasLivingRoom: room.roomType === 'SUITE' || room.roomType === 'PENTHOUSE',
      amenities: ['Free WiFi', 'Air Conditioning', 'Room Service'],
      basePrice: room.basePrice,
      currency: hotel.currency,
      isAvailable: true,
      images,
      beds: [{ bedType: room.maxGuests > 2 ? 'QUEEN' : 'DOUBLE', quantity: 1 }],
      sortOrder: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    log(`  Created room "${room.name}"`);
  }

  const sectionsCol = db.collection('MenuSections');
  const existingSections = await sectionsCol.where('placeId', '==', placeId).get();
  let section = existingSections.docs.find(
    (d) => d.data().name === hotel.dining.sectionName,
  );

  let sectionId;
  if (section) {
    sectionId = section.id;
    log(`  Menu section "${hotel.dining.sectionName}" already exists — skipping`);
  } else if (DRY_RUN) {
    log(`  [dry-run] would create menu section "${hotel.dining.sectionName}"`);
    sectionId = 'dry-run-section';
  } else {
    const ref = await sectionsCol.add({
      placeId,
      name: hotel.dining.sectionName,
      sortOrder: 0,
      isActive: true,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    sectionId = ref.id;
    log(`  Created menu section "${hotel.dining.sectionName}"`);
  }

  const itemsCol = db.collection('MenuItems');
  const existingItems = await itemsCol.where('placeId', '==', placeId).get();
  const existingItemByName = new Map(
    existingItems.docs.map((d) => [d.data().name, d]),
  );

  for (const item of hotel.dining.items) {
    const image = DISH_IMAGES[item.name];
    const images = image ? [image] : [];
    const existingDoc = existingItemByName.get(item.name);

    if (existingDoc) {
      if (DRY_RUN) {
        log(`  [dry-run] would update images for menu item "${item.name}"`);
        continue;
      }
      await itemsCol.doc(existingDoc.id).update({
        images,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
      });
      log(`  Updated images for menu item "${item.name}"`);
      continue;
    }

    if (DRY_RUN) {
      log(`  [dry-run] would create menu item "${item.name}"`);
      continue;
    }
    await itemsCol.add({
      placeId,
      sectionId,
      name: item.name,
      description: `${item.name} — a signature dish at ${hotel.name}.`,
      mealType: item.mealType,
      ingredients: [],
      allergens: [],
      dietaryOptions: [],
      spicyLevel: 0,
      isVegetarian: false,
      isVegan: false,
      isGlutenFree: false,
      price: item.price,
      currency: hotel.currency,
      isAvailable: true,
      isSignatureDish: false,
      isChefSpecial: false,
      images,
      sortOrder: 0,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    log(`  Created menu item "${item.name}"`);
  }
}

// ── Main ──────────────────────────────────────────────────────────────────

async function main() {
  log(DRY_RUN ? 'DRY RUN — no writes will be made.' : 'Live run.');

  await login();
  const city = await ensureNairobi();

  // Matches "Accom" so it catches both the correct spelling and the
  // "Accomodation" typo that exists live in this system's category catalog.
  const accommodationCategory = await findCategoryByName('Accom');
  if (!accommodationCategory) {
    throw new Error(
      'Could not find an active Accommodation-like category via GET /api/categories — create one first (admin_categories_screen.dart) or adjust the match in this script.',
    );
  }
  log('Using Accommodation category:', accommodationCategory.id);

  if (!DRY_RUN) {
    admin.initializeApp({ credential: admin.credential.applicationDefault() });
  }
  const db = DRY_RUN ? null : admin.firestore();

  for (const hotel of HOTELS) {
    log('---', hotel.name, '---');
    const { place } = await createOrGetPlace(city, accommodationCategory, hotel);
    if (!DRY_RUN) {
      await seedRoomsAndDining(db, place.id, hotel);
    } else {
      log(`  [dry-run] would seed ${hotel.rooms.length} rooms + ${hotel.dining.items.length} menu items`);
    }
  }

  log('Done.');
}

main().catch((err) => {
  console.error('[seed] FAILED:', err);
  process.exitCode = 1;
});
