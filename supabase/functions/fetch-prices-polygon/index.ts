import { serve } from "https://deno.land/std@0.168.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SUPABASE_SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;
const POLYGON_API_KEY = Deno.env.get("POLYGON_API_KEY")!;

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

interface PolygonLastTradeResponse {
  status: string;
  results?: {
    T: string; // Ticker
    p: number; // Price
    s: number; // Size (volume)
    t: number; // Timestamp
    x?: number; // Exchange ID
    c?: number[]; // Conditions
  };
}

interface PolygonPreviousCloseResponse {
  ticker: string;
  status: string;
  results?: Array<{
    T?: string; // Ticker
    v: number; // Volume
    vw?: number; // VWAP
    o: number; // Open
    c: number; // Close
    h: number; // High
    l: number; // Low
    t: number; // Timestamp
    n?: number; // Number of transactions
  }>;
}

interface PolygonTickerDetailsResponse {
  status: string;
  results?: {
    ticker: string;
    name: string;
    type?: string;
    active?: boolean;
    market?: string;
  };
}

interface StockPriceData {
  price: number;
  previousClose: number | null;
  companyName: string;
  volume: number | null;
  open: number | null;
  high: number | null;
  low: number | null;
  vwap: number | null;
}

async function fetchPolygonPrice(
  ticker: string
): Promise<StockPriceData | null> {
  if (!POLYGON_API_KEY) {
    console.error("POLYGON_API_KEY not configured");
    return null;
  }

  try {
    // Fetch last trade for current price
    const lastTradeUrl = `https://api.polygon.io/v2/last/trade/${encodeURIComponent(
      ticker
    )}?apiKey=${POLYGON_API_KEY}`;

    const tradeResp = await fetch(lastTradeUrl, {
      headers: {
        Accept: "application/json",
      },
    });

    if (!tradeResp.ok) {
      console.error(
        `Polygon last trade API error for ${ticker}: ${tradeResp.status}`
      );
      return null;
    }

    const tradeData: PolygonLastTradeResponse = await tradeResp.json();

    if (tradeData.status !== "OK" || !tradeData.results) {
      console.error(`No trade data for ${ticker}`);
      return null;
    }

    const currentPrice = tradeData.results.p;
    const tradeVolume = tradeData.results.s;

    // Fetch previous close (includes OHLCV data)
    const prevCloseUrl = `https://api.polygon.io/v2/aggs/ticker/${encodeURIComponent(
      ticker
    )}/prev?adjusted=true&apiKey=${POLYGON_API_KEY}`;

    const prevResp = await fetch(prevCloseUrl, {
      headers: {
        Accept: "application/json",
      },
    });

    let previousClose: number | null = null;
    let volume: number | null = tradeVolume;
    let open: number | null = null;
    let high: number | null = null;
    let low: number | null = null;
    let vwap: number | null = null;

    if (prevResp.ok) {
      const prevData: PolygonPreviousCloseResponse = await prevResp.json();
      if (
        prevData.status === "OK" &&
        prevData.results &&
        prevData.results.length > 0
      ) {
        const bar = prevData.results[0];
        previousClose = bar.c;
        volume = bar.v;
        open = bar.o;
        high = bar.h;
        low = bar.l;
        vwap = bar.vw || null;

        console.log(
          `${ticker}: previousClose=${previousClose}, open=${open}, high=${high}, low=${low}, volume=${volume}`
        );
      }
    }

    // Fetch company details for name
    const detailsUrl = `https://api.polygon.io/v3/reference/tickers/${encodeURIComponent(
      ticker
    )}?apiKey=${POLYGON_API_KEY}`;

    const detailsResp = await fetch(detailsUrl, {
      headers: {
        Accept: "application/json",
      },
    });

    let companyName = ticker;
    if (detailsResp.ok) {
      const detailsData: PolygonTickerDetailsResponse = await detailsResp.json();
      if (detailsData.status === "OK" && detailsData.results) {
        companyName = detailsData.results.name || ticker;
      }
    }

    console.log(
      `${ticker}: Fetched from Polygon.io - price=${currentPrice}, prevClose=${previousClose}`
    );

    return {
      price: currentPrice,
      previousClose: previousClose,
      companyName: companyName,
      volume: volume,
      open: open,
      high: high,
      low: low,
      vwap: vwap,
    };
  } catch (error) {
    console.error(`Error fetching ${ticker} from Polygon.io:`, error);
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
  volume: number | null;
  open: number | null;
  high: number | null;
  low: number | null;
  vwap: number | null;
  data_source: string;
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

    // Polygon Starter tier: Unlimited API calls
    // Process in larger batches for better performance
    const batchSize = 50;
    for (let i = 0; i < tickers.length; i += batchSize) {
      const batch = tickers.slice(i, i + batchSize);

      // Fetch all prices in the batch concurrently
      const results = await Promise.all(
        batch.map((ticker) => fetchPolygonPrice(ticker))
      );

      batch.forEach((ticker, idx) => {
        const data = results[idx];
        if (data && data.price > 0) {
          const dayChange =
            data.previousClose && data.previousClose > 0
              ? ((data.price - data.previousClose) / data.previousClose) * 100
              : null;

          console.log(
            `${ticker}: price=${data.price}, prevClose=${data.previousClose}, dayChange=${dayChange?.toFixed(
              2
            )}%`
          );

          updates.push({
            ticker,
            price: data.price,
            previous_close: data.previousClose,
            day_change_percent: dayChange,
            company_name: data.companyName,
            volume: data.volume,
            open: data.open,
            high: data.high,
            low: data.low,
            vwap: data.vwap,
            data_source: "polygon",
            updated_at: new Date().toISOString(),
          });
        }
      });

      // No delay needed between batches (unlimited API calls on Starter tier)
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
        dataSource: "polygon",
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
