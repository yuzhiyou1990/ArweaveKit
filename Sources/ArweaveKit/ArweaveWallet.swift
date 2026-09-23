import Foundation
import JOSESwift
import CryptoKit
import PromiseKit

public struct ArweaveWallet: Codable, Hashable, Comparable {
    
    public var key: RSAPrivateKey
    public let keyData: Data
    public var ownerModulus: String
    public var address: ArweaveAddress

    private enum CodingKeys: String, CodingKey {
        case keyData, ownerModulus, address
    }
    
    public static func < (lhs: ArweaveWallet, rhs: ArweaveWallet) -> Bool {
        lhs.address < rhs.address
    }
    
    public static func == (lhs: ArweaveWallet, rhs: ArweaveWallet) -> Bool {
        lhs.address == rhs.address
    }
    
    public func hash(into hasher: inout Hasher) {
        hasher.combine(keyData)
    }
    
    public init(jwkFileData: Data) throws {
        let jwk = try RSAPrivateKey(data: jwkFileData)
        key = jwk
        keyData = jwkFileData
        ownerModulus = key.modulus
        address = ArweaveAddress(from: key.modulus)
    }
    public init() throws{
        let type = kSecAttrKeyTypeRSA
        let attributes: [String: Any] =
        [kSecAttrKeyType as String: type,
         kSecAttrKeySizeInBits as String: 2048
        ]
        var error: Unmanaged<CFError>?
        guard let _key = SecKeyCreateRandomKey(attributes as CFDictionary, &error)else {
                  throw error!.takeRetainedValue() as Error
              }
        let  rsaPrivateKeyComponents = try _key.rsaPrivateKeyComponents()
        
        let keypair = try RSAPrivateKey(privateKey: SecKey.representing(rsaPrivateKeyComponents: rsaPrivateKeyComponents))
        let jsonData = try JSONSerialization.data(withJSONObject: keypair.requiredParameters, options: .prettyPrinted)
        keyData = jsonData
        ownerModulus = keypair.modulus
        address = ArweaveAddress(from: keypair.modulus)
        key = keypair
    }
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let data = try container.decode(Data.self, forKey: .keyData)
        try self.init(jwkFileData: data)
    }
    
    static public func balance(address: ArweaveAddress) -> Promise<Amount>{
        return Promise { seal in
            let target = Arweave.shared.request(for: .walletBalance(walletAddress: address))
            HttpClient.request(target).done { response in
                let respString = String(decoding: response.data, as: UTF8.self)
                guard let balance = Double(respString) else {
                    seal.reject(ArweaveApiError.getBalanceError)
                    return
                }
                let amount = Amount(value: balance, unit: .winston)
                seal.fulfill(amount)
            }.catch { _ in
                seal.reject(ArweaveApiError.getBalanceError)
            }
        }
    }
    
    static public func lastTransactionId(address: ArweaveAddress) ->Promise<TransactionId>{
        return Promise { seal in
            let target = Arweave.shared.request(for: .lastTransactionId(walletAddress: address))
            HttpClient.request(target).done { response in
                let lastTx = String(decoding: response.data, as: UTF8.self)
                seal.fulfill(lastTx)
            }.catch { _ in
                seal.reject(ArweaveApiError.getLastTransactionIdError)
            }
        }
    }

    public func sign(_ message: Data) throws -> Data {
        let privateKey: SecKey = try key.converted(to: SecKey.self)

        let algorithm: SecKeyAlgorithm = .rsaSignatureMessagePSSSHA256
        var error: Unmanaged<CFError>?
        guard let signature = SecKeyCreateSignature(privateKey,
                                                    algorithm,
                                                    message as CFData,
                                                    &error) as Data? else {
                                                        throw error!.takeRetainedValue() as Error
        }
        return signature
    }
}

public struct ArweaveAddress: Hashable, Codable, Equatable, Comparable, CustomStringConvertible {
    
    public let address: String
    public var description: String { address }

    public init(address: String) {
        self.address = address
    }
    public func data() -> Data?{
        return address.data(using: .utf8)
    }
    public static func address(data: Data) -> String?{
        return String(data: data, encoding: .utf8)
    }
    public static func < (lhs: ArweaveAddress, rhs: ArweaveAddress) -> Bool {
        lhs.address < rhs.address
    }
}

public extension ArweaveAddress {
    init(from modulus: String) {
        guard let data = Data(base64URLEncoded: modulus) else {
            preconditionFailure("Invalid base64 value for JWK public modulus (n) property.")
        }
        let digest = SHA256.hash(data: data)
        address = digest.data.base64URLEncodedString()
    }
    func base64urlToBase64() -> Data? {
        var base64 = self.address
            .replacingOccurrences(of: "-", with: "+")
            .replacingOccurrences(of: "_", with: "/")
        if base64.count % 4 != 0 {
            base64.append(String(repeating: "=", count: 4 - base64.count % 4))
        }
        guard let decodedData = Data(base64Encoded: base64) else {
            return nil
        }
        return decodedData
    }
}
