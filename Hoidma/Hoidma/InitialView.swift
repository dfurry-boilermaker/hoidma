import SwiftUI

struct InitialView: View {
    @Binding var showingCommitForm: Bool
    
    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            
            VStack(spacing: 16) {
                Text("No positions")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundColor(.black)
                
                Text("Start by adding a stock to track")
                    .font(.system(size: 16, weight: .regular))
                    .foregroundColor(.gray)
            }
            .padding(.bottom, 40)
            
            Button {
                showingCommitForm = true
            } label: {
                Text("Add Stock")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(Color(red: 0.231, green: 0.706, blue: 0.494))
                    .cornerRadius(12)
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 40)
            
            Spacer()
        }
    }
}

