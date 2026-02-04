-- Migration: Enhanced stock_prices table for Polygon.io OHLCV data
-- Created: 2026-02-04
-- Purpose: Add support for Polygon.io as primary data source with full OHLCV data

-- Enhance stock_prices table with OHLCV (Open, High, Low, Close, Volume) data
ALTER TABLE stock_prices
  ADD COLUMN IF NOT EXISTS volume BIGINT,
  ADD COLUMN IF NOT EXISTS open DECIMAL(12,4),
  ADD COLUMN IF NOT EXISTS high DECIMAL(12,4),
  ADD COLUMN IF NOT EXISTS low DECIMAL(12,4),
  ADD COLUMN IF NOT EXISTS vwap DECIMAL(12,4),
  ADD COLUMN IF NOT EXISTS data_source TEXT DEFAULT 'yahoo',
  ADD COLUMN IF NOT EXISTS market_status TEXT,
  ADD COLUMN IF NOT EXISTS quote_timestamp TIMESTAMPTZ;

-- Add indexes for performance optimization
CREATE INDEX IF NOT EXISTS idx_stock_prices_source ON stock_prices(data_source);
CREATE INDEX IF NOT EXISTS idx_stock_prices_timestamp ON stock_prices(quote_timestamp);
CREATE INDEX IF NOT EXISTS idx_stock_prices_ticker_timestamp ON stock_prices(ticker, quote_timestamp DESC);

-- Add comments for documentation
COMMENT ON COLUMN stock_prices.volume IS 'Trading volume for the period';
COMMENT ON COLUMN stock_prices.open IS 'Opening price';
COMMENT ON COLUMN stock_prices.high IS 'Highest price during period';
COMMENT ON COLUMN stock_prices.low IS 'Lowest price during period';
COMMENT ON COLUMN stock_prices.vwap IS 'Volume Weighted Average Price';
COMMENT ON COLUMN stock_prices.data_source IS 'API source: polygon, yahoo, or fmp';
COMMENT ON COLUMN stock_prices.market_status IS 'Market status: open, closed, extended_hours';
COMMENT ON COLUMN stock_prices.quote_timestamp IS 'Timestamp from the data provider (may differ from updated_at)';

-- Create a function to clean up old price data (keep last 90 days)
CREATE OR REPLACE FUNCTION cleanup_old_prices()
RETURNS void
LANGUAGE plpgsql
AS $$
BEGIN
  DELETE FROM stock_prices
  WHERE updated_at < NOW() - INTERVAL '90 days';
END;
$$;

-- Optional: Schedule cleanup job (uncomment to enable)
-- SELECT cron.schedule('cleanup-old-prices', '0 2 * * *', 'SELECT cleanup_old_prices()');
