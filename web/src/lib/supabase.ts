import { createClient } from '@supabase/supabase-js';

// Same project the iOS app uses (ios/.../Services/SupabaseService.swift).
// The anon key is a public client key; row-level security protects the data.
export const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL ?? 'https://nzfrxpnksrqcqxphtdye.supabase.co';
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY
  ?? 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im56ZnJ4cG5rc3JxY3F4cGh0ZHllIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQ4OTY4MzQsImV4cCI6MjA5MDQ3MjgzNH0.Te92nt173H8t4nIGBnDMgBWSV-pIGNKzD-BlNx4iNJ8';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true, flowType: 'implicit' },
});

/** Where password-reset emails send web users. Must be allow-listed in Supabase Auth → URL Configuration. */
export const WEB_RESET_REDIRECT = `${window.location.origin}${window.location.pathname}`;
