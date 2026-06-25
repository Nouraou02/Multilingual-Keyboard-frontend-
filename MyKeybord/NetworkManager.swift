import Foundation

class NetworkManager {
    static let shared = NetworkManager()
    
    // Updated ngrok URL
    private let apiURL = "https://1e76-113-140-3-91.ngrok-free.app/predict"
    

    // --- CHANGE 1: Change completion to expect an array [String] ---
    func fetchPredictions(for text: String, completion: @escaping ([String]?, String?) -> Void) {
        guard let url = URL(string: apiURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        
        let body: [String: Any] = ["text": text]
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let task = URLSession.shared.dataTask(with: request) { data, _, _ in
                if let data = data,
                   let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                   let preds = json["predictions"] as? [String],
                   let adapter = json["adapter"] as? String {
                    DispatchQueue.main.async { completion(preds, adapter) }
                } else {
                    completion(nil, nil)
                }
            }
            task.resume()
    }
}
