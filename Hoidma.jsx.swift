import React, { useState, useEffect, useMemo } from 'react';
import { getFirestore, doc, setDoc, onSnapshot } from 'firebase/firestore';
import { initializeApp } from 'firebase/app';
import { getAuth, signInAnonymously, signInWithCustomToken } from 'firebase/auth';
import { Diamond, PlusCircle, Trash2, Database } from 'lucide-react';

// NOTE: This application is designed to mimic an iOS app's look and feel,
// using React and Tailwind CSS in a single file.
// Stock price data is simulated for demo purposes.

// --- GLOBAL CONFIGURATION (Provided by Canvas Environment) ---
// These variables ensure data persistence via Firebase/Firestore.
const appId = typeof __app_id !== 'undefined' ? __app_id : 'default-app-id';
const firebaseConfig = JSON.parse(typeof __firebase_config !== 'undefined' ? __firebase_config : '{}');
// FIX: Safely check if the global variable exists before accessing it.
const initialAuthToken = typeof __initial_auth_token !== 'undefined' ? __initial_auth_token : null;

// --- UTILITY: Mock Stock Data Function ---
// Simulates real-time price fluctuation based on the purchase price.
const generateMockData = (initialPrice, purchasePrice) => {
  // Base price starts slightly above the purchase price for fluctuation base
  const initialSeedPrice = purchasePrice * 1.05;
  // Simulate real-time price feed with fluctuation (e.g., +/- 20% range)
  const currentPrice = initialSeedPrice * (1 + (Math.random() - 0.5) * 0.4);
  const change = currentPrice - purchasePrice;
  const changePercent = (change / purchasePrice) * 100;
  const status = currentPrice > purchasePrice ? 'green' : 'red';
  
  return {
    currentPrice: parseFloat(currentPrice.toFixed(2)),
    change: parseFloat(change.toFixed(2)),
    changePercent: parseFloat(changePercent.toFixed(2)),
    status,
  };
};

