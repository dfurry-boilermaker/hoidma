# Hoidma Project Memory

## Project Overview
iOS stock portfolio app with Supabase backend, biometric authentication, and real-time price updates.

## Architecture Decisions

### Authentication
- **Method:** Email OTP via Supabase (no passwords stored)
- **Session:** Auto-refresh enabled, foreground re-validation
- **Storage:** Email in Keychain, tokens managed by Supabase SDK
- **Biometrics:** Face ID/Touch ID with device passcode fallback

### Data Storage
- **Cloud:** Supabase with RLS policies (MUST verify enabled in dashboard)
- **Local:** UserDefaults for portfolio (consider migrating to encrypted storage)
- **Secrets:** Environment variables for API keys (never hardcode)

### API Integrations
- **Polygon.io:** Primary price source (Starter tier: $29/mo, unlimited calls, 5 years historical data)
- **Yahoo Finance:** Fallback price source (unofficial, no SLA) - used only when Polygon fails
- **Financial Modeling Prep:** Fundamental data (250 req/day) - currently experiencing 403 errors

## Security Patterns

### Already Implemented
- Keychain storage with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
- OTP rate limiting (5 attempts/code, 10 total, 30-min lockout)
- API rate limiting with exponential backoff
- Sanitized error messages (no internal details)
- Input validation (RFC 5322 email, ticker normalization)
- HTTPS enforcement via URLComponents

### Required for Production
- Verify Supabase RLS is ENABLED for: users, stocks, stock_lots
- Configure API keys in Xcode scheme or Info.plist
- Consider certificate pinning for financial data

## Security Audit Findings

### Issues Requiring Attention

#### 1. Portfolio Data in UserDefaults (MEDIUM)
**File:** `StockViewModel.swift:100-101, 166`
**Problem:** Stock holdings stored unencrypted in UserDefaults
**Risk:** Portfolio visible to attackers with device access
**Recommendation:** Migrate to Keychain or encrypted Core Data for sensitive financial data

#### 2. No RLS Verification on Startup (HIGH)
**File:** `SupabaseConfig.swift:14-156`
**Problem:** App documents RLS policies but cannot verify they're actually enabled
**Risk:** If RLS accidentally disabled, users could access each other's data
**Recommendation:** Add startup validation that tests RLS enforcement

#### 3. User-Agent String (LOW)
**File:** `StockAPIService.swift:185`
**Problem:** Generic macOS User-Agent instead of iOS
**Recommendation:** Use proper iOS User-Agent or let URLSession default

## Code Conventions

### Async/Await
- Use `[weak self]` in closures to prevent retain cycles
- Track tasks with `trackTask()` for proper cancellation
- Call `cancelAllTasks()` in deinit

### SwiftUI Views
- Avoid expensive computed properties (O(n²) sorting)
- Move calculations to ViewModel as @Published properties
- Use `.task` modifier for async work, not `.onAppear`

### Error Handling
- Map errors to user-safe messages via `mapErrorToSafeMessage()`
- Log warnings/errors but not sensitive data
- Use retry logic for transient network failures

## Known Technical Debt

### Performance (HIGH Priority)
- [ ] Move JSON parsing off main thread (`StockAPIService.swift:319-376`)
- [ ] Fix O(n²) sorting in views (`PortfolioView.swift:29-48`)
- [ ] Fix O(n²) account summaries (`PortfolioVisualizationsView.swift:16-66`)
- [ ] Cache historical prices (`StockAPIService.swift:701-735`)
- [ ] Cache ETF status with 24-hour TTL (`StockAPIService.swift:467-516`)
- [x] Migrate to Polygon.io Starter tier (unlimited API calls) - COMPLETED 2026-02-04

### Performance (MEDIUM Priority)
- [ ] Fix unbounded activeTasks array (`StockViewModel.swift:30, 78-96`)
- [ ] Explicitly cancel timer (`StockViewModel.swift:12, 69-73`)
- [ ] Fix async deinit race condition (`SupabaseManager.swift:202-209`)
- [ ] Optimize Calendar operations in loop (`StockViewModel.swift:310-387`)
- [ ] Add task cleanup on view disappear (`StockViewModel.swift:78-96`)
- [ ] Add jitter to exponential backoff

### Security
- [ ] Migrate portfolio data from UserDefaults to encrypted storage
- [ ] Add RLS verification on app startup
- [ ] Implement certificate pinning

## File Reference

| Purpose | File |
|---------|------|
| Auth Manager | SupabaseAuthManager.swift |
| Data Manager | SupabaseManager.swift |
| Stock Prices | StockAPIService.swift |
| Rate Limiting | Utilities/RateLimiter.swift |
| Keychain | Utilities/KeychainHelper.swift |
| API Config | Configuration/APIConfig.swift |
| Supabase Config | Configuration/SupabaseConfig.swift |
| Environment | Utilities/Environment.swift |

## Polygon.io Migration (Phase 1 Complete)

### Implementation Status
- [x] Database migration (002_polygon_data_model.sql) - Added OHLCV columns
- [x] Polygon.io data models (PolygonLastTrade, PolygonAggregates, etc.)
- [x] API configuration updated (Starter tier = unlimited calls)
- [x] Rate limiter updated (Int.max for Polygon endpoint)
- [x] New API methods (fetchPriceFromPolygon, fetchHistoricalBarsFromPolygon)
- [x] Primary fetchStockData() uses Polygon first, Yahoo fallback
- [x] Edge Function (fetch-prices-polygon/index.ts) for server-side updates

### Deployment Steps
1. Run database migration: `supabase db push`
2. Set Polygon API key: `supabase secrets set POLYGON_API_KEY=your_starter_key`
3. Deploy Edge Function: `supabase functions deploy fetch-prices-polygon`
4. Update cron job in Supabase dashboard to use fetch-prices-polygon
5. Monitor logs for data source usage (should see "✅ Fetched X from Polygon.io (primary)")

### Monitoring
- Check Polygon API usage in dashboard (should be well below limits)
- Verify stock_prices.data_source = 'polygon' in database
- Monitor fallback rate (target: < 1% using Yahoo)
- Compare prices between Polygon and Yahoo (should be within 0.1%)

### Rollback Plan
If issues arise, set `USE_POLYGON_PRIMARY = false` in StockAPIService.swift or switch cron back to fetch-prices Edge Function.

## Deployment Checklist

Before TestFlight:
- [ ] iOS deployment target = 17.0 (not 26.0)
- [ ] useLocalStorage = false (Environment.swift)
- [ ] API keys configured for Release build (including POLYGON_API_KEY)
- [ ] RLS verified in Supabase dashboard
- [ ] Polygon.io database migration applied
- [ ] Polygon Edge Function deployed with API key secret
