//
//  ReceiptAPI.swift
//  Budgetty
//
//  Client for the deployed `extractReceipt` Cloud Function — the SAME backend the Android app uses.
//  Sends a base64 image + a Firebase ID token (Bearer) and decodes the structured receipt. Uses
//  URLSession only; no Firebase SDK needed here (only obtaining the token does).
//

import Foundation

/// Base URL of the deployed `extractReceipt` Cloud Function (gen2, europe-west1).
let receiptAPIBaseURL = "https://extractreceipt-5izrhecgza-ew.a.run.app/"

// MARK: - DTOs (mirror data/remote/ReceiptDtos.kt)

struct ExtractRequest: Encodable {
    let fileBase64: String
    let mimeType: String
}

struct ExtractResponse: Decodable {
    var storeName: String?
    var date: String?
    var discount: Double?
    /// Printed grand total actually paid (after discounts); nil/0 if not printed.
    var total: Double?
    /// Printed sum of line items before tax/fees (equals total when prices include tax); nil/0 if absent.
    var subtotal: Double?
    /// Tax added on top of item prices (0 when prices already include tax); nil/0 if none.
    var tax: Double?
    /// Model self-assessment: false when the image was too poor to read line items reliably.
    var readable: Bool?
    /// Article/item count printed on the receipt; nil/0 if not printed.
    var printedItemCount: Int?
    var items: [ExtractedItem] = []
}

struct ExtractedItem: Decodable {
    var name: String = ""
    var quantity: Double?
    var price: Double?
    var category: String?
}

enum ReceiptAPIError: LocalizedError {
    case unauthorized
    case http(Int)
    case transport(Error)
    case decoding(Error)

    var errorDescription: String? {
        switch self {
        case .unauthorized: "Not signed in. Please try again."
        case .http(let code): "The server returned an error (\(code))."
        case .transport: "Couldn't reach the server. Check your connection."
        case .decoding: "The receipt response couldn't be read."
        }
    }
}

/// Calls the extract endpoint.
struct ReceiptAPI {
    var session: URLSession = .shared

    func extract(imageData: Data, mimeType: String, token: String) async throws -> ExtractResponse {
        guard let url = URL(string: receiptAPIBaseURL + "extractReceipt") else {
            throw ReceiptAPIError.http(-1)
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONEncoder().encode(
            ExtractRequest(fileBase64: imageData.base64EncodedString(), mimeType: mimeType)
        )
        req.timeoutInterval = 60

        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: req)
        } catch {
            throw ReceiptAPIError.transport(error)
        }
        guard let http = response as? HTTPURLResponse else { throw ReceiptAPIError.http(-1) }
        if http.statusCode == 401 { throw ReceiptAPIError.unauthorized }
        guard (200..<300).contains(http.statusCode) else { throw ReceiptAPIError.http(http.statusCode) }

        do {
            return try JSONDecoder().decode(ExtractResponse.self, from: data)
        } catch {
            throw ReceiptAPIError.decoding(error)
        }
    }
}
