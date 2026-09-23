import Foundation
import CryptoKit
import PromiseKit

public struct Chunks {
    let data_root: Data
    let chunks: [Chunk]
    let proofs: [Proof]
}

public typealias TransactionId = String
public typealias Base64EncodedString = String

public extension ArweaveTransaction {
    
    struct PriceRequest {
        
        public init(bytes: Int = 0, target: ArweaveAddress? = nil) {
            self.bytes = bytes
            self.target = target
        }
        
        public var bytes: Int = 0
        public var target: ArweaveAddress?
    }
    
    struct Tag: Codable {
        public let name: String
        public let value: String
        
        public init(name: String, value: String) {
            self.name = name
            self.value = value
        }
    }
}

public struct ArweaveTransaction: Codable {
    public var format = Format.v2
    public var id: TransactionId = ""
    public var last_tx: TransactionId = ""
    public var owner: String = ""
    public var tags = [Tag]()
    public var target: String = ""
    public var quantity: String = "0"
    public var data: String = ""
    public var reward: String = ""
    public var signature: String = ""
    
    
    public var data_root: String = ""
    public var data_size: String = "0"
    public var chunks: Chunks?
    
    private enum CodingKeys: String, CodingKey {
        case format, id, last_tx, owner, tags, target, quantity, data, data_size, data_root, reward, signature
    }
    
    public var priceRequest: PriceRequest {
        PriceRequest(bytes: rawData.count, target: ArweaveAddress(address: target))
    }
    
    public var rawData = Data()
    public enum Format: Int, Codable {
        case v1 = 1
        case v2 = 2
    }
}

public extension ArweaveTransaction {
    init(data: Data) {
        self.rawData = data
        self.data_size = String(data.count)
    }
    
    init(amount: Amount, target: ArweaveAddress) {
        self.quantity = String(describing: amount)
        self.target = target.address
    }
    
    func sign(with wallet: ArweaveWallet) -> Promise<ArweaveTransaction>{
        return Promise { seal in
            var tx = self
            firstly {
                return ArweaveTransaction.anchor()
            }.then { txAnchor -> Promise<Amount> in
                tx.last_tx = txAnchor
                tx.data = rawData.base64URLEncodedString()
                return ArweaveTransaction.price(for: priceRequest)
            }.done({ priceAmount in
                tx.reward = String(describing: priceAmount)
                tx.owner = wallet.ownerModulus
                tx.signatureBody().done({ signBody in
                    do {
                        let signedMessage = try wallet.sign(signBody)
                        tx.signature = signedMessage.base64URLEncodedString()
                        tx.id = SHA256.hash(data: signedMessage).data.base64URLEncodedString()
                        seal.fulfill(tx)
                    }catch {
                        seal.reject(ArweaveApiError.signError)
                    }
                }).catch { error in
                    seal.reject(error)
                }
            }).catch({ error in
                seal.reject(error)
            })
        }
    }
    
    func commit() -> Promise<Data>{
        return Promise { seal in
            guard !signature.isEmpty else {
                seal.reject(ArweaveApiError.otherError(errorMessage: "Missing signature on transaction."))
                return
            }
            let commit = Arweave.shared.request(for: .commit(self))
            HttpClient.request(commit).done { response in
                seal.fulfill(response.data)
            }.catch { error in
                if case let ArweaveApiError.responseError(_, message) = error,
                   !message.isEmpty {
                    seal.reject(ArweaveApiError.otherError(errorMessage: message))
                } else {
                    seal.reject(ArweaveApiError.commitError)
                }
            }
        }
    }
    
    private mutating func signatureBody() -> Promise<Data> {
        switch format {
        case .v1:
            return Promise { seal in
                seal.fulfill([
                    Data(base64URLEncoded: owner),
                    Data(base64URLEncoded: target),
                    rawData,
                    quantity.data(using: .utf8),
                    reward.data(using: .utf8),
                    Data(base64URLEncoded: last_tx),
                    tags.combined.data(using: .utf8)
                ].compactMap { $0 } .combined)
            }
        default:
            if data_root.isEmpty {
                prepareChunks(data: self.rawData)
            }
            return Promise { seal in
                let tagList = tags.map { tag in
                    DeepHashItem.list([
                        .blob(Data(tag.name.utf8)),
                        .blob(Data(tag.value.utf8))
                    ])
                }

                seal.fulfill(ArweaveTransaction.deepHash(items: [
                    .blob(Data(String(format.rawValue).utf8)),
                    .blob(Data(base64URLEncoded: owner) ?? Data()),
                    .blob(Data(base64URLEncoded: target) ?? Data()),
                    .blob(Data(quantity.utf8)),
                    .blob(Data(reward.utf8)),
                    .blob(Data(base64URLEncoded: last_tx) ?? Data()),
                    .list(tagList),
                    .blob(Data(data_size.utf8)),
                    .blob(Data(base64URLEncoded: data_root) ?? Data())
                ]))
            }
        }
    }

    private enum DeepHashItem {
        case blob(Data)
        case list([DeepHashItem])
    }

