require('dotenv').config();
const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_KEY) {
    console.error("❌ Error: Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env");
    process.exit(1);
}

const supabase = createClient(SUPABASE_URL, SERVICE_KEY);

const ROUTES_DIR = './routes';

async function bulkImport() {
  console.log("🚀 Starting Bulk Import...");

  // 1. Get all files from the folder
  let files = [];
  try {
    files = fs.readdirSync(ROUTES_DIR).filter(file => file.endsWith('.geojson'));
  } catch (err) {
    console.error(`❌ Error reading directory: ${err.message}`);
    return;
  }

  if (files.length === 0) {
    console.log("No .geojson files found in /routes folder!");
    return;
  }

  for (const file of files) {
    const filePath = path.join(ROUTES_DIR, file);

    // 2. BETTER CLEANING LOGIC:
    // - Removes "ROUTE #", "Route -", etc.
    // - Keeps the numbers (e.g. "1", "10", "06")
    // - Removes extension
    const cleanName = file
      .replace('.geojson', '')        // Remove extension
      .replace(/^ROUTE\s*#?\s*-?\s*/i, '') // Remove "ROUTE #", "Route -", case insensitive
      .trim()
      .toUpperCase();                 // Standardize to uppercase

    console.log(`\n📂 Processing: ${cleanName} (from ${file})`);

    const fileContent = fs.readFileSync(filePath, 'utf8');
    let geojson;

    try {
        geojson = JSON.parse(fileContent);
    } catch (err) {
        console.error(`   ❌ Failed to parse JSON in ${file}`);
        continue;
    }

    // 3. Robust Feature Check
    // Handles if the file is a "FeatureCollection" OR just a single "Feature"
    const features = geojson.features || (geojson.type === 'Feature' ? [geojson] : []);

    for (const feature of features) {
      // Use the color from the file, or default to black
      const color = feature.properties?.stroke || '#000000';
      // Attempt to find formal name, fallback to cleanName
      const formalName = feature.properties?.formal_name || feature.properties?.name || cleanName;
      const geometry = feature.geometry;

      if (!geometry) {
          console.warn('   ⚠️  Skipping a feature with no geometry.');
          continue;
      }

      // 4. Upload to Supabase
      // Using named parameters to match the RPC function we will create
      const { error } = await supabase.rpc('insert_route', {
        p_route_name: cleanName,
        p_formal_name: formalName,
        p_color: color,
        p_geo_json: geometry
      });

      if (error) {
        console.error(`   ❌ Failed to upload: ${error.message}`);
      } else {
        console.log(`   ✅ Uploaded`);
      }
    }
  }
  console.log("\n✨ All done!");
}

bulkImport();
