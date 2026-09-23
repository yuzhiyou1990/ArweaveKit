import XCTest
import CryptoKit
import JOSESwift

@testable import ArweaveKit

final class WalletTests: XCTestCase {

    static let walletAddress = ArweaveAddress(address: "3t2aPa6RArz9ssZ-pEmPiI6rUwAy1v69wm_7Qn0uUt8")
    static var wallet: ArweaveWallet?
    
    class func initWalletFromKeyfile() {
        
        guard let keyPath = Bundle.module.url(forResource: "test-key", withExtension: "json"),
              let keyData = try? Data(contentsOf: keyPath)
        else { return }
        
        WalletTests.wallet = try? ArweaveWallet(jwkFileData: keyData)
        
        XCTAssertNotNil(WalletTests.wallet)
        XCTAssertEqual(WalletTests.walletAddress, WalletTests.wallet?.address)
    }
    
    override class func setUp() {
        super.setUp()
        WalletTests.initWalletFromKeyfile()
    }
    
    func testCheckWalletBalance() throws {
        let expection = expectation(description: "testCheckWalletBalance")
//        DispatchQueue.global(qos: .userInitiated).async {
//            do {
//                let balance = try WalletTests.wallet?.balance().wait()
//                expection.fulfill(balance)
//            } catch ( _) {
//                expection.fulfill()
//            }
//        }
        waitForExpectations(timeout: 10)
    }
    
//    func testCheckWalletBalance_UsingCustomHost() async throws {
//        Arweave.baseUrl = URL(string: "https://arweave.net:443")!
//        let balance = try await WalletTests.wallet?.balance()
//        XCTAssertNotNil(balance?.value)
//    }
//
//    func testFetchLastTransactionId() async throws {
//        let lastTxId = try await WalletTests.wallet?.lastTransactionId()
//        XCTAssertNotNil(lastTxId)
//    }
    func testRandom(){
        
        // Generate keys
        let tag = "com.wm.POD-browser".data(using: .utf8)!
        let attributes: [String: Any] =
        [kSecAttrKeyType as String:  kSecAttrKeyTypeRSA,
         kSecAttrKeySizeInBits as String: 2048,
         kSecPrivateKeyAttrs as String:
            [kSecAttrApplicationTag as String: tag]
        ]
        var error: Unmanaged<CFError>?
        guard let privateKey = SecKeyCreateRandomKey(attributes as CFDictionary, &error) else {
            print(error!.takeRetainedValue() as Error)
            return
        }
       
        
    }
    
    func testGenerateBase64Encoded2048BitRSAKey() throws{
        let type = kSecAttrKeyTypeRSA
        let tag = "com.wm.POD-browser".data(using: .utf8)!
        let attributes: [String: Any] =
        [kSecAttrKeyType as String: type,
         kSecAttrKeySizeInBits as String: 2048
        ]
        
        var error: Unmanaged<CFError>?
        guard let key = SecKeyCreateRandomKey(attributes as CFDictionary, &error),
              let data = SecKeyCopyExternalRepresentation(key, &error) as Data?,
              let publicKey = SecKeyCopyPublicKey(key),
              let publicKeyData = SecKeyCopyExternalRepresentation(publicKey, &error) as Data? else {
                  throw error!.takeRetainedValue() as Error
              }
        let modulus = publicKeyData[(publicKeyData.count > 269 ? 9:8)...]
        let exponent = publicKeyData[(publicKeyData.count - 3)..<publicKeyData.count]
        
        let  rsaPrivateKeyComponents = try key.rsaPrivateKeyComponents()
        
        let keypair = try RSAKeyPair(privateKey: SecKey.representing(rsaPrivateKeyComponents: rsaPrivateKeyComponents))
        let jsonData = try JSONSerialization.data(withJSONObject: keypair.requiredParameters, options: .prettyPrinted)
            // here "jsonData" is the dictionary encoded in JSON data

        let theJSONText = String(data: jsonData,
                                       encoding: .ascii)
            print("JSON string = \(theJSONText!)")
        let address = ArweaveAddress(from: keypair.modulus)
        print("address = \(address)")
    }
    
    func testNewWallet() throws{
        let wallet = try ArweaveWallet()
        let theJSONText = String(data: wallet.keyData,
                                       encoding: .ascii)
        print("JSON string = \(theJSONText!)",wallet.address.address)
    }
    func testSignMessage() throws {
        let msg = try XCTUnwrap("Arweave".data(using: .utf8))
        let wallet = try XCTUnwrap(WalletTests.wallet)
        let signedData = try wallet.sign(msg)

        let hash = SHA256.hash(data: signedData).data.base64URLEncodedString()
        XCTAssertNotNil(hash)
    }

    func testWinstonToARConversion() {
        var transferAmount = Amount(value: 1, unit: .AR)
        let amtInWinston = transferAmount.converted(to: .winston)
        XCTAssertEqual(amtInWinston.value, 1000000000000, accuracy: 0e-12)

        transferAmount = Amount(value: 2, unit: .winston)
        let amtInAR = transferAmount.converted(to: .AR)
        XCTAssertEqual(amtInAR.value, 0.000000000002, accuracy: 0e-12)
    }

    func testTransferTransactionDefaultsToV2() {
        let transaction = ArweaveTransaction(
            amount: Amount(value: 1, unit: .winston),
            target: ArweaveAddress(address: "target")
        )

        XCTAssertEqual(transaction.format, .v2)
        XCTAssertEqual(transaction.data_size, "0")
    }
}