    private static func deepHash(items: [DeepHashItem]) -> Data {
        let tag = Data("list\(items.count)".utf8)
        var accumulator = tag

        for item in items {
            let itemHash: Data
            switch item {
            case .blob(let data):
                itemHash = deepHash(buffer: data)
            case .list(let nestedItems):
                itemHash = deepHash(items: nestedItems)
            }

            accumulator = Data(SHA384.hash(data: accumulator + itemHash))
        }

        return accumulator
    }

    static func deepHash(buffers: [Data]) -> Data {
        precondition(!buffers.isEmpty)
        let tag = "list".data(using: .utf8)! + String(buffers.count).data(using: .utf8)!
        return deepHashChunks(chunks: buffers, acc: tag)
    }
    
    static func deepHash(buffer: Data) -> Data {
        let tag = "blob".data(using: .utf8)! + String(buffer.count).data(using: .utf8)!
        let taggedHash = Data(SHA384.hash(data: tag)) + Data(SHA384.hash(data: buffer))
        return Data(SHA384.hash(data: taggedHash))
    }
    
    static func deepHashChunks(chunks: [Data], acc: Data) -> Data {
        guard chunks.count >= 1 else { return acc }
        var currentChunks = chunks
        
        let first = currentChunks.removeFirst()
        let hashPair = acc + deepHash(buffer: first)
        let newAcc = Data(SHA384.hash(data: hashPair))
        return deepHashChunks(chunks: currentChunks, acc: newAcc)
    }
}
public extension ArweaveTransaction {
    mutating func prepareChunks(data: Data) {
        if chunks == nil && data.count > 0 {
            chunks = generateTransactionChunks(data: data)
            data_root = chunks!.data_root.base64URLEncodedString()
        }
        
        if chunks == nil && data.count == 0 {
            chunks = Chunks(data_root: Data(), chunks: [], proofs: [])
            data_root = ""
        }
    }
    static func find(_ txId: TransactionId) -> Promise<ArweaveTransaction>{
        return Promise { seal in
            let findEndpoint = Arweave.shared.request(for: .transaction(id: txId))
            HttpClient.request(findEndpoint).done{ response in
                do {
                    let transaction = try JSONDecoder().decode(ArweaveTransaction.self, from: response.data)
                    seal.fulfill(transaction)
                } catch  _ {
                    seal.reject(ArweaveApiError.findError)
                }
            }.catch { _ in
                seal.reject(ArweaveApiError.findError)
            }
        }
    }
    static func data(for txId: TransactionId) -> Promise<Base64EncodedString>{
        return Promise { seal in
            let target = Arweave.shared.request(for: .transactionData(id: txId))
            HttpClient.request(target).done { response in
                seal.fulfill(String(decoding: response.data, as: UTF8.self))
            }.catch { _ in
                seal.reject(ArweaveApiError.getTransactionDataError)
            }
        }
    }
    
    static func status(of txId: TransactionId) -> Promise<ArweaveTransaction.Status>{
        return Promise { seal in
            let target = Arweave.shared.request(for: .transactionStatus(id: txId))
            HttpClient.request(target).done { response in
                do {
                    var status: ArweaveTransaction.Status
                    if response.statusCode == 200 {
                        let data = try JSONDecoder().decode(ArweaveTransaction.Status.Data.self, from: response.data)
                        status = .accepted(data: data)
                    } else {
                        status = ArweaveTransaction.Status(rawValue: .status(response.statusCode))!
                    }
                    seal.fulfill(status)
                } catch _ {
                    seal.reject(ArweaveApiError.transactionStatusError)
                }
            }.catch { _ in
                seal.reject(ArweaveApiError.transactionStatusError)
            }
        }
    }
    
    static func price(for request: ArweaveTransaction.PriceRequest)-> Promise<Amount>{
        return Promise { seal in
            let target = Arweave.shared.request(for: .reward(request))
            HttpClient.request(target).done { response in
                let costString = String(decoding: response.data, as: UTF8.self)
                guard let value = Double(costString) else {
                    seal.reject(ArweaveApiError.priceError)
                    return
                }
                seal.fulfill(Amount(value: value, unit: .winston))
            }.catch { _ in
                seal.reject(ArweaveApiError.priceError)
            }
        }
    }
    
    static func anchor() -> Promise<String>{
        return Promise { seal in
            let target = Arweave.shared.request(for: .txAnchor)
            HttpClient.request(target).done { response in
                let anchor = String(decoding: response.data, as: UTF8.self)
                seal.fulfill(anchor)
            }.catch { _ in
                seal.reject(ArweaveApiError.anchorError)
            }
        }
    }
    static func info() -> Promise<ChainInfo>{
        return Promise { seal in
            let infoR = Arweave.shared.request(for: .chainInfo)
            HttpClient.request(infoR).done { response in
                let info = try JSONDecoder().decode(ChainInfo.self, from: response.data)
                seal.fulfill(info)
            }.catch { _ in
                seal.reject(ArweaveApiError.chainInfoError)
            }
        }
    }
}

extension Array where Element == ArweaveTransaction.Tag {
    var combined: String {
        reduce(into: "") { str, tag in
            str += tag.name
            str += tag.value
        }
    }
}
