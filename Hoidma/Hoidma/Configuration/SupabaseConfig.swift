import Foundation
import Supabase

/// Centralized Supabase configuration
///
/// SECURITY NOTES:
/// ===============
///
/// 1. ANONYMOUS KEY (anonKey):
///    - This key is SAFE to expose in client code
///    - It only provides access that Row Level Security (RLS) policies allow
///    - Without RLS, this key would grant full table access - NEVER disable RLS!
///
/// 2. ROW LEVEL SECURITY (RLS) - CRITICAL:
///    - ALL tables MUST have RLS enabled in Supabase dashboard
///    - RLS policies MUST verify user ownership (auth.uid() = user_id)
///    - Without RLS, any client could read/write any data
///
///    Required RLS policies for each table:
///    - users: SELECT/UPDATE where auth.uid() = auth_user_id
///    - stocks: SELECT/INSERT/UPDATE/DELETE where user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid())
///    - stock_lots: SELECT/INSERT/UPDATE/DELETE via foreign key to stocks
///
/// 3. NEVER commit service_role key (admin key) to source code
///    - The service_role key bypasses all RLS
///    - Only use it in secure server-side environments
///
/// 4. PROJECT URL:
///    - Safe to expose - it's just the project identifier
///    - All security comes from RLS and authentication
///
enum SupabaseConfig {
    // MARK: - Configuration

    /// Supabase project URL
    /// This is safe to expose - security is enforced by RLS policies
    static let projectURL: URL = {
        guard let url = URL(string: "https://pndawkqbdqrappqjsltz.supabase.co") else {
            fatalError("Invalid Supabase project URL")
        }
        return url
    }()

    /// Supabase anonymous/public key
    ///
    /// SECURITY: This key is safe to expose ONLY because:
    /// 1. Row Level Security (RLS) is enabled on ALL tables
    /// 2. RLS policies verify user ownership
    /// 3. Users can only access their own data
    ///
    /// If RLS were disabled, this key would grant full database access!
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBuZGF3a3FiZHFyYXBwcWpzbHR6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg3NjE0OTgsImV4cCI6MjA4NDMzNzQ5OH0.dpSo7uVlAUtU3Xtd3RM009fHdfMSDuUxYWcKARu44js"

    // MARK: - Supabase Client

    /// Shared Supabase client instance
    /// Configured with auto-refresh tokens for seamless authentication
    static let client: SupabaseClient = {
        SupabaseClient(
            supabaseURL: projectURL,
            supabaseKey: anonKey,
            options: SupabaseClientOptions(
                auth: SupabaseClientOptions.AuthOptions(
                    autoRefreshToken: true,
                    emitLocalSessionAsInitialSession: true
                )
            )
        )
    }()

    // MARK: - Security Validation

    /// Verify that required RLS policies are likely in place
    /// This is a client-side reminder - actual verification must be done in Supabase dashboard
    static func logSecurityReminder() {
        #if DEBUG
        AppLogger.info("""
        ⚠️ SUPABASE SECURITY CHECKLIST:
        1. Verify RLS is ENABLED on: users, stocks, stock_lots tables
        2. Verify RLS policies check user ownership
        3. Test that users cannot access other users' data
        4. Never use service_role key in client code
        """)
        #endif
    }
}

// MARK: - RLS Policy Reference
/*
 REQUIRED ROW LEVEL SECURITY POLICIES:

 -- users table
 ALTER TABLE users ENABLE ROW LEVEL SECURITY;

 CREATE POLICY "Users can view own record"
   ON users FOR SELECT
   USING (auth.uid() = auth_user_id);

 CREATE POLICY "Users can update own record"
   ON users FOR UPDATE
   USING (auth.uid() = auth_user_id);

 -- stocks table
 ALTER TABLE stocks ENABLE ROW LEVEL SECURITY;

 CREATE POLICY "Users can view own stocks"
   ON stocks FOR SELECT
   USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

 CREATE POLICY "Users can insert own stocks"
   ON stocks FOR INSERT
   WITH CHECK (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

 CREATE POLICY "Users can update own stocks"
   ON stocks FOR UPDATE
   USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

 CREATE POLICY "Users can delete own stocks"
   ON stocks FOR DELETE
   USING (user_id IN (SELECT id FROM users WHERE auth_user_id = auth.uid()));

 -- stock_lots table (inherits through foreign key)
 ALTER TABLE stock_lots ENABLE ROW LEVEL SECURITY;

 CREATE POLICY "Users can view own stock lots"
   ON stock_lots FOR SELECT
   USING (stock_id IN (
     SELECT s.id FROM stocks s
     JOIN users u ON s.user_id = u.id
     WHERE u.auth_user_id = auth.uid()
   ));

 CREATE POLICY "Users can insert own stock lots"
   ON stock_lots FOR INSERT
   WITH CHECK (stock_id IN (
     SELECT s.id FROM stocks s
     JOIN users u ON s.user_id = u.id
     WHERE u.auth_user_id = auth.uid()
   ));

 CREATE POLICY "Users can update own stock lots"
   ON stock_lots FOR UPDATE
   USING (stock_id IN (
     SELECT s.id FROM stocks s
     JOIN users u ON s.user_id = u.id
     WHERE u.auth_user_id = auth.uid()
   ));

 CREATE POLICY "Users can delete own stock lots"
   ON stock_lots FOR DELETE
   USING (stock_id IN (
     SELECT s.id FROM stocks s
     JOIN users u ON s.user_id = u.id
     WHERE u.auth_user_id = auth.uid()
   ));
*/
