const { createClient } = require('@supabase/supabase-js');
const fs = require('fs');
const path = require('path');

// ⚠️ REPLACE THESE WITH YOUR ACTUAL KEYS
const SUPABASE_URL = 'https://cgxvfhxdiqpmnfpktjvr.supabase.co';
const SERVICE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNneHZmaHhkaXFwbW5mcGt0anZyIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NjA2ODAyOCwiZXhwIjoyMDgxNjQ0MDI4fQ.zF1b_U4daAyEBUQ90MoAO7uji8B2sfFZfZ5_lVPqing'; 

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
      const geometry = feature.geometry;

      if (!geometry) {
          console.warn('   ⚠️  Skipping a feature with no geometry.');
          continue;
      }

      // 4. Upload to Supabase
      const { error } = await supabase.rpc('insert_route', {
        route_name: cleanName,
        route_color: color,
        geo_json: geometry 
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