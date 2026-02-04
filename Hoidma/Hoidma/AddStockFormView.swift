import SwiftUI

struct AddStockFormView: View {
    @ObservedObject var viewModel: StockViewModel
    @Binding var isPresented: Bool
    var initialAccountName: String = ""

    @State private var tickerInput: String = ""
    @State private var priceInput: String = ""
    @State private var sharesInput: String = ""
    @State private var accountNameInput: String = ""
    @State private var commitError: String? = nil
    @State private var isValidating: Bool = false
    @State private var validationError: String? = nil
    @FocusState private var focusedField: Field?
    @Environment(\.colorScheme) private var colorScheme

    private var isDarkMode: Bool { colorScheme == .dark }

    enum Field {
        case ticker, price, shares, accountName
    }

    /// Get unique account names from existing stocks
    private var existingAccountNames: [String] {
        let allAccounts = viewModel.stocks.flatMap { $0.lots.map { $0.accountName } }
        return Array(Set(allAccounts)).sorted()
    }

    /// Filtered account suggestions based on current input
    private var filteredAccountSuggestions: [String] {
        let input = accountNameInput.lowercased().trimmingCharacters(in: .whitespaces)
        if input.isEmpty {
            return existingAccountNames
        }
        return existingAccountNames.filter { $0.lowercased().contains(input) }
    }

    /// Get unique tickers from existing stocks
    private var existingTickers: [String] {
        viewModel.stocks.map { $0.ticker.uppercased() }.sorted()
    }

    /// Filtered ticker suggestions based on current input
    private var filteredTickerSuggestions: [String] {
        let input = tickerInput.uppercased().trimmingCharacters(in: .whitespaces)
        if input.isEmpty {
            return existingTickers
        }
        return existingTickers.filter { $0.contains(input) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            ZStack {
                HStack {
                    Button {
                        isPresented = false
                    } label: {
                        Image("cancel")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 48, height: 48)
                    }

                    Spacer()
                }

                // Centered title
                Text("Add to Portfolio")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Color.primary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 16)

            // Form fields
            VStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Symbol")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.secondary)

                    TextField("NVDA", text: $tickerInput)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.primary)
                        .textInputAutocapitalization(.characters)
                        .focused($focusedField, equals: .ticker)
                        .disabled(isValidating)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )

                    // Ticker suggestions
                    if !existingTickers.isEmpty && focusedField == .ticker && !filteredTickerSuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(filteredTickerSuggestions, id: \.self) { ticker in
                                    Button {
                                        tickerInput = ticker
                                        focusedField = .accountName
                                    } label: {
                                        Text(ticker)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(tickerInput == ticker ? .white : Color.primary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .fill(tickerInput == ticker ? Color.blue : Color.gray.opacity(0.15))
                                            )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Account Name")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.secondary)

                    TextField("Indv, 401k, Roth IRA, etc.", text: $accountNameInput)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.primary)
                        .focused($focusedField, equals: .accountName)
                        .disabled(isValidating)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )

                    // Account name suggestions
                    if !existingAccountNames.isEmpty && focusedField == .accountName && !filteredAccountSuggestions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(filteredAccountSuggestions, id: \.self) { account in
                                    Button {
                                        accountNameInput = account
                                        focusedField = .price
                                    } label: {
                                        Text(account)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(accountNameInput == account ? .white : Color.primary)
                                            .padding(.horizontal, 12)
                                            .padding(.vertical, 6)
                                            .background(
                                                RoundedRectangle(cornerRadius: 16)
                                                    .fill(accountNameInput == account ? Color.blue : Color.gray.opacity(0.15))
                                            )
                                    }
                                    .buttonStyle(PlainButtonStyle())
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Purchase Price")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.secondary)

                    HStack {
                        Text("$")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.secondary)
                        TextField("22.00", text: $priceInput)
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(Color.primary)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .price)
                            .disabled(isValidating)
                    }
                    .padding(.vertical, 10)
                    .padding(.horizontal, 12)
                    .cornerRadius(8)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Shares")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color.secondary)

                    TextField("9.0000", text: $sharesInput)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color.primary)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .shares)
                        .disabled(isValidating)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 12)
                        .cornerRadius(8)
                        .overlay(
                            RoundedRectangle(cornerRadius: 8)
                                .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                        )
                }

                // Buy button below shares
                Button {
                    attemptCommit()
                } label: {
                    if isValidating {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle())
                            .frame(maxWidth: .infinity)
                            .frame(height: 15)
                            .padding(.vertical, 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppColors.positive.opacity(0.5), lineWidth: 1)
                            )
                    } else {
                        Image(isDarkMode ? "buy.dark" : "buy")
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(maxWidth: .infinity)
                            .frame(height: 15)
                            .padding(.vertical, 6)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(AppColors.positive, lineWidth: 1)
                            )
                    }
                }
                .disabled(isValidating)
            }
            .padding(.horizontal, 20)

            if let error = validationError ?? commitError {
                Text(error)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.red)
                    .padding(.top, 16)
                    .padding(.horizontal, 20)
            }

            Spacer()
        }
        .background(Color(UIColor.systemBackground))
        .onAppear {
            if !initialAccountName.isEmpty {
                accountNameInput = initialAccountName
            }
        }
    }

    private func attemptCommit() {
        // Dismiss keyboard first so error message is visible
        focusedField = nil

        // Clear previous errors
        commitError = nil
        validationError = nil

        // Validate input fields first
        guard !tickerInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            validationError = "Please enter a ticker symbol."
            return
        }

        guard let price = Double(priceInput), let shares = Double(sharesInput), shares > 0 else {
            commitError = "Please enter valid numbers for price and shares."
            return
        }

        // Account name is optional, default to "Main" if empty
        let accountName = accountNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalAccountName = accountName.isEmpty ? "Main" : accountName
        let ticker = tickerInput.uppercased()

        // Start async validation
        isValidating = true

        Task {
            let result = await viewModel.validateTicker(ticker)

            await MainActor.run {
                isValidating = false

                switch result {
                case .valid, .alreadyInPortfolio:
                    // Ticker is valid or already in portfolio, commit and dismiss
                    viewModel.commitStock(ticker: ticker, price: price, shares: shares, accountName: finalAccountName)
                    isPresented = false

                case .invalid(let message):
                    validationError = message

                case .networkError(let message):
                    validationError = message
                }
            }
        }
    }
}