// --- MAIN APP COMPONENT ---
const App = () => {
  // Firebase State
  const [db, setDb] = useState(null);
  const [userId, setUserId] = useState(null);
  const [isAuthReady, setIsAuthReady] = useState(false);
  const [error, setError] = useState('');

  // App State
  const [stock, setStock] = useState(null);
  const [tickerInput, setTickerInput] = useState('');
  const [priceInput, setPriceInput] = useState('');
  const [sharesInput, setSharesInput] = useState('');
  const [isAdding, setIsAdding] = useState(false);
  const [showModal, setShowModal] = useState(false);

  // --- 1. Firebase Initialization and Authentication ---
  useEffect(() => {
    try {
      const app = initializeApp(firebaseConfig);
      const firestore = getFirestore(app);
      const firebaseAuth = getAuth(app);
      setDb(firestore);

      const signIn = async () => {
        const auth = firebaseAuth;
        // Now safely using initialAuthToken
        if (initialAuthToken) {
          await signInWithCustomToken(auth, initialAuthToken);
        } else {
          await signInAnonymously(auth);
        }
        setUserId(auth.currentUser?.uid || crypto.randomUUID());
        setIsAuthReady(true);
        // setLogLevel('Debug'); // Enable debug logs for Firebase
      };
      signIn();
    } catch (e) {
      console.error("Firebase initialization failed:", e);
      setError("Failed to connect to backend services.");
    }
  }, []);

  // --- 2. Data Listener (Firestore) ---
  useEffect(() => {
    if (!db || !userId) return;

    // Data path: /artifacts/{appId}/users/{userId}/conviction_stocks/the_bag
    const stockRef = doc(db, `artifacts/${appId}/users/${userId}/conviction_stocks`, 'the_bag');

    const unsubscribe = onSnapshot(stockRef, (doc) => {
      if (doc.exists() && doc.data().isMaritalStatus !== false) {
        const data = doc.data();
        setStock({
          ...data,
          isMaritalStatus: true,
        });
      } else {
        // Use a placeholder object when no stock is committed
        setStock({ isMaritalStatus: false });
      }
    }, (e) => {
      console.error("Firestore subscription failed:", e);
      setError("Failed to listen for stock data updates.");
    });

    return () => unsubscribe();
  }, [db, userId]);

  // --- 3. Core Logic Functions ---

  const handleAddStock = async () => {
    if (!tickerInput || !priceInput || !sharesInput || !db || !userId) {
        setError("Please fill in all fields.");
        return;
    }

    const newStock = {
      ticker: tickerInput.toUpperCase(),
      purchasePrice: parseFloat(priceInput),
      shares: parseInt(sharesInput, 10),
      purchaseDate: new Date(),
    };

    try {
      const stockRef = doc(db, `artifacts/${appId}/users/${userId}/conviction_stocks`, 'the_bag');
      await setDoc(stockRef, newStock);
      setIsAdding(false);
      setError('');
      setTickerInput('');
      setPriceInput('');
      setSharesInput('');
    } catch (e) {
      console.error("Failed to add stock:", e);
      setError("Could not save stock. Check console for details.");
    }
  };

  const handleRemoveStock = async () => {
    if (!db || !userId) return;
    setShowModal(false);

    try {
      const stockRef = doc(db, `artifacts/${appId}/users/${userId}/conviction_stocks`, 'the_bag');
      // Set 'isMaritalStatus: false' to signify the stock has been 'un-married'
      await setDoc(stockRef, { isMaritalStatus: false }, { merge: true });
      setStock({ isMaritalStatus: false }); // Update local state immediately
      setError('');
    } catch (e) {
      console.error("Failed to remove stock:", e);
      setError("Could not un-marry stock.");
    }
  };
  
  // Simulated Market Performance (Runs every 5 seconds)
  const [marketData, setMarketData] = useState(null);
  useEffect(() => {
    if (!stock || !stock.ticker) return;

    const updateMarketData = () => {
      // Simulate price fluctuation using the derived initialSeedPrice
      const data = generateMockData(stock.purchasePrice * 1.05, stock.purchasePrice);
      setMarketData(data);
    };

    updateMarketData(); // Run immediately on load/update
    const interval = setInterval(updateMarketData, 5000); // Update every 5 seconds

    return () => clearInterval(interval);
  }, [stock?.ticker, stock?.purchasePrice]);

  // --- Derived Calculations ---
  const { currentPrice, change, changePercent, status } = marketData || {};

  const currentValue = useMemo(() => {
    return (currentPrice && stock?.shares) ? currentPrice * stock.shares : 0;
  }, [currentPrice, stock?.shares]);

  const totalCost = useMemo(() => {
    return (stock?.purchasePrice && stock?.shares) ? stock.purchasePrice * stock.shares : 0;
  }, [stock?.purchasePrice, stock?.shares]);

  const profitLoss = useMemo(() => {
    return currentValue - totalCost;
  }, [currentValue, totalCost]);

  const pLPercent = useMemo(() => {
    return totalCost ? (profitLoss / totalCost) * 100 : 0;
  }, [profitLoss, totalCost]);

  // Ironic Conviction Prompts
  const convictionText = useMemo(() => {
    if (!stock?.isMaritalStatus) return "Ready to commit?";
    
    if (pLPercent < -25) {
      return "This price is a gift! If you truly believe, now is the time to finalize your conviction and *average down*.";
    } else if (pLPercent < -10) {
      return "True conviction isn't measured in green. Stick to your thesis, or prepare to be labeled 'paper hands' forever!";
    } else if (pLPercent < 0) {
      return "Patience is a virtue. This is the ultimate test of your research. Hoidma (Hold Fast)!";
    } else if (pLPercent < 15) {
      return "A little green isn't enough to sell. You committed to the future, not a fleeting gain. Let the good times run!";
    } else {
      return "You're a genius! Now prove your long-term thesis by letting it run. The wedding party has just begun!";
    }
  }, [pLPercent, stock?.isMaritalStatus]);

  // --- UI Components ---

  const Header = () => (
    <div className="flex justify-between items-center p-4 border-b border-gray-700 bg-gray-800 rounded-t-xl shadow-lg">
      <h1 className="text-3xl font-extrabold text-yellow-400 tracking-wider">HOIDMA</h1>
      <Diamond className="text-yellow-400 h-7 w-7" />
    </div>
  );

  const StockDisplay = () => (
    <div className="p-6 space-y-6">
      <div className="flex justify-between items-center">
        <h2 className="text-4xl font-extrabold" style={{ color: status === 'green' ? '#10B981' : '#EF4444' }}>
          {stock.ticker}
        </h2>
        <button
          onClick={() => setShowModal(true)}
          className="p-3 bg-red-600 hover:bg-red-700 text-white rounded-full transition duration-150 shadow-md"
          aria-label="Un-Marry Stock"
        >
          <Trash2 className="w-5 h-5" />
        </button>
      </div>

      <div className="grid grid-cols-2 gap-4 text-gray-300">
        <StatCard label="Current Price" value={`$${currentPrice.toFixed(2)}`} />
        <StatCard label="Purchase Price" value={`$${stock.purchasePrice.toFixed(2)}`} />
        <StatCard label="Shares Owned" value={stock.shares.toLocaleString()} />
        <StatCard label="Total Cost" value={`$${totalCost.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}`} />
      </div>
      
      <div className="bg-gray-700 p-4 rounded-xl shadow-inner">
        <div className="text-sm font-semibold text-gray-400 mb-1">P/L (Total Value)</div>
        <div className="text-3xl font-bold">
          <span className={status === 'green' ? 'text-green-400' : 'text-red-400'}>
            ${profitLoss.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}
          </span>
          <span className={`ml-3 text-lg font-mono ${status === 'green' ? 'text-green-500' : 'text-red-500'}`}>
            ({pLPercent.toFixed(2)}%)
          </span>
        </div>
        <div className="text-sm font-semibold text-gray-400 mt-2">
          Current Value: <span className="text-white">${currentValue.toLocaleString(undefined, { minimumFractionDigits: 2, maximumFractionDigits: 2 })}</span>
        </div>
      </div>

      <ConvictionCard text={convictionText} status={status} />

    </div>
  );

  const StatCard = ({ label, value }) => (
    <div className="bg-gray-700 p-3 rounded-lg shadow-md">
      <div className="text-xs font-medium text-gray-400">{label}</div>
      <div className="text-lg font-semibold text-white truncate">{value}</div>
    </div>
  );

  const ConvictionCard = ({ text, status }) => (
    <div className={`p-4 rounded-xl shadow-xl ${status === 'green' ? 'bg-green-800/30 border-green-500' : 'bg-red-800/30 border-red-500'} border-2`}>
      <div className="flex items-center space-x-3 mb-2">
        <Diamond className="w-6 h-6 text-yellow-400" />
        <h3 className="text-xl font-bold text-white">Conviction Check</h3>
      </div>
      <p className="text-lg text-gray-100 italic">"{text}"</p>
    </div>
  );

  const InitialView = () => (
    <div className="flex flex-col items-center justify-center p-8 text-center space-y-6">
      <Diamond className="w-16 h-16 text-yellow-400" />
      <h2 className="text-2xl font-bold text-white">Choose Your Life Partner</h2>
      <p className="text-gray-400">Commit to a stock and practice **Hoidma** (The Art of Holding).</p>
      <button
        onClick={() => setIsAdding(true)}
        className="flex items-center justify-center px-6 py-3 bg-yellow-600 hover:bg-yellow-700 text-white font-semibold rounded-full shadow-lg transition duration-150"
      >
        <PlusCircle className="w-5 h-5 mr-2" />
        Commit to a Stock
      </button>
    </div>
  );

  const AddStockForm = () => (
    <div className="p-6 space-y-4">
      <h2 className="text-2xl font-bold text-white">The Vows</h2>
      <input
        type="text"
        placeholder="Ticker Symbol (e.g., TSLA)"
        value={tickerInput}
        onChange={(e) => setTickerInput(e.target.value)}
        className="w-full p-3 bg-gray-700 text-white rounded-lg border border-gray-600 placeholder-gray-500 focus:ring-yellow-500 focus:border-yellow-500"
      />
      <input
        type="number"
        placeholder="Purchase Price per Share ($)"
        value={priceInput}
        onChange={(e) => setPriceInput(e.target.value)}
        className="w-full p-3 bg-gray-700 text-white rounded-lg border border-gray-600 placeholder-gray-500 focus:ring-yellow-500 focus:border-yellow-500"
      />
      <input
        type="number"
        placeholder="Number of Shares"
        value={sharesInput}
        onChange={(e) => setSharesInput(e.target.value)}
        className="w-full p-3 bg-gray-700 text-white rounded-lg border border-gray-600 placeholder-gray-500 focus:ring-yellow-500 focus:border-yellow-500"
      />
      <button
        onClick={handleAddStock}
        className="w-full py-3 bg-green-600 hover:bg-green-700 text-white font-semibold rounded-full transition duration-150 shadow-lg"
      >
        Finalize Commitment
      </button>
      <button
        onClick={() => setIsAdding(false)}
        className="w-full py-2 text-gray-400 hover:text-gray-200 transition duration-150"
      >
        Cancel
      </button>
    </div>
  );

  const Modal = () => (
    <div className="fixed inset-0 bg-black bg-opacity-70 flex items-center justify-center z-50 p-4">
      <div className="bg-gray-800 p-6 rounded-xl shadow-2xl max-w-sm w-full border border-red-500">
        <h3 className="text-xl font-bold text-red-400 mb-2">Divorce Proceedings</h3>
        <p className="text-gray-300 mb-6">Are you sure you want to end your commitment to **{stock?.ticker}**? Realizing the loss (or gain) means admitting you were wrong (or right, but impatient). This action is non-reversible!</p>
        <div className="flex justify-between space-x-3">
          <button
            onClick={() => setShowModal(false)}
            className="flex-1 py-3 bg-gray-600 hover:bg-gray-700 text-white font-semibold rounded-lg transition duration-150"
          >
            Stay Married (Cancel)
          </button>
          <button
            onClick={handleRemoveStock}
            className="flex-1 py-3 bg-red-600 hover:bg-red-700 text-white font-semibold rounded-lg transition duration-150"
          >
            <Trash2 className="w-5 h-5 inline mr-1" />
            Un-Marry Now
          </button>
        </div>
      </div>
    </div>
  );

  // --- Main Render ---
  return (
    <div className="min-h-screen bg-gray-900 text-white font-sans flex items-start justify-center p-4 sm:p-8">
      <div className="w-full max-w-lg bg-gray-800 rounded-xl shadow-2xl relative">
        <Header />
        
        {error && (
          <div className="p-4 bg-red-800/50 text-red-300 border-l-4 border-red-500">
            <p className="font-semibold">{error}</p>
          </div>
        )}
        
        {!isAuthReady && (
          <div className="flex items-center justify-center p-12 text-yellow-500">
            <Diamond className="w-6 h-6 mr-3 animate-pulse" />
            <p>Awaiting Financial Commitment...</p>
          </div>
        )}

        {isAuthReady && (
          <>
            {isAdding ? (
              <AddStockForm />
            ) : stock?.isMaritalStatus ? (
              <StockDisplay />
            ) : (
              <InitialView />
            )}
          </>
        )}

        <div className="text-xs text-gray-600 p-2 text-center flex justify-between">
          <span>{userId ? `User ID: ${userId.substring(0, 8)}...` : 'User ID Loading'}</span>
          <span><Database className="w-3 h-3 inline mr-1" /> Data Persistence via Firebase</span>
        </div>

      </div>
      {showModal && <Modal />}
    </div>
  );
};

export default App;
