/**
 * Consolidate freguesias into municipalities
 * This script merges freguesias of specific municipalities into single features
 * with the municipality name and merged MultiPolygon geometries
 */

import fs from 'fs';

// Input/output files
const INPUT_FILE = 'geojson_compras_updated.json';
const OUTPUT_FILE = 'geojson_compras_updated.json';

// Municipalities that should be consolidated (7-character codes)
// NOTE: Vila Nova de Gaia is NOT here - its freguesias remain separate
// The "União das freguesias de Sandim, Olival, Lever e Crestuma" already exists as a single feature
const CONSOLIDATE_MUNICIPIOS = [
  '11A0104', // Arouca
  '11A0113', // Oliveira de Azeméis
  '11A0109', // Santa Maria da Feira
  '11A0107', // Espinho
  '11A1316', // Vila do Conde
  '11A0119'  // Vale de Cambra
];

console.log('Loading GeoJSON...');
const geojson = JSON.parse(fs.readFileSync(INPUT_FILE, 'utf8'));

console.log(`Total features before consolidation: ${geojson.features.length}`);

// Group features by município code (first 7 chars of geocode)
const municipioGroups = {};

for (const feature of geojson.features) {
  const geocode = feature.properties.geocode;
  if (!geocode || geocode.length < 7) continue;

  const municipioCode = geocode.substring(0, 7);

  // Only group features from municipalities we want to consolidate
  if (CONSOLIDATE_MUNICIPIOS.includes(municipioCode)) {
    if (!municipioGroups[municipioCode]) {
      municipioGroups[municipioCode] = [];
    }
    municipioGroups[municipioCode].push(feature);
  }
}

console.log(`\nFound ${Object.keys(municipioGroups).length} municipalities to consolidate:`);
for (const [code, features] of Object.entries(municipioGroups)) {
  console.log(`  ${code}: ${features.length} features`);
}

// Helper function to extract all polygons from a geometry
function extractPolygons(geometry) {
  if (!geometry) return [];

  if (geometry.type === 'Polygon') {
    return [geometry.coordinates];
  } else if (geometry.type === 'MultiPolygon') {
    return geometry.coordinates;
  }
  return [];
}

// Helper function to find the município-level feature (shortest geocode = no freguesia suffix)
function findMunicipioFeature(features) {
  // The município-level feature has geocode exactly 7 characters long
  // or is the one with the shortest geocode
  let shortest = features[0];
  for (const feature of features) {
    const geocode = feature.properties.geocode || '';
    const shortestGeocode = shortest.properties.geocode || '';
    if (geocode.length < shortestGeocode.length) {
      shortest = feature;
    }
  }
  return shortest;
}

// Consolidate each município
const consolidatedFeatures = [];
const processedMunicipios = new Set();

for (const [municipioCode, features] of Object.entries(municipioGroups)) {
  if (features.length === 0) continue;

  // Find the município-level feature to use as the base
  const municipioFeature = findMunicipioFeature(features);

  // Collect all polygons from all freguesias
  const allPolygons = [];
  for (const feature of features) {
    const polygons = extractPolygons(feature.geometry);
    allPolygons.push(...polygons);
  }

  // Create consolidated feature with MultiPolygon geometry
  const consolidatedFeature = {
    type: 'Feature',
    properties: {
      ...municipioFeature.properties,
      // Ensure the geocode is the município-level code (7 chars)
      geocode: municipioCode
    },
    geometry: {
      type: allPolygons.length === 1 ? 'Polygon' : 'MultiPolygon',
      coordinates: allPolygons.length === 1 ? allPolygons[0] : allPolygons
    }
  };

  consolidatedFeatures.push(consolidatedFeature);
  processedMunicipios.add(municipioCode);

  console.log(`\nConsolidated ${municipioCode} (${municipioFeature.properties.lugar}):`);
  console.log(`  - Merged ${features.length} features into 1`);
  console.log(`  - Combined ${allPolygons.length} polygons`);
}

// Keep all features that are NOT part of consolidated municipalities
const finalFeatures = [];
for (const feature of geojson.features) {
  const geocode = feature.properties.geocode;
  if (!geocode || geocode.length < 7) {
    // Keep features without geocodes
    finalFeatures.push(feature);
    continue;
  }

  const municipioCode = geocode.substring(0, 7);
  if (!processedMunicipios.has(municipioCode)) {
    // This feature is not part of a consolidated município
    finalFeatures.push(feature);
  }
}

// Add all consolidated features
finalFeatures.push(...consolidatedFeatures);

geojson.features = finalFeatures;

console.log(`\n=== Summary ===`);
console.log(`Features before: ${geojson.features.length + consolidatedFeatures.length - consolidatedFeatures.length + municipioGroups[Object.keys(municipioGroups)[0]].length * Object.keys(municipioGroups).length}`);
console.log(`Features after: ${geojson.features.length}`);
console.log(`Consolidated: ${Object.keys(municipioGroups).length} municipalities`);

console.log(`\nSaving to ${OUTPUT_FILE}...`);
fs.writeFileSync(OUTPUT_FILE, JSON.stringify(geojson));

console.log('Done!');
