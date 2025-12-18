const SUPABASE_URL = 'https://cgxvfhxdiqpmnfpktjvr.supabase.co';
const SERVICE_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImNneHZmaHhkaXFwbW5mcGt0anZyIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NjA2ODAyOCwiZXhwIjoyMDgxNjQ0MDI4fQ.zF1b_U4daAyEBUQ90MoAO7uji8B2sfFZfZ5_lVPqing';

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
