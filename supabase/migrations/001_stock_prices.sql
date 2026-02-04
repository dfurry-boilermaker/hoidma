-- Migration: Create stock_prices and tracked_stocks tables
-- This enables server-side stock price caching to support multiple users
-- without hitting API rate limits

-- ============================================================================
-- stock_prices table: Stores cached stock prices from Yahoo Finance
-- ============================================================================
CREATE TABLE IF NOT EXISTS stock_prices (
  ticker TEXT PRIMARY KEY,
  price DECIMAL(12,4) NOT NULL,
  previous_close DECIMAL(12,4),
  day_change_percent DECIMAL(8,4),
  company_name TEXT,
  beta DECIMAL(6,4),
  is_etf BOOLEAN DEFAULT false,
  updated_at TIMESTAMPTZ DEFAULT NOW(),
  -- Period changes (populated less frequently, may be null initially)
  change_1w DECIMAL(8,4),
  change_1m DECIMAL(8,4),
  change_3m DECIMAL(8,4),
  change_ytd DECIMAL(8,4)
);

-- Index for fast lookups by update time (useful for finding stale data)
CREATE INDEX IF NOT EXISTS idx_stock_prices_updated ON stock_prices(updated_at);

-- Enable Row Level Security
-- All authenticated users can read stock prices (public data)
ALTER TABLE stock_prices ENABLE ROW LEVEL SECURITY;

-- Policy: Any authenticated user can read stock prices
CREATE POLICY "Anyone can read stock prices" ON stock_prices
  FOR SELECT
  TO authenticated
  USING (true);

-- Policy: Only service role can insert/update (Edge Functions use service role)
-- This prevents users from manipulating prices
CREATE POLICY "Service role can manage stock prices" ON stock_prices
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- tracked_stocks table: Aggregates all tickers that users are tracking
-- ============================================================================
CREATE TABLE IF NOT EXISTS tracked_stocks (
  ticker TEXT PRIMARY KEY,
  user_count INTEGER DEFAULT 1,
  last_requested TIMESTAMPTZ DEFAULT NOW()
);

-- Enable Row Level Security
ALTER TABLE tracked_stocks ENABLE ROW LEVEL SECURITY;

-- Policy: Any authenticated user can read tracked stocks
CREATE POLICY "Anyone can read tracked stocks" ON tracked_stocks
  FOR SELECT
  TO authenticated
  USING (true);

-- Policy: Only service role can manage tracked stocks
CREATE POLICY "Service role can manage tracked stocks" ON tracked_stocks
  FOR ALL
  TO service_role
  USING (true)
  WITH CHECK (true);

-- ============================================================================
-- Trigger: Auto-update tracked_stocks when users add/remove stocks
-- ============================================================================
CREATE OR REPLACE FUNCTION update_tracked_stocks()
RETURNS TRIGGER AS $$
BEGIN
  IF TG_OP = 'INSERT' THEN
    -- Add or increment user count for this ticker
    INSERT INTO tracked_stocks (ticker, user_count, last_requested)
    VALUES (NEW.ticker, 1, NOW())
    ON CONFLICT (ticker) DO UPDATE
    SET user_count = tracked_stocks.user_count + 1,
        last_requested = NOW();
    RETURN NEW;
  ELSIF TG_OP = 'DELETE' THEN
    -- Decrement user count
    UPDATE tracked_stocks
    SET user_count = user_count - 1
    WHERE ticker = OLD.ticker;
    -- Clean up if no users track this stock anymore
    DELETE FROM tracked_stocks
    WHERE ticker = OLD.ticker AND user_count <= 0;
    RETURN OLD;
  END IF;
  RETURN NULL;
END;
$$ LANGUAGE plpgsql SECURITY DEFINER;

-- Create trigger on stocks table (fires when users add/remove stocks)
DROP TRIGGER IF EXISTS on_stock_change ON stocks;
CREATE TRIGGER on_stock_change
AFTER INSERT OR DELETE ON stocks
FOR EACH ROW EXECUTE FUNCTION update_tracked_stocks();

-- ============================================================================
-- Initial population: Add existing stocks to tracked_stocks
-- ============================================================================
INSERT INTO tracked_stocks (ticker, user_count, last_requested)
SELECT ticker, COUNT(*) as user_count, NOW() as last_requested
FROM stocks
GROUP BY ticker
ON CONFLICT (ticker) DO UPDATE
SET user_count = EXCLUDED.user_count,
    last_requested = NOW();

-- ============================================================================
-- Comments for documentation
-- ============================================================================
COMMENT ON TABLE stock_prices IS 'Cached stock prices fetched by Edge Function from Yahoo Finance';
COMMENT ON TABLE tracked_stocks IS 'Aggregated list of all tickers tracked by any user';
COMMENT ON FUNCTION update_tracked_stocks() IS 'Maintains tracked_stocks table when users add/remove stocks';
