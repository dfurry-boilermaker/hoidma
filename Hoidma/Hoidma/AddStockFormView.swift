import SwiftUI

struct AddStockFormView: View {
    @ObservedObject var viewModel: StockViewModel
    @Binding var isPresented: Bool
    @AppStorage("isDarkMode") private var isDarkMode: Bool = false
    
    @State private var tickerInput: String = ""
    @State private var priceInput: String = ""
    @State private var sharesInput: String = ""
    @State private var accountNameInput: String = ""
    @State private var commitError: String? = nil
    @FocusState private var focusedField: Field?
    
    enum Field {
        case ticker, price, shares, accountName
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
                Text("Add Stock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Color.primary)
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 30)
            
            // Form fields - clean and simple
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Symbol")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.secondary)
                    
                    TextField("NVDA", text: $tickerInput)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Color.primary)
                        .textInputAutocapitalization(.characters)
                        .focused($focusedField, equals: .ticker)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Account Name")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.secondary)
                    
                    TextField("Indv, 401k, Roth IRA, etc.", text: $accountNameInput)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Color.primary)
                        .focused($focusedField, equals: .accountName)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Purchase Price")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.secondary)
                    
                    HStack {
                        Text("$")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(Color.secondary)
                        TextField("22.00", text: $priceInput)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(Color.primary)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .price)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color(UIColor.secondarySystemBackground))
                    .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shares")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(Color.secondary)
                    
                    TextField("9.0000", text: $sharesInput)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Color.primary)
                        .keyboardType(.decimalPad)
                        .focused($focusedField, equals: .shares)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color(UIColor.secondarySystemBackground))
                        .cornerRadius(8)
                }
                
                // Add button - full width below shares field
                Button {
                    attemptCommit()
                } label: {
                    Text("Add")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundColor(AppColors.positive)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12)
                                .stroke(AppColors.positive, lineWidth: 1)
                        )
                }
                .padding(.top, 8)
            }
            .padding(.horizontal, 20)
            
            if let commitError = commitError {
                Text(commitError)
                    .font(.system(size: 14, weight: .regular))
                    .foregroundColor(.red)
                    .padding(.top, 16)
            }
            
            Spacer()
        }
        .background(Color(UIColor.systemBackground))
    }
    
    private func attemptCommit() {
        guard let price = Double(priceInput), let shares = Double(sharesInput), shares > 0, !tickerInput.isEmpty else {
            commitError = "Please enter valid numbers and a ticker symbol."
            return
        }
        
        // Account name is optional, default to "Main" if empty
        let accountName = accountNameInput.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalAccountName = accountName.isEmpty ? "Main" : accountName
        
        // Call the view model to commit and dismiss the form
        viewModel.commitStock(ticker: tickerInput.uppercased(), price: price, shares: shares, accountName: finalAccountName)
        isPresented = false
    }
}

