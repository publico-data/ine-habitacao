const geoData = require('./geojson_compras_updated.json');
const historicalData = require('./dados_ine_combined.json');

// Get latest period data to find municipality names
const indicatorCodes = Object.keys(historicalData);
const latestIndicator = indicatorCodes[0];
const latestPeriod = historicalData[latestIndicator];
const dadosKey = Object.keys(latestPeriod[0].Dados)[0];
const locations = latestPeriod[0].Dados[dadosKey];

// Build geocode to name map for municipalities
const geocodeToName = {};
locations.forEach(loc => {
  if (loc.geocod && loc.geocod.length <= 7) {
    geocodeToName[loc.geocod] = loc.geodsg;
  }
});

// Find all freguesias (geocode > 7 chars) and group by municipality
const municipalityFreguesias = {};

geoData.features.forEach(f => {
  const geocode = f.properties.geocode;
  if (geocode && geocode.length > 7) {
    const munCode = geocode.substring(0, 7);
    if (!municipalityFreguesias[munCode]) {
      municipalityFreguesias[munCode] = {
        code: munCode,
        name: geocodeToName[munCode] || 'Unknown',
        freguesias: []
      };
    }
    municipalityFreguesias[munCode].freguesias.push(f.properties.lugar);
  }
});

// Print municipalities with multiple freguesias
console.log('Municipalities split into freguesias:\n');
const splitMunicipalities = Object.values(municipalityFreguesias)
  .filter(mun => mun.freguesias.length > 1)
  .sort((a, b) => b.freguesias.length - a.freguesias.length);

splitMunicipalities.forEach(mun => {
  console.log(`- ${mun.name} (${mun.code}): ${mun.freguesias.length} freguesias`);
});

console.log(`\nTotal: ${splitMunicipalities.length} municipalities split into freguesias\n`);

// Output as JavaScript array for quickAccessCities
console.log('For quickAccessCities array:\n');
splitMunicipalities.forEach(mun => {
  const nameTitleCase = mun.name.split(' ').map(word =>
    word.charAt(0).toUpperCase() + word.slice(1).toLowerCase()
  ).join(' ');
  console.log(`    { id: '${mun.name.toLowerCase().replace(/\s+/g, '-')}', name: '${nameTitleCase}', geocodPrefix: '${mun.code}', isMunicipality: true },`);
});
