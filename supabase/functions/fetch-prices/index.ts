import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

// US Market hours: 9:30 AM - 4:00 PM ET (Eastern Time)
function isMarketOpen(): boolean {
  const now = new Date();
  // Convert to Eastern Time
  const etOptions: Intl.DateTimeFormatOptions = {
    timeZone: "America/New_York",
    hour: "numeric",
    minute: "numeric",
    hour12: false,
    weekday: "short",
  };
  const etTime = new Intl.DateTimeFormat("en-US", etOptions).formatToParts(now);

  const weekday = etTime.find((p) => p.type === "weekday")?.value || "";
  const hour = parseInt(etTime.find((p) => p.type === "hour")?.value || "0");
  const minute = parseInt(etTime.find((p) => p.type === "minute")?.value || "0");

  // Weekend check
  if (weekday === "Sat" || weekday === "Sun") {
    return false;
  }

  // Time check (9:30 AM - 4:00 PM ET)
  const timeInMinutes = hour * 60 + minute;
  const marketOpen = 9 * 60 + 30; // 9:30 AM
  const marketClose = 16 * 60; // 4:00 PM

  return timeInMinutes >= marketOpen && timeInMinutes < marketClose;
}

interface YahooChartResponse {
  chart?: {
    result?: Array<{
      meta?: {
        regularMarketPrice?: number;
        previousClose?: number;
        regularMarketPreviousClose?: number;
        chartPreviousClose?: number;
        longName?: string;
        shortName?: string;
      };
      timestamp?: number[];
      indicators?: {
        quote?: Array<{
          close?: (number | null)[];
        }>;
      };
    }>;
  };
}

interface StockPriceData {
  price: number;
  previousClose: number | null;
  companyName: string;
}

async function fetchYahooPrice(ticker: string): Promise<StockPriceData | null> {
  // Use range=2d for more focused data (we only need yesterday's close)
  const url = `https://query1.finance.yahoo.com/v8/finance/chart/${encodeURIComponent(ticker)}?interval=1d&range=2d`;

  try {
    const resp = await fetch(url, {
      headers: {
        "User-Agent":
          "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15",
        Accept: "application/json",
      },
    });

    if (!resp.ok) {
      console.error(`Yahoo API error for ${ticker}: ${resp.status}`);
      return null;
    }

    const data: YahooChartResponse = await resp.json();
    const result = data?.chart?.result?.[0];
    if (!result?.meta) {
      console.error(`No meta data for ${ticker}`);
      return null;
    }

    const meta = result.meta;
    const currentPrice = meta.regularMarketPrice ?? 0;

    // PRIORITY 1: Use meta.previousClose (official previous trading day close)
    let previousClose: number | null = null;

    if (typeof meta.previousClose === "number" && meta.previousClose > 0) {
      previousClose = meta.previousClose;
      console.log(`${ticker}: Using meta.previousClose = ${previousClose}`);
    }
    // PRIORITY 2: Try regularMarketPreviousClose
    else if (
      typeof meta.regularMarketPreviousClose === "number" &&
      meta.regularMarketPreviousClose > 0
    ) {
      previousClose = meta.regularMarketPreviousClose;
      console.log(
        `${ticker}: Using meta.regularMarketPreviousClose = ${previousClose}`
      );
    }
    // PRIORITY 3: Use closes array - ALWAYS use second-to-last for previousClose
    // With daily interval, the array structure is: [..., yesterday, today]
    // count-1 = today's close, count-2 = yesterday's close (what we need)
    else if (result.indicators?.quote?.[0]?.close) {
      const closes = result.indicators.quote[0].close;
      const validCloses = closes.filter((c): c is number => c !== null);

      // With range=2d: [yesterday, today]
      // length-1 = today's close
      // length-2 = yesterday's close <-- THIS IS WHAT WE NEED
      if (validCloses.length >= 2) {
        previousClose = validCloses[validCloses.length - 2];
        console.log(
          `${ticker}: Using closes[count-2] as previousClose = ${previousClose} (yesterday)`
        );
      } else if (validCloses.length >= 1) {
        previousClose = validCloses[validCloses.length - 1];
        console.log(
          `${ticker}: Using only available close = ${previousClose}`
        );
      }
    }

    // Validation: previousClose should be within reasonable range of current price
    // Reject if it implies >100% daily change (very rare, likely data error)
    if (previousClose !== null && currentPrice > 0) {
      const ratio = currentPrice / previousClose;
      if (ratio < 0.5 || ratio > 2.0) {
        console.warn(
          `${ticker}: previousClose ${previousClose} seems invalid relative to price ${currentPrice}, discarding`
        );
        previousClose = null;
      }
    }

    return {
      price: currentPrice,
      previousClose: previousClose,
      companyName: meta.longName || meta.shortName || ticker,
    };
  } catch (error) {
    console.error(`Error fetching ${ticker}:`, error);
    return null;
  }
}

