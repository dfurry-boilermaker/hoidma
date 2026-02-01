import Foundation
import Supabase

/// Centralized Supabase configuration
enum SupabaseConfig {
    // MARK: - Configuration

    /// Supabase project URL
    static let projectURL = URL(string: "https://pndawkqbdqrappqjsltz.supabase.co")!

    /// Supabase anonymous/public key (safe to expose - RLS protects data)
    static let anonKey = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InBuZGF3a3FiZHFyYXBwcWpzbHR6Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg3NjE0OTgsImV4cCI6MjA4NDMzNzQ5OH0.dpSo7uVlAUtU3Xtd3RM009fHdfMSDuUxYWcKARu44js"

    // MARK: - Supabase Client

    /// Shared Supabase client instance
    static let client: SupabaseClient = {
        SupabaseClient(
            supabaseURL: projectURL,
            supabaseKey: anonKey
        )
    }()
}
