//
//  File.swift
//
//
//  Created by li shuai on 2022/1/18.
//

import Foundation


public enum ArweaveApiError: Error {
    case unknown
    case findError
    case getTransactionDataError
    case transactionStatusError
    case priceError
    case anchorError
    case chainInfoError
    case commitError
    case signError
    case getBalanceError
    case getLastTransactionIdError
    case otherError(errorMessage: String)
    case responseError(stateCode: Int, message: String)
}
