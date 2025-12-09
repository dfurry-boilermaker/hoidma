import SwiftUI

struct AddStockFormView: View {
    @ObservedObject var viewModel: StockViewModel
    @Binding var isPresented: Bool
    
    @State private var tickerInput: String = ""
    @State private var priceInput: String = ""
    @State private var sharesInput: String = ""
    @State private var commitError: String? = nil
    @FocusState private var focusedField: Field?
    
    enum Field {
        case ticker, price, shares
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Button {
                    isPresented = false
                } label: {
                    Text("Cancel")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundColor(.gray)
                }
                
                Spacer()
                
                Text("Add Stock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                
                Spacer()
                
                Button {
                    attemptCommit()
                } label: {
                    Text("Add")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(Color(red: 0.231, green: 0.706, blue: 0.494))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 30)
            
            // Form fields - clean and simple
            VStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Symbol")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    TextField("TSLA", text: $tickerInput)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.black)
                        .textInputAutocapitalization(.characters)
                        .focused($focusedField, equals: .ticker)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Purchase Price")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    HStack {
                        Text("$")
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(.gray)
                        TextField("0.00", text: $priceInput)
                            .font(.system(size: 18, weight: .regular))
                            .foregroundColor(.black)
                            .keyboardType(.decimalPad)
                            .focused($focusedField, equals: .price)
                    }
                    .padding(.vertical, 12)
                    .padding(.horizontal, 16)
                    .background(Color.gray.opacity(0.1))
                    .cornerRadius(8)
                }
                
                VStack(alignment: .leading, spacing: 8) {
                    Text("Shares")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundColor(.gray)
                    
                    TextField("0", text: $sharesInput)
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(.black)
                        .keyboardType(.numberPad)
                        .focused($focusedField, equals: .shares)
                        .padding(.vertical, 12)
                        .padding(.horizontal, 16)
                        .background(Color.gray.opacity(0.1))
                        .cornerRadius(8)
                }
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
    }
    
    private func attemptCommit() {
        guard let price = Double(priceInput), let shares = Int(sharesInput), !tickerInput.isEmpty else {
            commitError = "Please enter valid numbers and a ticker symbol."
            return
        }
        
        // Call the view model to commit and dismiss the form
        viewModel.commitStock(ticker: tickerInput.uppercased(), price: price, shares: shares)
        isPresented = false
    }
}

