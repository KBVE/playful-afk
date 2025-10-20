// Supabase configuration
const SUPABASE_URL = 'https://supabase.kbve.com';
const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlIiwiaWF0IjoxNzU1NDAzMjAwLCJleHAiOjE5MTMxNjk2MDB9.oietJI22ZytbghFywvdYMSJp7rcsBdBYbcciJxeGWrg';

// Initialize Supabase client
let supabaseClient = null;

function initializeSupabase() {
	if (typeof supabase === 'undefined') {
		console.error('Supabase library not loaded');
		return null;
	}

	try {
		supabaseClient = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
		console.log('Supabase client initialized successfully');
		return supabaseClient;
	} catch (error) {
		console.error('Error initializing Supabase client:', error);
		return null;
	}
}

// Get the Supabase client instance
function getSupabaseClient() {
	if (!supabaseClient) {
		return initializeSupabase();
	}
	return supabaseClient;
}

// Test connection
async function testSupabaseConnection() {
	const client = getSupabaseClient();
	if (!client) {
		console.error('Supabase client not initialized');
		return false;
	}

	try {
		// Try to get the session (will return null if not authenticated, but confirms connection)
		const { data, error } = await client.auth.getSession();
		if (error) {
			console.error('Supabase connection test failed:', error);
			return false;
		}
		console.log('Supabase connection test successful');
		return true;
	} catch (error) {
		console.error('Supabase connection test error:', error);
		return false;
	}
}