interface TrackedStock {
  ticker: string;
}

interface StockPriceUpdate {
  ticker: string;
  price: number;
  previous_close: number | null;
  day_change_percent: number | null;
  company_name: string;
  updated_at: string;
}

serve(async (req) => {
  // CORS headers for browser requests
  const corsHeaders = {
    "Access-Control-Allow-Origin": "*",
    "Access-Control-Allow-Headers":
      "authorization, x-client-info, apikey, content-type",
  };

  // Handle preflight requests
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  try {
    // Skip if market is closed (unless force=true query param)
    const url = new URL(req.url);
    const force = url.searchParams.get("force") === "true";
    const singleTicker = url.searchParams.get("ticker");

    if (!isMarketOpen() && !force) {
      return new Response(
        JSON.stringify({
          message: "Market closed, skipping update",
          marketOpen: false,
        }),
        {
          status: 200,
          headers: { ...corsHeaders, "Content-Type": "application/json" },
        }
      );
    }

    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY);

    let tickers: string[];

    if (singleTicker) {
      // Fetch a specific ticker
      tickers = [singleTicker.toUpperCase()];
    } else {
      // Get all tracked stocks from database
      const { data: trackedStocks, error: trackError } = await supabase
        .from("tracked_stocks")
        .select("ticker");

      if (trackError) {
        console.error("Error fetching tracked stocks:", trackError);
        return new Response(
          JSON.stringify({ error: trackError.message }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      if (!trackedStocks?.length) {
        return new Response(
          JSON.stringify({ message: "No stocks to update" }),
          {
            status: 200,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }

      tickers = (trackedStocks as TrackedStock[]).map((s) => s.ticker);
    }

    const updates: StockPriceUpdate[] = [];

    // Fetch prices in batches of 10 to avoid rate limiting
    const batchSize = 10;
    for (let i = 0; i < tickers.length; i += batchSize) {
      const batch = tickers.slice(i, i + batchSize);

      // Fetch all prices in the batch concurrently
      const results = await Promise.all(
        batch.map((ticker) => fetchYahooPrice(ticker))
      );

      batch.forEach((ticker, idx) => {
        const data = results[idx];
        if (data && data.price > 0) {
          const dayChange =
            data.previousClose && data.previousClose > 0
              ? ((data.price - data.previousClose) / data.previousClose) * 100
              : null;

          console.log(`${ticker}: price=${data.price}, prevClose=${data.previousClose}, dayChange=${dayChange?.toFixed(2)}%`);

          updates.push({
            ticker,
            price: data.price,
            previous_close: data.previousClose,
            day_change_percent: dayChange,
            company_name: data.companyName,
            updated_at: new Date().toISOString(),
          });
        }
      });

      // Small delay between batches to be respectful to Yahoo
      if (i + batchSize < tickers.length) {
        await new Promise((r) => setTimeout(r, 500));
      }
    }

    // Upsert all prices to the database
    if (updates.length > 0) {
      const { error: upsertError } = await supabase
        .from("stock_prices")
        .upsert(updates, { onConflict: "ticker" });

      if (upsertError) {
        console.error("Error upserting prices:", upsertError);
        return new Response(
          JSON.stringify({ error: upsertError.message }),
          {
            status: 500,
            headers: { ...corsHeaders, "Content-Type": "application/json" },
          }
        );
      }
    }

    return new Response(
      JSON.stringify({
        updated: updates.length,
        tickers: updates.map((u) => u.ticker),
        marketOpen: isMarketOpen(),
      }),
      {
        status: 200,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  } catch (error) {
    console.error("Edge function error:", error);
    return new Response(
      JSON.stringify({
        error: error instanceof Error ? error.message : "Unknown error",
      }),
      {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      }
    );
  }
});
