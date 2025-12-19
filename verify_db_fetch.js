require('dotenv').config();
const SUPABASE_URL = process.env.SUPABASE_URL;
const SERVICE_KEY = process.env.SUPABASE_SERVICE_ROLE_KEY;

if (!SUPABASE_URL || !SERVICE_KEY) {
    console.error("❌ Error: Missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY in .env");
    process.exit(1);
}

async function verify() {
  const url = `${SUPABASE_URL}/rest/v1/routes?select=*&limit=1`;
  try {
    const response = await fetch(url, {
      headers: {
        'apikey': SERVICE_KEY,
        'Authorization': `Bearer ${SERVICE_KEY}`
      }
    });

    if (!response.ok) {
      console.error('Error fetching routes:', response.status, response.statusText);
      const text = await response.text();
      console.error('Response:', text);
      return;
    }

    const data = await response.json();
    console.log('Routes table check:', data.length > 0 ? 'Data found' : 'Table empty');
    if (data.length > 0) {
      console.log('Sample row keys:', Object.keys(data[0]));
      // Check path format
      if (data[0].path) {
          console.log('Path column exists.');
          console.log('Path sample (start):', data[0].path.substring(0, 50));
      } else {
          console.log('Path column MISSING in sample.');
      }
    }
  } catch (error) {
    console.error('Fetch error:', error);
  }
}

verify();
